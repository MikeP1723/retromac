// SPDX-License-Identifier: GPL-3.0-or-later

public enum RosettaInstall: Equatable, Sendable {
    case installed, declined, failed(String)
}

/// Rosetta 2, which the x86_64-only emulators (PCSX2) need. Apple has said macOS 27 is the last release
/// with general-purpose Rosetta.
public struct Rosetta: Sendable {
    public static let warning = "This system depends on Rosetta, which Apple is phasing out after macOS 27."

    let runner: any CommandRunner

    public init(runner: any CommandRunner) { self.runner = runner }

    /// An x86_64 binary runs only with Rosetta installed ("Bad CPU type in executable" without it).
    public var isInstalled: Bool {
        (try? runner.run("/usr/bin/arch", ["-x86_64", "/usr/bin/true"])) != nil
    }

    /// One admin prompt. The command is a fixed string; nothing is interpolated into it.
    public func install() -> RosettaInstall {
        let script = #"do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges"#
        do {
            try runner.run("/usr/bin/osascript", ["-e", script])
            return .installed
        } catch InstallError.commandFailed(_, _, let stderr) {
            return stderr.contains("(-128)") ? .declined : .failed(stderr)
        } catch {
            return .failed(String(describing: error))
        }
    }

    public static func isSupported(osMajor: Int) -> Bool { osMajor <= 27 }
}
