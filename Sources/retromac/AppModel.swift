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

    enum NetworkStatus: Equatable { case local, connected, notConnected(String) }
    /// Whether the network library (if any) is reachable; the home screen shows a banner when it isn't.
    var networkStatus: NetworkStatus = .local
    /// Shown when Play can't connect the network library.
    var playAlert: String?
    static let notConnected = "Your network library isn't connected."

    let paths = Paths(home: FileManager.default.homeDirectoryForCurrentUser)
    let wizard: WizardModel
    let updates: UpdateModel
    let games: GamesModel

    init() {
        let wizard = WizardModel()
        let paths = wizard.paths
        self.wizard = wizard
        updates = UpdateModel(paths: paths, profile: { wizard.profile })
        games = GamesModel(paths: paths, libraryRoot: { wizard.profile.libraryRoot }, readOnly: { wizard.profile.isLibraryReadOnly }, biosAdded: { try? wizard.applyConfigs() })
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

    /// Mounts the network library, if there is one, and points everything at its mount point (which can
    /// change between mounts, e.g. /Volumes/roms-1). False when it can't be reached; the path is left as is.
    @discardableResult
    func connectNetworkLibrary() async -> Bool {
        guard let library = wizard.profile.networkLibrary else {
            networkStatus = .local
            return true
        }
        do {
            let folder = try await Task.detached { try NetworkShare().libraryFolder(for: library) }.value
            if folder.standardizedFileURL != wizard.profile.libraryRoot.standardizedFileURL {
                wizard.profile.libraryRoot = folder
                try? wizard.profile.save(to: paths.profile)
                try? wizard.applyConfigs()
            }
            networkStatus = .connected
            return true
        } catch {
            networkStatus = .notConnected(Self.describe(error))
            return false
        }
    }

    static func describe(_ error: Error) -> String {
        switch error as? NetworkShareError {
        case .cancelled: "The server login was cancelled."
        case .unreachable(let reason): "The server couldn't be reached (\(reason))."
        case .folderMissing(let folder): "The folder \(folder) isn't on the share."
        case nil: error.localizedDescription
        }
    }

    /// The share as `address` names it, mounted, with the console folders found in it; or why not.
    enum NetworkCheck {
        case found(url: URL, folder: URL, consoles: [SystemID], other: [String])
        case failed(String)
    }

    func checkNetworkLibrary(_ address: String) async -> NetworkCheck {
        guard let url = NetworkLibrary.parse(address) else {
            return .failed("Enter an smb:// address, for example smb://nas/media/roms.")
        }
        let library = NetworkLibrary(url: url, localLibrary: wizard.profile.libraryRoot)
        do {
            let folder = try await Task.detached { try NetworkShare().libraryFolder(for: library) }.value
            let (found, other) = await Task.detached { NetworkLibrary.consoleFolders(in: folder) }.value
            return .found(url: url, folder: folder, consoles: found, other: other)
        } catch {
            return .failed(Self.describe(error))
        }
    }

    /// Switches the library (to a share, or back to local) and re-applies. A refused apply (ES-DE or an
    /// emulator is open) rolls the profile back and says which app to quit.
    func switchLibrary(_ change: (inout Profile) -> Void) -> String? {
        let before = wizard.profile
        change(&wizard.profile)
        do {
            try wizard.profile.save(to: paths.profile)
            try wizard.applyConfigs()
        } catch {
            wizard.profile = before
            try? before.save(to: paths.profile)
            if case ApplyError.appRunning(let app) = error {
                return "Quit \(app.replacingOccurrences(of: ".app", with: "")) and try again."
            }
            return error.localizedDescription
        }
        networkStatus = wizard.profile.isLibraryReadOnly ? .connected : .local
        games.refreshConvertible()
        Task { await refreshLibraryStats() }
        return nil
    }

    func play() async {
        // A network library must be mounted first: ES-DE never opens on an empty library, and the console
        // agent is only told once it is.
        guard await connectNetworkLibrary() else {
            playAlert = Self.notConnected
            return
        }
        // The console agent starts its session (standby assertion, combos) and brings ES-DE forward;
        // opening ES-DE here too means Play works even if the agent isn't running.
        if wizard.profile.console?.enabled == true {
            DistributedNotificationCenter.default().postNotificationName(.init("petersoft.retromac.console.play"), object: nil, deliverImmediately: true)
        }
        wizard.openESDE()
    }

    func showGamesInFinder() {
        let library = wizard.profile.libraryRoot
        if !wizard.profile.isLibraryReadOnly {
            try? FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        }
        NSWorkspace.shared.activateFileViewerSelecting([library])
    }

    func refreshLibraryStats() async {
        let library = wizard.profile.libraryRoot
        // Summing sizes across a server's terabytes over SMB is skipped; counts only.
        let sizes = !wizard.profile.isLibraryReadOnly
        let stats = await Task.detached { LibraryStats.scan(library, sizes: sizes) }.value
        games.librarySystems = stats.bySystem
        let count = "\(stats.count.formatted()) game\(stats.count == 1 ? "" : "s")"
        libraryStats = stats.count == 0 ? "No games yet"
            : sizes ? "\(count) · \(ByteCountFormatter.string(fromByteCount: stats.bytes, countStyle: .file))" : "\(count) on your network library"
    }
}

/// Games per system in the library: disc tracks referenced by a .cue count once, sidecars not at all.
struct LibraryStats: Sendable {
    var count = 0
    var bytes: Int64 = 0
    var bySystem: [SystemID: Int] = [:]

    static func scan(_ library: URL, sizes: Bool = true) -> LibraryStats {
        var stats = LibraryStats()
        let fm = FileManager.default
        let keys: [URLResourceKey] = sizes ? [.totalFileAllocatedSizeKey] : []
        func size(_ url: URL) -> Int64 {
            sizes ? Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0) : 0
        }
        for system in SystemID.allCases {
            let folder = library.appending(path: system.rawValue)
            guard let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                          options: [.skipsHiddenFiles]) else { continue }
            let hasCue = files.contains { $0.pathExtension.lowercased() == "cue" }
            var games = 0
            for file in files {
                let ext = file.pathExtension.lowercased()
                if ext == "m3u", let set = try? fm.contentsOfDirectory(at: file, includingPropertiesForKeys: keys,
                                                                         options: [.skipsHiddenFiles]) {
                    // A multi-disc game's folder (see DiscSets) is one game.
                    stats.bytes += set.reduce(0) { $0 + size($1) }
                    games += 1
                    continue
                }
                stats.bytes += size(file)
                if ext == "txt" || (hasCue && ext == "bin") { continue }
                // A bare image that got its own cue (see DiscSets) is counted through the cue.
                if ["img", "iso"].contains(ext), fm.fileExists(atPath: file.deletingPathExtension().appendingPathExtension("cue").path) { continue }
                games += 1
            }
            if games > 0 { stats.bySystem[system] = games }
            stats.count += games
        }
        return stats
    }
}
