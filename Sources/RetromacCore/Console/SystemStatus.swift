// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum PasswordAfterWake: Equatable, Sendable {
    case immediately, after(seconds: Int), off, unknown
}

/// The macOS settings that decide whether console mode can reach ES-DE without a password prompt.
public struct SystemStatus: Equatable, Sendable {
    /// nil when it couldn't be read.
    public var fileVaultOn: Bool?
    public var autoLoginUser: String?
    public var passwordAfterWake: PasswordAfterWake

    public init(fileVaultOn: Bool?, autoLoginUser: String?, passwordAfterWake: PasswordAfterWake) {
        self.fileVaultOn = fileVaultOn
        self.autoLoginUser = autoLoginUser
        self.passwordAfterWake = passwordAfterWake
    }
}

/// Read-only probes; retromac never changes these settings itself.
public enum SystemStatusProbe {
    public static func read(runner: any CommandRunner) -> SystemStatus {
        let autoLogin = (try? runner.run("/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.loginwindow", "autoLoginUser"]))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return SystemStatus(fileVaultOn: combined("/usr/bin/fdesetup isactive", runner).flatMap(parseFileVault),
                            autoLoginUser: autoLogin?.isEmpty == false ? autoLogin : nil,
                            passwordAfterWake: combined("/usr/sbin/sysadminctl -screenLock status", runner).map(parseScreenLock) ?? .unknown)
    }

    /// `fdesetup isactive` exits 1 when FileVault is off, and sysadminctl reports on stderr; capture both
    /// streams whatever the exit status. `command` is always a constant.
    private static func combined(_ command: String, _ runner: any CommandRunner) -> String? {
        try? runner.run("/bin/sh", ["-c", "\(command) 2>&1; exit 0"])
    }

    public static func parseFileVault(_ out: String) -> Bool? {
        switch out.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "true": true
        case "false": false
        default: nil
        }
    }

    /// Parses `screenLock delay is immediate`, `screenLock delay is N seconds` or `screenLock is off`,
    /// ignoring the log prefix sysadminctl puts in front.
    public static func parseScreenLock(_ out: String) -> PasswordAfterWake {
        if out.contains("screenLock delay is immediate") { return .immediately }
        if out.contains("screenLock is off") { return .off }
        if let match = out.firstMatch(of: /screenLock delay is (\d+) seconds/), let seconds = Int(match.1) {
            return .after(seconds: seconds)
        }
        return .unknown
    }
}

/// System Settings panes the console wizard step links to.
public enum SettingsPane: String, CaseIterable, Sendable {
    case usersAndGroups = "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension"
    case fileVault = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault"
    case lockScreen = "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension"

    public var url: URL { URL(string: rawValue)! }
}
