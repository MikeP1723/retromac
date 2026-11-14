// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Observation
import RetromacCore

/// Which screen the window shows: a one-time migration, setup, the home screen, or the library.
@Observable @MainActor
final class AppModel {
    enum Screen { case migrating, wizard, home, library }

    var screen: Screen
    var migrationError: String?
    var migrating = false
    /// "1,190 games · 38.2 GB", computed in the background.
    var libraryStats: String?

    let paths = Paths(home: FileManager.default.homeDirectoryForCurrentUser)
    let wizard: WizardModel
    let updates: UpdateModel
    let games: GamesModel

    init() {
        let wizard = WizardModel()
        let paths = wizard.paths
        self.wizard = wizard
        updates = UpdateModel(paths: paths, profile: { wizard.profile })
        games = GamesModel(paths: paths, libraryRoot: { wizard.profile.libraryRoot })
        screen = .wizard
        if Self.migrator(paths).isNeeded { screen = .migrating } else { route() }
    }

    static let pendingApplyKey = "retromac.pendingApply"

    /// Home when setup is complete. A profile without retromac's own ES-DE (e.g. macOS wouldn't let the
    /// old copy be moved) goes straight to the Install step to get a fresh one.
    func route() {
        if isSetUp {
            screen = .home
        } else {
            screen = .wizard
            if FileManager.default.fileExists(atPath: paths.profile.path) {
                wizard.step = .apply
                wizard.notice = "retromac needs to install its own copy of RetroArch and ES-DE. Click Install & Apply to finish."
            }
        }
    }

    /// Re-applies configs a migration couldn't (e.g. ES-DE was opened mid-way); safe to call every launch.
    func retryPendingApply() {
        guard UserDefaults.standard.bool(forKey: Self.pendingApplyKey), screen != .migrating else { return }
        if (try? wizard.applyConfigs()) != nil {
            UserDefaults.standard.removeObject(forKey: Self.pendingApplyKey)
        }
    }

    static func migrator(_ paths: Paths) -> Migrator {
        Migrator(paths: paths, legacy: LegacyPaths(home: paths.home), isRunning: RunningApps.isRunning)
    }

    /// Setup has run once: there's a profile and retromac's own ES-DE is in place.
    static func isSetUp(_ paths: Paths) -> Bool {
        FileManager.default.fileExists(atPath: paths.profile.path)
            && FileManager.default.fileExists(atPath: paths.applications.appending(path: "ES-DE.app").path)
    }

    var isSetUp: Bool { Self.isSetUp(paths) }

    var canPlay: Bool {
        FileManager.default.fileExists(atPath: paths.applications.appending(path: "ES-DE.app").path)
    }

    func migrate() async {
        migrating = true
        migrationError = nil
        defer { migrating = false }
        let migrator = Self.migrator(paths)
        do {
            _ = try await Task.detached { try migrator.run() }.value
            wizard.reloadProfile()
            games.dats = DatStore(paths: paths).load()
            do {
                try wizard.applyConfigs()
            } catch {
                // Not fatal: the migration already pointed ES-DE at the new library. Retried next launch.
                UserDefaults.standard.set(true, forKey: Self.pendingApplyKey)
            }
            route()
            await refreshLibraryStats()
        } catch MigrationError.appRunning(let app) {
            migrationError = "Quit \(app.replacingOccurrences(of: ".app", with: "")) to finish updating retromac."
        } catch MigrationError.moveFailed(let reason) {
            migrationError = "Couldn't move \(reason)"
        } catch {
            migrationError = error.localizedDescription
        }
    }

    func play() {
        wizard.openESDE()
    }

    func showGamesInFinder() {
        let library = wizard.profile.libraryRoot
        try? FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([library])
    }

    func refreshLibraryStats() async {
        let library = wizard.profile.libraryRoot
        let stats = await Task.detached { LibraryStats.scan(library) }.value
        games.librarySystems = stats.bySystem
        libraryStats = stats.count == 0 ? "No games yet"
            : "\(stats.count.formatted()) game\(stats.count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file))"
    }
}

/// Games per system in the library: disc tracks referenced by a .cue count once, sidecars not at all.
struct LibraryStats: Sendable {
    var count = 0
    var bytes: Int64 = 0
    var bySystem: [SystemID: Int] = [:]

    static func scan(_ library: URL) -> LibraryStats {
        var stats = LibraryStats()
        let fm = FileManager.default
        for system in SystemID.allCases {
            let folder = library.appending(path: system.rawValue)
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                                                          options: [.skipsHiddenFiles]) else { continue }
            let hasCue = files.contains { $0.pathExtension.lowercased() == "cue" }
            var games = 0
            for file in files {
                stats.bytes += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
                let ext = file.pathExtension.lowercased()
                if ext == "txt" || (hasCue && ext == "bin") { continue }
                games += 1
            }
            if games > 0 { stats.bySystem[system] = games }
            stats.count += games
        }
        return stats
    }
}
