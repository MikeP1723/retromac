// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Observation
import RetromacCore

@Observable @MainActor
final class UpdateModel {
    var plan: UpdatePlan?
    var selected: Set<String> = []
    var adopt: Set<String> = []
    var log: [String] = []
    var error: String?
    var busy = false
    var showSheet = false
    /// Components with a previous generation that Revert can swap back.
    var revertible: [String] = []

    let paths: Paths
    private let profile: () -> Profile
    private var latest: Manifest?
    private var coreIndex: CoreIndex?

    static let lastCheckKey = "lastUpdateCheck"

    init(paths: Paths, profile: @escaping () -> Profile) {
        self.paths = paths
        self.profile = profile
        refreshRevertible()
    }

    var appVersion: String {
        AppVersion.current(infoDictionary: Bundle.main.infoDictionary)
    }

    var hasUpdates: Bool {
        guard let plan else { return false }
        return !plan.updates.isEmpty || plan.retromacUpdate != nil
    }

    /// `RETROMAC_RELEASE_FIXTURES` rehearses an update against a local fake release (debug builds only).
    private var downloader: any Downloader {
        #if DEBUG
        if let dir = ProcessInfo.processInfo.environment["RETROMAC_RELEASE_FIXTURES"] {
            return DirectoryDownloader(root: URL(filePath: dir))
        }
        #endif
        return URLSessionDownloader(headers: ["Accept": "application/vnd.github+json"])
    }

    func check(force: Bool) async {
        let defaults = UserDefaults.standard
        if !force, let last = defaults.object(forKey: Self.lastCheckKey) as? Date, Date().timeIntervalSince(last) < 24 * 60 * 60 {
            return
        }
        error = nil
        do {
            let client = ReleaseClient(downloader: downloader)
            let release = try await client.latest()
            do {
                coreIndex = try await client.coreIndex()
            } catch {
                coreIndex = nil
                log.append("Couldn't check for core rebuilds: \(error.localizedDescription)")
            }
            latest = release.manifest
            replan()
            selected = Set(plan?.updates.filter(\.managed).map(\.id) ?? [])
            adopt = []
            defaults.set(Date(), forKey: Self.lastCheckKey)
        } catch UpdateError.policy(let violations) {
            error = (["The latest release failed safety checks and was ignored:"] + violations).joined(separator: "\n")
        } catch {
            self.error = "Couldn't check for updates: \(error.localizedDescription)"
        }
    }

    private func replan() {
        guard let latest else { return }
        guard let state = try? InstallState.load(from: paths.state) else { return }
        plan = UpdatePlanner.plan(state: state, applied: appliedManifest() ?? latest, latest: latest,
                                  coreIndex: coreIndex, appVersion: appVersion)
    }

    private func appliedManifest() -> Manifest? {
        if let data = try? Data(contentsOf: paths.appliedManifest), let m = try? JSONDecoder().decode(Manifest.self, from: data) {
            return m
        }
        return try? Manifest.bundled()
    }

    private func updater(for manifest: Manifest) -> Updater {
        let apps = manifest.apps.map(\.appName)
        return Updater(paths: paths,
                       installer: Installer(manifest: manifest, paths: paths, downloader: downloader, runner: ProcessRunner()),
                       applier: Applier(paths: paths, apps: apps, isRunning: RunningApps.isRunning),
                       apps: apps, isRunning: RunningApps.isRunning)
    }

    func applySelected() async {
        guard let plan, let latest, let rules = try? DisplayRules.bundled() else { return }
        busy = true
        defer { busy = false }
        let chosen = plan.updates.filter { selected.contains($0.id) }
        log.append("Updating \(chosen.map(\.id).joined(separator: ", "))…")
        do {
            let report = try await updater(for: latest).apply(chosen, adopt: adopt, latest: latest, profile: profile(), rules: rules)
            report.updated.forEach { log.append("Updated \($0)") }
            report.skipped.forEach { log.append("Skipped \($0)") }
            report.failed.forEach { log.append("Failed \($0)") }
            log.append(report.failed.isEmpty ? "Done." : "Finished with errors; failed components are unchanged.")
        } catch UpdateError.appRunning(let app), ApplyError.appRunning(let app) {
            log.append("Quit \(app.replacingOccurrences(of: ".app", with: "")) and try again.")
        } catch {
            log.append("Update failed: \(error)")
        }
        replan()
        selected = Set(self.plan?.updates.filter(\.managed).map(\.id) ?? [])
        refreshRevertible()
    }

    func updateSelf() async {
        guard let entry = plan?.retromacUpdate else { return }
        let target = Bundle.main.bundleURL
        guard target.pathExtension == "app" else {
            log.append("Self-update only works from retromac.app.")
            return
        }
        if let reason = SelfUpdater.cannotReplace(bundle: target) {
            log.append(reason)
            return
        }
        busy = true
        defer { busy = false }
        do {
            let dir = FileManager.default.temporaryDirectory.appending(path: "retromac-self-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let staged = try await SelfUpdater.stage(entry, in: dir, downloader: downloader, runner: ProcessRunner())
            try FileManager.default.createDirectory(at: paths.previous, withIntermediateDirectories: true)
            let script = SelfUpdater.swapScript(pid: ProcessInfo.processInfo.processIdentifier, staged: staged, target: target,
                                                previous: paths.previous.appending(path: "retromac.app"))
            let process = Process()
            process.executableURL = URL(filePath: "/bin/sh")
            process.arguments = ["-c", script]
            try process.run()
            NSApplication.shared.terminate(nil)
        } catch {
            log.append("Self-update failed: \(error)")
        }
    }

    func revert(_ id: String) {
        guard let manifest = latest ?? appliedManifest() else { return }
        do {
            try updater(for: manifest).rollback(id)
            log.append("Reverted \(id).")
        } catch UpdateError.appRunning(let app) {
            log.append("Quit \(app.replacingOccurrences(of: ".app", with: "")) and try again.")
        } catch {
            log.append("Revert failed: \(error)")
        }
        replan()
        refreshRevertible()
    }

    private func refreshRevertible() {
        let state = try? InstallState.load(from: paths.state)
        revertible = Array((state?.previousApps ?? [:]).keys) + Array((state?.previousCores ?? [:]).keys)
        revertible.sort()
    }
}
