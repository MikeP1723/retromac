// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public protocol FileOps: Sendable {
    func move(_ from: URL, to: URL) throws
    func removeIfExists(_ url: URL) throws
}

public struct RealFileOps: FileOps {
    public init() {}

    public func move(_ from: URL, to: URL) throws {
        try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: from, to: to)
    }

    public func removeIfExists(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

public struct UpdateReport: Equatable, Sendable {
    public var updated: [String] = []
    public var skipped: [String] = []
    /// "<id>: <reason>" for components whose swap failed; they stay on their current version.
    public var failed: [String] = []
    public var config: ApplyReport?
}

/// Applies component updates: stage everything first, then swap each into place with the
/// current copy kept in `paths.previous` as a one-generation rollback.
public struct Updater: Sendable {
    let paths: Paths
    let installer: Installer
    let applier: Applier
    /// App bundle names checked for running before anything is touched.
    let apps: [String]
    let isRunning: @Sendable (String) -> Bool
    let fileOps: any FileOps

    public init(paths: Paths, installer: Installer, applier: Applier, apps: [String],
                isRunning: @escaping @Sendable (String) -> Bool, fileOps: any FileOps = RealFileOps()) {
        self.paths = paths
        self.installer = installer
        self.applier = applier
        self.apps = apps
        self.isRunning = isRunning
        self.fileOps = fileOps
    }

    struct Staged {
        let id: String
        let staged: URL
        let target: URL
        let name: String
        let app: InstallState.App?
        let core: InstallState.Core?
    }

    public func apply(_ updates: [ComponentUpdate], adopt: Set<String>, latest: Manifest,
                      profile: Profile, rules: DisplayRules) async throws -> UpdateReport {
        if let running = apps.first(where: isRunning) { throw UpdateError.appRunning(running) }
        var state = try InstallState.load(from: paths.state)
        var report = UpdateReport()

        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appending(path: "retromac-update-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        var staged: [Staged] = []
        defer {
            try? fm.removeItem(at: tmp)
            for s in staged where s.app != nil { try? fm.removeItem(at: s.staged.deletingLastPathComponent()) }
        }

        // Stage everything before swapping anything: a bad download leaves the install untouched.
        for update in updates {
            if !update.managed && !adopt.contains(update.id) {
                report.skipped.append("\(update.id): not managed by retromac")
                continue
            }
            switch update.kind {
            case .app:
                guard let entry = latest.apps.first(where: { $0.id == update.id }) else { continue }
                let url = try await installer.stageApp(entry)
                staged.append(Staged(id: entry.id, staged: url, target: paths.applications.appending(path: entry.appName),
                                     name: entry.appName, app: .init(version: entry.version, sha256: entry.sha256, managed: true), core: nil))
            case .core:
                guard let entry = latest.cores.first(where: { $0.id == update.id }) else { continue }
                let result = try await installer.stageCore(entry, in: tmp)
                staged.append(Staged(id: entry.id, staged: result.dylib, target: paths.retroarchCores.appending(path: entry.file),
                                     name: entry.file, app: nil,
                                     core: .init(version: entry.version, sha256: result.sha256, file: entry.file, crc32: result.crc32)))
            }
        }

        // The download can take minutes; an emulator launched meanwhile must not have files swapped under it.
        if let running = apps.first(where: isRunning) { throw UpdateError.appRunning(running) }

        for s in staged {
            let previous = paths.previous.appending(path: s.name)
            // Park the current copy until the new one is in place, so a failed swap never costs
            // the existing rollback generation.
            let parked = paths.previous.appending(path: "\(s.name).parked-\(UUID().uuidString)")
            let hadCurrent = fm.fileExists(atPath: s.target.path)
            do {
                if hadCurrent { try fileOps.move(s.target, to: parked) }
                do {
                    try fileOps.move(s.staged, to: s.target)
                } catch {
                    if hadCurrent {
                        do { try fileOps.move(parked, to: s.target) } catch {
                            throw CocoaError(.fileWriteUnknown, userInfo: [
                                NSLocalizedDescriptionKey: "couldn't restore \(s.name); the old copy is at \(parked.path)"])
                        }
                    }
                    throw error
                }
            } catch {
                report.failed.append("\(s.id): \(error.localizedDescription)")
                continue
            }

            var keptPrevious = false
            if hadCurrent {
                try? fileOps.removeIfExists(previous)
                keptPrevious = (try? fileOps.move(parked, to: previous)) != nil
            }
            if let app = s.app {
                var previousApps = state.previousApps ?? [:]
                previousApps[s.id] = keptPrevious ? state.apps[s.id] : nil
                state.previousApps = previousApps
                state.apps[s.id] = app
            }
            if let core = s.core {
                var previousCores = state.previousCores ?? [:]
                previousCores[s.id] = keptPrevious ? state.cores[s.id] : nil
                state.previousCores = previousCores
                state.cores[s.id] = core
            }
            try state.save(to: paths.state)
            report.updated.append(s.id)
        }

        guard !report.updated.isEmpty else { return report }
        report.config = try applier.apply(ProfileRenderer.render(profile, manifest: latest, rules: rules, paths: paths))
        // Only a fully applied update moves the baseline the planner compares licenses against.
        if report.failed.isEmpty {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try fm.createDirectory(at: paths.appliedManifest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(latest).write(to: paths.appliedManifest, options: .atomic)
        }
        return report
    }

    /// Swaps a component back with its copy in `paths.previous`.
    public func rollback(_ id: String) throws {
        if let running = apps.first(where: isRunning) { throw UpdateError.appRunning(running) }
        var state = try InstallState.load(from: paths.state)
        let name: String, target: URL
        if state.previousApps?[id] != nil, let appName = appName(for: id) {
            name = appName
            target = paths.applications.appending(path: name)
        } else if let core = state.previousCores?[id] {
            name = core.file
            target = paths.retroarchCores.appending(path: name)
        } else {
            throw UpdateError.nothingToRollBack(id)
        }
        let fm = FileManager.default
        let previous = paths.previous.appending(path: name)
        guard fm.fileExists(atPath: previous.path) else { throw UpdateError.nothingToRollBack(id) }

        let parked = paths.previous.appending(path: "\(name).rollback-\(UUID().uuidString)")
        let hadCurrent = fm.fileExists(atPath: target.path)
        if hadCurrent { try fileOps.move(target, to: parked) }
        do {
            try fileOps.move(previous, to: target)
        } catch {
            if hadCurrent { try? fileOps.move(parked, to: target) }
            throw error
        }
        let keptCurrent = hadCurrent && (try? fileOps.move(parked, to: previous)) != nil

        if let old = state.previousApps?[id] {
            state.previousApps?[id] = keptCurrent ? state.apps[id] : nil
            state.apps[id] = old
        } else if let old = state.previousCores?[id] {
            state.previousCores?[id] = keptCurrent ? state.cores[id] : nil
            state.cores[id] = old
        }
        try state.save(to: paths.state)
    }

    func appName(for id: String) -> String? {
        let applied = (try? Data(contentsOf: paths.appliedManifest)).flatMap { try? JSONDecoder().decode(Manifest.self, from: $0) }
        return (applied ?? (try? Manifest.bundled()))?.apps.first { $0.id == id }?.appName
    }
}
