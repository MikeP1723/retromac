// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import GameController
import Observation
import RetromacCore

@Observable @MainActor
final class WizardModel {
    enum Step: Int, CaseIterable {
        case display, systems, controllers, library, apply, games

        var title: String {
            switch self {
            case .display: "Display"
            case .systems: "Systems"
            case .controllers: "Controllers"
            case .library: "Library"
            case .apply: "Install"
            case .games: "Games"
            }
        }
    }

    var step: Step = .display
    var profile: Profile
    var log: [String] = []
    var busy = false
    /// Set after a successful Install & Apply; the last step then offers to open ES-DE.
    var applied = false
    var backups: [URL] = []
    var loadError: String?

    let paths = Paths(home: FileManager.default.homeDirectoryForCurrentUser)
    private let manifest: Manifest?
    private let rules: DisplayRules?
    private var observers: [NSObjectProtocol] = []

    init() {
        let paths = Paths(home: FileManager.default.homeDirectoryForCurrentUser)
        var errors: [String] = []
        manifest = Self.load("manifest", into: &errors) { try Manifest.bundled() }
        rules = Self.load("display rules", into: &errors) { try DisplayRules.bundled() }
        loadError = errors.isEmpty ? nil : errors.joined(separator: "\n")

        if var saved = try? Profile.load(from: paths.profile) {
            // Re-detect the screen, keeping the size and distance only the user knows.
            saved.display = DisplayDetector.detect(diagonalInches: saved.display.diagonalInches,
                                                   distanceInches: saved.display.distanceInches)
            profile = saved
        } else {
            profile = Profile(display: DisplayDetector.detect(), look: .crisp, systems: Set((try? Manifest.bundled())?.installableSystems ?? []),
                              controllers: [], facePolicy: .position, libraryRoot: paths.defaultLibraryRoot)
        }
        profile.controllers = ControllerDetector.detect()
        backups = (try? BackupStore(root: paths.backups, home: paths.home).list()) ?? []

        for name in [NSNotification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.profile.controllers = ControllerDetector.detect() }
            })
        }
    }

    private static func load<T>(_ what: String, into errors: inout [String], _ body: () throws -> T) -> T? {
        do { return try body() } catch {
            errors.append("Couldn't load \(what): \(error.localizedDescription)")
            return nil
        }
    }

    var shaderDescription: String {
        guard let rules else { return "unavailable" }
        return rules.shaderPreset(for: profile.display, look: profile.look)?.path ?? "none"
    }

    var pixelsPerDegree: Double { Optics.pixelsPerDegree(profile.display) }

    func installAndApply() async {
        guard let manifest, let rules else { return }
        busy = true
        defer { busy = false }
        log = []
        applied = false
        do {
            try profile.save(to: paths.profile)
            log.append("Installing emulators and cores…")
            let installer = Installer(manifest: manifest, paths: paths, downloader: URLSessionDownloader(), runner: ProcessRunner())
            let installed = try await installer.install(systems: profile.systems)
            installed.installed.forEach { log.append("Installed \($0)") }
            installed.skipped.forEach { log.append("Already installed: \($0)") }
            installed.warnings.forEach { log.append("Note: \($0)") }

            let files = ProfileRenderer.render(profile, manifest: manifest, rules: rules, paths: paths)
            let report = try Applier(paths: paths, apps: manifest.apps.map(\.appName), isRunning: RunningApps.isRunning).apply(files)
            log.append("Wrote \(report.written.count) files, \(report.unchanged.count) unchanged.")
            if let backup = report.backup { log.append("Previous config backed up to \(backup.path)") }
            backups = try BackupStore(root: paths.backups, home: paths.home).list()
            log.append("Done.")
            applied = true
        } catch ApplyError.appRunning(let app) {
            log.append("Quit \(app.replacingOccurrences(of: ".app", with: "")) and try again.")
        } catch {
            log.append("Error: \(error)")
        }
    }

    func openESDE() {
        NSWorkspace.shared.open(paths.applications.appending(path: "ES-DE.app"))
    }

    func restore(_ snapshot: URL) {
        if let running = manifest?.apps.map(\.appName).first(where: RunningApps.isRunning) {
            log.append("Quit \(running.replacingOccurrences(of: ".app", with: "")) and try again.")
            return
        }
        do {
            try BackupStore(root: paths.backups, home: paths.home).restore(snapshot)
            log.append("Restored config from \(snapshot.lastPathComponent).")
        } catch {
            log.append("Restore failed: \(error)")
        }
    }
}
