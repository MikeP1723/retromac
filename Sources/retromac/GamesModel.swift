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
    let installable: Set<SystemID> = Set((try? Manifest.bundled())?.installableSystems ?? [])
    private var analysis: Task<Void, Never>?
    var candidates: [ImportCandidate] = []
    /// What's running; each is shown and cancelled separately, and only one copy can run at a time.
    var analyzing = false
    var committing = false
    var updatingDats = false
    var busy: Bool { analyzing || committing || updatingDats }
    var message: String?

    private let paths: Paths
    private let libraryRoot: () -> URL
    /// Everything dropped since the last Add/Clear; re-analyzed together so duplicates across drops are caught.
    private var dropped: [URL] = []
    private var session: ImportSession?
    /// Bumped per analysis; a result from an older analysis is discarded, so overlapping drops can't
    /// replace a newer list with a stale one.
    private var generation = 0

    init(paths: Paths, libraryRoot: @escaping () -> URL) {
        self.paths = paths
        self.libraryRoot = libraryRoot
        dats = DatStore(paths: paths).load()
    }

    var toAdd: Int { candidates.filter(Self.addable).count }

    /// Candidates that commit copies into the library.
    static func addable(_ item: ImportCandidate) -> Bool {
        guard item.destination != nil else { return false }
        switch item.status {
        case .identified, .unverified, .unidentified: return true
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
        let importer = Importer(libraryRoot: libraryRoot(), dats: DatStore(paths: paths), runner: ProcessRunner())
        let urls = dropped
        // Reusing the session keeps already-unpacked archives instead of unpacking them again.
        let previous = session
        let worker = Task.detached { Result { try importer.analyze(urls, reusing: previous) } }
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
        let importer = Importer(libraryRoot: libraryRoot(), dats: DatStore(paths: paths), runner: ProcessRunner())
        let pending = candidates
        do {
            let added = try await Task.detached { try importer.commit(session, pending) }.value
            let count = added.filter(Self.addable).count
            candidates = added
            // Only what this commit covered; anything dropped meanwhile stays queued.
            dropped.removeFirst(min(committed.count, dropped.count))
            self.session = nil
            message = "Added \(count) game\(count == 1 ? "" : "s"). They appear in ES-DE the next time it starts."
        } catch {
            message = "Couldn't add games: \(error.localizedDescription)"
        }
    }

    func clear() {
        dropped = []
        candidates = []
        session = nil
        message = nil
    }
}
