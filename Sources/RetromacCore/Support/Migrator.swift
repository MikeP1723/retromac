// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct MigrationReport: Equatable, Sendable {
    public var moved: [String] = []
    public var leftAlone: [String] = []

    public init(moved: [String] = [], leftAlone: [String] = []) {
        self.moved = moved
        self.leftAlone = leftAlone
    }
}

public enum MigrationError: Error, Equatable {
    case appRunning(String)
    case moveFailed(String)
}

/// Moves a Phase 1–3 install (~/retromac, ~/ES-DE, managed apps in /Applications) under Application
/// Support. Only renames, only what retromac created, and safe to run again after an interruption.
public struct Migrator: Sendable {
    static let layoutVersion = 2

    let paths: Paths
    let legacy: LegacyPaths
    let isRunning: @Sendable (String) -> Bool
    var fm: FileManager { .default }

    public init(paths: Paths, legacy: LegacyPaths, isRunning: @escaping @Sendable (String) -> Bool) {
        self.paths = paths
        self.legacy = legacy
        self.isRunning = isRunning
    }

    public var isNeeded: Bool {
        if fm.fileExists(atPath: legacy.root.path) { return true }
        let state = currentState()
        guard state.layoutVersion != Self.layoutVersion else { return false }
        return managedApps(state).contains { fm.fileExists(atPath: legacy.applications.appending(path: $0).path) }
    }

    /// What `run()` would do, without moving anything.
    public func plan() -> MigrationReport {
        var report = MigrationReport()
        try? walk(dryRun: true, &report)
        return report
    }

    public func run() throws -> MigrationReport {
        if let running = ["RetroArch.app", "ES-DE.app"].first(where: isRunning) { throw MigrationError.appRunning(running) }
        var report = MigrationReport()
        try walk(dryRun: false, &report)
        return report
    }

    private func walk(dryRun: Bool, _ report: inout MigrationReport) throws {
        guard isNeeded else { return }
        if !dryRun { try create(paths.root) }

        // 1. retromac's own files. Conflicts keep the newer layout's copy; the older one is parked.
        let leftovers = paths.root.appending(path: "Leftovers from ~:retromac")
        if fm.fileExists(atPath: legacy.root.path) {
            // Child by child, so a dry run reports the same moves whether or not the root exists yet.
            for child in try fm.contentsOfDirectory(at: legacy.root, includingPropertiesForKeys: nil) {
                let name = child.lastPathComponent
                try merge(child, into: paths.root.appending(path: name), label: "~/retromac/\(name)",
                          leftovers: leftovers.appending(path: name), dryRun: dryRun, &report)
            }
            if !dryRun, (try? fm.contentsOfDirectory(atPath: legacy.root.path))?.isEmpty == true {
                try? fm.removeItem(at: legacy.root)
            }
        }
        let state = dryRun ? currentState() : (try? InstallState.load(from: paths.state)) ?? .empty
        let names = appNames()

        // 2. ES-DE's data, only when retromac installed ES-DE. Data moves before apps, so a blocked
        //    app move never strands it.
        if fm.fileExists(atPath: legacy.esde.path) {
            if state.apps["esde"]?.managed == true {
                try merge(legacy.esde, into: paths.esdeRoot, label: "~/ES-DE",
                          leftovers: paths.root.appending(path: "Leftovers from ~:ES-DE"), dryRun: dryRun, &report)
            } else {
                report.leftAlone.append("~/ES-DE (yours)")
            }
        }

        // 3. Apps retromac installed. The user's own copies stay where they are. macOS can refuse to
        //    move another developer's app out of /Applications (App Management); that copy is left and
        //    retromac installs a fresh one into its own folder instead.
        for (id, app) in state.apps.sorted(by: { $0.key < $1.key }) {
            guard let name = names[id] else { continue }
            let source = legacy.applications.appending(path: name)
            guard fm.fileExists(atPath: source.path) else { continue }
            guard app.managed else {
                report.leftAlone.append("\(name) (yours)")
                continue
            }
            let target = paths.applications.appending(path: name)
            if fm.fileExists(atPath: target.path) {
                report.leftAlone.append(name)
                continue
            }
            if dryRun {
                report.moved.append(name)
            } else if (try? move(source, to: target, label: name)) != nil {
                report.moved.append(name)
            } else {
                report.leftAlone.append("\(name) (couldn't move — retromac will install a fresh copy)")
            }
        }
        guard !dryRun else { return }

        // 4. Backups taken before the move restore into the new ES-DE folder, never ~/ES-DE.
        let newESDE = "Library/Application Support/retromac/ES-DE"
        for snapshot in (try? fm.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)) ?? [] {
            let old = snapshot.appending(path: "ES-DE")
            if fm.fileExists(atPath: old.path) {
                var internalMoves = MigrationReport()
                try merge(old, into: snapshot.appending(path: newESDE), label: "backup \(snapshot.lastPathComponent)",
                          leftovers: snapshot.appending(path: "Leftovers"), dryRun: false, &internalMoves)
            }
            let created = snapshot.appending(path: BackupStore.createdList)
            if let text = try? String(contentsOf: created, encoding: .utf8) {
                let rewritten = text.components(separatedBy: "\n")
                    .map { $0.hasPrefix("ES-DE/") ? newESDE + "/" + $0.dropFirst("ES-DE/".count) : $0 }
                    .joined(separator: "\n")
                try rewritten.write(to: created, atomically: true, encoding: .utf8)
            }
        }

        // 5. The library lives under the root. A folder the user picked earlier moves in when it's on the
        //    same disk; one on another disk (an external drive) keeps being used where it is.
        var oldLibraries = [legacy.root.appending(path: "Library").standardizedFileURL.path]
        if var profile = try? Profile.load(from: paths.profile) {
            let chosen = profile.libraryRoot.standardizedFileURL
            if chosen.path != paths.defaultLibraryRoot.standardizedFileURL.path {
                if fm.fileExists(atPath: chosen.path), chosen.path != oldLibraries[0] {
                    if sameVolume(chosen, paths.root) {
                        try merge(chosen, into: paths.defaultLibraryRoot, label: "your game folder",
                                  leftovers: paths.root.appending(path: "Leftovers from \(chosen.lastPathComponent)"), dryRun: false, &report)
                        oldLibraries.append(chosen.path)
                        profile.libraryRoot = paths.defaultLibraryRoot
                    }
                } else {
                    profile.libraryRoot = paths.defaultLibraryRoot
                }
                try profile.save(to: paths.profile)
            }
        }
        let library = ((try? Profile.load(from: paths.profile))?.libraryRoot ?? paths.defaultLibraryRoot).path

        // 6. ES-DE points at the moved library and finds RetroArch in its new place before any config
        //    apply (and its backup snapshot) happens, including inside older snapshots.
        if fm.fileExists(atPath: paths.esdeRoot.path) {
            var settings = [paths.esdeSettings]
            for snapshot in (try? fm.contentsOfDirectory(at: paths.backups, includingPropertiesForKeys: nil)) ?? [] {
                settings.append(snapshot.appending(path: "Library/Application Support/retromac/ES-DE/settings/es_settings.xml"))
            }
            for file in settings {
                guard let text = try? String(contentsOf: file, encoding: .utf8),
                      oldLibraries.contains(where: { text.contains("value=\"\(ESDESettings.xmlEscape($0))\"") }) else { continue }
                try ESDESettings.merge(existing: text, romDirectory: library).write(to: file, atomically: true, encoding: .utf8)
            }
            try create(paths.esdeFindRules.deletingLastPathComponent())
            try ESDESystems.findRules(retroarch: paths.retroarchExecutable, cores: paths.retroarchCores)
                .write(to: paths.esdeFindRules, atomically: true, encoding: .utf8)
        }

        // 7. Last, so an interrupted run still counts as needed.
        var final = (try? InstallState.load(from: paths.state)) ?? .empty
        final.layoutVersion = Self.layoutVersion
        try final.save(to: paths.state)
    }

    /// Renames `source` into `target`; when both are folders, merges child by child. A file present in
    /// both keeps the target's copy and parks the source's under `leftovers`, so nothing is lost and the
    /// source folder empties out and is removed.
    private func merge(_ source: URL, into target: URL, label: String, leftovers: URL, dryRun: Bool,
                       _ report: inout MigrationReport) throws {
        guard fm.fileExists(atPath: target.path) else {
            if !dryRun { try move(source, to: target, label: label) }
            report.moved.append(label)
            return
        }
        guard isDirectory(source), isDirectory(target) else {
            if !dryRun { try move(source, to: Self.freeName(leftovers), label: label) }
            report.leftAlone.append("\(label) (kept the newer copy)")
            return
        }
        for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
            try merge(child, into: target.appending(path: child.lastPathComponent), label: "\(label)/\(child.lastPathComponent)",
                      leftovers: leftovers.appending(path: child.lastPathComponent), dryRun: dryRun, &report)
        }
        if !dryRun, (try? fm.contentsOfDirectory(atPath: source.path))?.isEmpty == true {
            try? fm.removeItem(at: source)
        }
    }

    private func move(_ source: URL, to target: URL, label: String) throws {
        do {
            try create(target.deletingLastPathComponent())
            try fm.moveItem(at: source, to: target)
        } catch {
            throw MigrationError.moveFailed("\(label): \(error.localizedDescription)")
        }
    }

    private func create(_ dir: URL) throws {
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            throw MigrationError.moveFailed("\(dir.lastPathComponent): \(error.localizedDescription)")
        }
    }

    private func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let volume = { (url: URL) -> String? in
            var probe = url
            while !fm.fileExists(atPath: probe.path), probe.pathComponents.count > 1 { probe.deleteLastPathComponent() }
            return (try? probe.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier).map { "\($0)" }
        }
        return volume(a) != nil && volume(a) == volume(b)
    }

    private func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    static func freeName(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        var n = 2
        while FileManager.default.fileExists(atPath: url.path + " (\(n))") { n += 1 }
        return URL(filePath: url.path + " (\(n))")
    }

    private func currentState() -> InstallState {
        (try? InstallState.load(from: fm.fileExists(atPath: paths.state.path) ? paths.state : legacy.root.appending(path: "state.json")))
            ?? .empty
    }

    private func appNames() -> [String: String] {
        Dictionary(uniqueKeysWithValues: ((try? Manifest.bundled())?.apps ?? []).map { ($0.id, $0.appName) })
    }

    private func managedApps(_ state: InstallState) -> [String] {
        let names = appNames()
        return state.apps.filter(\.value.managed).compactMap { names[$0.key] }
    }
}
