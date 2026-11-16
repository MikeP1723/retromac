// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Ryubing, the Switch emulator. The user installs it and sets it up themselves; retromac only finds it
/// and sets a few of its settings once it knows the settings format.
public enum Ryubing {
    public enum Status: Equatable, Sendable { case notInstalled, noConfig, unknownVersion, ready }

    public static let warning = "For advanced users. Needs Ryubing, which you install yourself, and keys and firmware from your own Switch, set up inside Ryubing. retromac can't do those steps for you."
    public static let installStep = "Move Ryujinx.app to Applications. The first time you open it, macOS blocks it; allow it in System Settings › Privacy & Security › Open Anyway."
    public static let setupStep = "Ryubing will say 'Keys not found' until you add them. In Ryubing, use the File menu to install your keys and firmware, then set up your controller under Options › Settings › Input › Player 1. Quit Ryubing and click Done."
    public static let ready = "Switch games now show in Play."
    public static let noConfig = "Open Ryubing once, then click Done again."
    public static let unknownVersion = "Ryubing was updated; retromac can't set it up until retromac updates too."
    public static let quitFirst = "Quit Ryubing, then click Done."

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
