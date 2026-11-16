// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation
import RetromacCore

@Observable @MainActor
final class GamesModel {
    var dats: [SystemID: DatFile] = [:]
    var datError: String?
    var datProgress: String?
    /// Consoles retromac can install an emulator for; others are filed and wait for a later update.
    /// Switch has no manifest entry: the user installs Ryubing (see SwitchSetupCard).
    let installable: Set<SystemID> = Set((try? Manifest.bundled())?.installableSystems ?? []).union([.switch])
    private var analysis: Task<Void, Never>?
    var candidates: [ImportCandidate] = []
    /// What's running; each is shown and cancelled separately, and only one copy can run at a time.
    var analyzing = false
    var committing = false
    var updatingDats = false
    var converting = false
    var busy: Bool { analyzing || committing || updatingDats || converting }
    /// PS1/Saturn cue sets that could become CHD; 0 without Homebrew, which hides the option.
    var convertibleCount = 0
    var convertProgress: String?
    var message: String?
    /// Files scanned so far and the total, while scanning.
    var scanProgress: (scanned: Int, total: Int)?
    /// Games per system already in the library, from the home/library screens' scan.
    var librarySystems: [SystemID: Int] = [:]

    var summary: ImportSummary? { candidates.isEmpty ? nil : Importer.summarize(candidates) }

    private let paths: Paths
    private let libraryRoot: () -> URL
    /// Re-applies configs: ES-DE lists Xbox only once its BIOS is present, and PCSX2 is pointed at a new PS2 BIOS.
    private let biosAdded: () -> Void
    /// Everything dropped since the last Add/Clear; re-analyzed together so duplicates across drops are caught.
    private var dropped: [URL] = []
    private var session: ImportSession?
    /// Bumped per analysis; a result from an older analysis is discarded, so overlapping drops can't
    /// replace a newer list with a stale one.
    private var generation = 0

    /// A network library: nothing is imported, converted or cleaned up there.
    let readOnly: () -> Bool

    init(paths: Paths, libraryRoot: @escaping () -> URL, readOnly: @escaping () -> Bool = { false }, biosAdded: @escaping () -> Void = {}) {
        self.readOnly = readOnly
        self.paths = paths
        self.libraryRoot = libraryRoot
        self.biosAdded = biosAdded
        dats = DatStore(paths: paths).load()
    }

    var toAdd: Int { candidates.filter(Self.addable).count }

    /// Candidates that commit copies into the library.
    static func addable(_ item: ImportCandidate) -> Bool {
        guard item.destination != nil else { return false }
        switch item.status {
        case .identified, .unverified, .unidentified, .bios: return true
        default: return false
        }
    }

    func importDats(_ urls: [URL]) {
        defer { dats = DatStore(paths: paths).load() }
        do {
            let outcomes = try DatStore(paths: paths).importDats(urls, runner: ProcessRunner())
            let skipped = outcomes.filter { $0.imported == nil }.count
            datError = outcomes.allSatisfy({ $0.imported == nil })
                ? "None of those files are DATs for a supported system."
                : skipped > 0 ? "Skipped \(skipped) file\(skipped == 1 ? "" : "s") for other systems or variants." : nil
        } catch {
            datError = "Couldn't import: \(error.localizedDescription)"
        }
    }

    func analyze(_ urls: [URL]) async {
        guard !committing, !updatingDats else { return }
        dropped += urls
        analysis?.cancel()
        let task = Task { await reanalyze() }
        analysis = task
        await task.value
    }

    /// Stops a running analysis; the dropped items are forgotten.
    func cancel() {
        guard analyzing else { return }
        analysis?.cancel()
        generation += 1
        dropped = []
        candidates = []
        session = nil
        analyzing = false
        message = "Cancelled."
    }

    func updated(_ system: SystemID) -> Date? { DatStore(paths: paths).updated(system) }

    func updateDats() async {
        guard !busy else { return }
        updatingDats = true
        defer { updatingDats = false; datProgress = nil }
        let results = await DatUpdater.update(store: DatStore(paths: paths), downloader: URLSessionDownloader(),
                                              runner: ProcessRunner()) { done, total in
            Task { @MainActor in self.datProgress = "Downloading \(done + 1) of \(total)…" }
        }
        dats = DatStore(paths: paths).load()
        let failed = results.filter { if case .failure = $0.1 { true } else { false } }.map { $0.0.displayName }
        datError = failed.isEmpty ? nil : "Couldn't update: \(failed.joined(separator: ", ")). Try again later."
    }

    private func reanalyze() async {
        generation += 1
        let mine = generation
        analyzing = true
        message = nil
        let importer = Importer(libraryRoot: libraryRoot(), dats: DatStore(paths: paths), runner: ProcessRunner(),
                                biosDirectory: paths.retroarchSystem)
        let urls = dropped
        // Reusing the session keeps already-unpacked archives instead of unpacking them again.
        let previous = session
        scanProgress = (0, 0)
        defer { if mine == generation { scanProgress = nil } }
        let worker = Task.detached {
            Result {
                try importer.analyze(urls, reusing: previous) { scanned, total in
                    Task { @MainActor in if mine == self.generation { self.scanProgress = (scanned, total) } }
                }
            }
        }
        let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        guard mine == generation else { return }
        analyzing = false
        switch result {
        case .success(let (session, candidates)):
            self.session = session
            self.candidates = candidates
        case .failure(let error):
            message = "Couldn't read the dropped files: \(error.localizedDescription)"
        }
    }

    func commit() async {
        guard let session, !busy else { return }
        committing = true
        defer { committing = false }
        let committed = dropped
        // Read at commit time: the library may have become the (read-only) network share since the scan.
        let importer = Importer(libraryRoot: libraryRoot(), dats: DatStore(paths: paths), runner: ProcessRunner(),
                                biosDirectory: paths.retroarchSystem, readOnly: readOnly())
        let pending = candidates
        do {
            let added = try await Task.detached { try importer.commit(session, pending) }.value
            let count = added.filter(Self.addable).count
            candidates = added
            // Only what this commit covered; anything dropped meanwhile stays queued.
            dropped.removeFirst(min(committed.count, dropped.count))
            self.session = nil
            if added.contains(where: { if case .bios(let system, _) = $0.status { system == .xbox || system == .ps2 } else { false } }) { biosAdded() }
            message = "Imported \(count.formatted()) game\(count == 1 ? "" : "s"). Click Play to start."
        } catch ImportError.readOnlyLibrary {
            message = "Games come from your network library, so Add Games is off. Turn the network library off to add games here."
        } catch ImportError.notEnoughSpace(let needed, let free) {
            let format = { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
            message = "Not enough space: needs \(format(needed)), \(format(free)) free. Nothing was copied."
        } catch {
            message = "Couldn't add games: \(error.localizedDescription)"
        }
    }

    func refreshConvertible() {
        guard !readOnly() else { convertibleCount = 0; return }
        if !converting { ChdTool.removeLeftovers(in: libraryRoot()) }
        convertibleCount = ChdTool(runner: ProcessRunner()).hasHomebrew ? ChdTool.convertible(in: libraryRoot()).count : 0
    }

    /// Converts every PS1/Saturn cue set and PS2 disc image to CHD, one game at a time; a game that fails keeps its files.
    func convertToCHD() async {
        guard !busy, !readOnly() else { return }
        converting = true
        defer {
            converting = false
            convertProgress = nil
            refreshConvertible()
        }
        message = nil
        let tool = ChdTool(runner: ProcessRunner())
        if !tool.hasChdman {
            convertProgress = "Installing chdman with Homebrew…"
            do {
                try await Task.detached { try tool.installChdman() }.value
            } catch {
                message = "Couldn't install chdman with Homebrew: \(Self.firstLine(error))"
                return
            }
        }
        // Re-read after the chdman install, which takes minutes: the library may be the share by now.
        let cues = ChdTool.convertible(in: libraryRoot(), readOnly: readOnly())
        var failed: [String] = []
        for (index, cue) in cues.enumerated() {
            let stem = cue.deletingPathExtension().lastPathComponent
            convertProgress = "Converting \((index + 1).formatted()) of \(cues.count.formatted()): \(stem)"
            do {
                _ = try await Task.detached { try tool.convert(disc: cue) }.value
            } catch {
                failed.append(stem)
            }
            // Multi-disc playlists now name the .chd.
            DiscSets.organizeAfterConversion(of: cue)
        }
        let converted = cues.count - failed.count
        message = ([converted > 0 ? "Converted \(converted.formatted()) disc game\(converted == 1 ? "" : "s") to CHD." : nil]
            + failed.map { "Couldn't convert \($0) — the original files are untouched." }).compactMap { $0 }.joined(separator: "\n")
    }

    private static func firstLine(_ error: Error) -> String {
        if case InstallError.commandFailed(_, _, let stderr) = error, let line = stderr.split(separator: "\n").last {
            return String(line)
        }
        return error.localizedDescription
    }

    func clear() {
        dropped = []
        candidates = []
        session = nil
        message = nil
    }
}
