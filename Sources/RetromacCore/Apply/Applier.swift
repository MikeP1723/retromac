// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct ApplyReport: Equatable, Sendable {
    public var written: [URL]
    public var unchanged: [URL]
    public var backup: URL?
}

public enum ApplyError: Error, Equatable {
    /// RetroArch and ES-DE rewrite their config on exit and would undo the apply.
    case appRunning(String)
}

public struct Applier: Sendable {
    let paths: Paths
    /// App bundle names (e.g. "ES-DE.app"); bundle IDs aren't reliable (ES-DE's is its version).
    let apps: [String]
    let isRunning: @Sendable (String) -> Bool

    public init(paths: Paths, apps: [String], isRunning: @escaping @Sendable (String) -> Bool) {
        self.paths = paths
        self.apps = apps
        self.isRunning = isRunning
    }

    public func apply(_ files: [RenderedFile]) throws -> ApplyReport {
        if let running = apps.first(where: isRunning) {
            throw ApplyError.appRunning(running)
        }
        let fm = FileManager.default
        var changed: [(URL, String)] = []
        var newDirs: [URL] = []
        var unchanged: [URL] = []

        for file in files {
            if file.kind == .directory {
                fm.fileExists(atPath: file.url.path) ? unchanged.append(file.url) : newDirs.append(file.url)
                continue
            }
            // Only a missing file counts as empty; anything unreadable must stop the apply,
            // or merging into "" would discard the user's settings.
            let current = fm.fileExists(atPath: file.url.path) ? try String(contentsOf: file.url, encoding: .utf8) : nil
            let final: String
            switch file.kind {
            case .retroarchKeys(let keys): final = RetroArchConfig.merge(existing: current ?? "", owned: keys)
            case .esdeSettings(let dir): final = ESDESettings.merge(existing: current, romDirectory: dir)
            case .esdeSystems(let ours): final = try ESDESystems.merge(existing: current, ours: ours)
            case .whole(let text): final = text
            case .directory: continue
            }
            final == current ? unchanged.append(file.url) : changed.append((file.url, final))
        }

        let created = changed.map(\.0).filter { !fm.fileExists(atPath: $0.path) }
        let backup = try BackupStore(root: paths.backups, home: paths.home).snapshot(changed.map(\.0), created: created)
        for (url, content) in changed {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        for dir in newDirs {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return ApplyReport(written: changed.map(\.0) + newDirs, unchanged: unchanged, backup: backup)
    }
}
