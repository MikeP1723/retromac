// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Observation
import RetromacCore

@Observable @MainActor
final class GamesModel {
    var dats: [SystemID: DatFile] = [:]
    var datError: String?
    var candidates: [ImportCandidate] = []
    var busy = false
    var message: String?

    private let paths: Paths
    private let libraryRoot: () -> URL
    /// Everything dropped since the last Add/Clear; re-analyzed together so duplicates across drops are caught.
    private var dropped: [URL] = []
    private var session: ImportSession?

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
        do {
            _ = try DatStore(paths: paths).importDats(urls, runner: ProcessRunner())
            dats = DatStore(paths: paths).load()
            datError = nil
        } catch DatError.unknownSystem(let name) {
            datError = "\(name) isn't a system retromac supports yet."
        } catch DatError.unsupportedVariant(let hint) {
            datError = "Wrong DAT variant: \(hint)."
        } catch DatError.notADat {
            datError = "That file isn't a No-Intro DAT."
        } catch {
            datError = "Couldn't import: \(error.localizedDescription)"
        }
    }

    func analyze(_ urls: [URL]) async {
        dropped += urls
        await reanalyze()
    }

    private func reanalyze() async {
        busy = true
        defer { busy = false }
        message = nil
        let importer = Importer(libraryRoot: libraryRoot(), dats: DatStore(paths: paths), runner: ProcessRunner())
        let urls = dropped
        do {
            let (session, candidates) = try await Task.detached { try importer.analyze(urls) }.value
            self.session = session
            self.candidates = candidates
        } catch {
            message = "Couldn't read the dropped files: \(error.localizedDescription)"
        }
    }

    func commit() async {
        guard let session else { return }
        busy = true
        defer { busy = false }
        let importer = Importer(libraryRoot: libraryRoot(), dats: DatStore(paths: paths), runner: ProcessRunner())
        let pending = candidates
        do {
            let added = try await Task.detached { try importer.commit(session, pending) }.value
            let count = added.filter(Self.addable).count
            candidates = added
            dropped = []
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
