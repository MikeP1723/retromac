// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// libretro's per-core build list for the arm64 nightly directory.
public struct CoreIndex: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var date: String
        /// CRC32 of the dylib inside the archive (not of the archive).
        public var crc32: String
    }

    public var entries: [String: Entry]

    public static let url = URL(string: "https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/.index-extended")!

    /// Lines are `<date> <8 hex crc> <archive name>`; anything else is skipped.
    public static func parse(_ text: String) -> CoreIndex {
        var entries: [String: Entry] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 2)
            guard fields.count == 3, fields[1].count == 8, fields[1].allSatisfy(\.isHexDigit) else { continue }
            entries[String(fields[2])] = Entry(date: String(fields[0]), crc32: fields[1].lowercased())
        }
        return CoreIndex(entries: entries)
    }
}

public enum ComponentKind: String, Codable, Sendable {
    case app, core
}

public struct ComponentUpdate: Equatable, Sendable, Identifiable {
    public var id: String
    public var kind: ComponentKind
    public var installed: String
    public var available: String
    public var managed: Bool
    public var license: String
    /// Set only when the license differs from the installed entry's.
    public var previousLicense: String?
    public var requiresRosetta: Bool
}

public struct UpdatePlan: Equatable, Sendable {
    public var updates: [ComponentUpdate]
    public var retromacUpdate: SelfEntry?
    public var blockedByMinAppVersion: String?
}

public enum UpdatePlanner {
    public static func plan(state: InstallState, applied: Manifest, latest: Manifest,
                            coreIndex: CoreIndex?, appVersion: String) -> UpdatePlan {
        let selfUpdate = latest.retromac.flatMap {
            SemVer.compare($0.version, appVersion) == .orderedDescending ? $0 : nil
        }
        if SemVer.compare(appVersion, latest.minAppVersion) == .orderedAscending {
            return UpdatePlan(updates: [], retromacUpdate: selfUpdate, blockedByMinAppVersion: latest.minAppVersion)
        }

        var updates: [ComponentUpdate] = []
        for app in latest.apps {
            guard let installed = state.apps[app.id],
                  installed.version != app.version || (installed.sha256.map { $0 != app.sha256 } ?? false) else { continue }
            let old = applied.apps.first { $0.id == app.id }?.license
            updates.append(ComponentUpdate(
                id: app.id, kind: .app, installed: installed.version, available: app.version, managed: installed.managed,
                license: app.license, previousLicense: old != app.license ? old : nil, requiresRosetta: app.rosetta))
        }
        for core in latest.cores {
            guard let installed = state.cores[core.id] else { continue }
            let available: String
            if let sha = core.sha256 {
                guard sha != installed.sha256 else { continue }
                available = core.version
            } else {
                guard let entry = coreIndex?.entries["\(core.file).zip"], entry.crc32 != installed.crc32 else { continue }
                available = "rebuild \(entry.date)"
            }
            let old = applied.cores.first { $0.id == core.id }?.license
            updates.append(ComponentUpdate(
                id: core.id, kind: .core, installed: installed.version, available: available, managed: true,
                license: core.license, previousLicense: old != core.license ? old : nil, requiresRosetta: core.rosetta))
        }
        return UpdatePlan(updates: updates.sorted { $0.id < $1.id }, retromacUpdate: selfUpdate, blockedByMinAppVersion: nil)
    }
}
