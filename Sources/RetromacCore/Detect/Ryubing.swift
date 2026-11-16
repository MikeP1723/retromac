// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Ryubing, the Switch emulator. The user installs it and sets it up themselves; retromac only finds it
/// and sets a few of its settings once it knows the settings format.
public enum Ryubing {
    public enum Status: Equatable, Sendable { case notInstalled, noConfig, unknownVersion, ready }

    /// Config.json versions whose keys retromac knows.
    public static let knownConfigVersions: Set<Int> = [70]

    public static func status(paths: Paths) -> Status {
        guard FileManager.default.fileExists(atPath: paths.ryubingExecutable.path) else { return .notInstalled }
        guard let data = FileManager.default.contents(atPath: paths.ryubingConfig.path) else { return .noConfig }
        return configVersion(data).map(knownConfigVersions.contains) == true ? .ready : .unknownVersion
    }

    /// Switch is in ES-DE and its settings are written only once the user chose it, installed Ryubing,
    /// clicked Done and Ryubing's settings are in a known format.
    public static func isLive(_ p: Profile, paths: Paths) -> Bool {
        p.systems.contains(.switch) && p.switchSetup?.confirmed == true && status(paths: paths) == .ready
    }

    static func configVersion(_ data: Data) -> Int? {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["version"] as? Int
    }
}
