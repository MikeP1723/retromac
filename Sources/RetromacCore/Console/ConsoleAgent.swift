// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Security

public enum ConsoleAgentError: Error, Equatable {
    /// The LaunchAgent stores retromac's path; anywhere but an Applications folder it may not survive.
    case notInApplications
}

/// The per-user LaunchAgent that runs `retromac-console` at login while console mode is on.
public struct ConsoleAgent {
    public static let label = "petersoft.retromac.console"
    static let launchctl = "/bin/launchctl"

    let paths: Paths
    let appBundle: URL
    let runner: any CommandRunner
    let uid: uid_t

    public init(paths: Paths, appBundle: URL, runner: any CommandRunner, uid: uid_t = getuid()) {
        self.paths = paths
        self.appBundle = appBundle
        self.runner = runner
        self.uid = uid
    }

    /// A nested app with its own bundle ID: run from retromac.app's own Contents/MacOS, it would register
    /// as retromac itself, and opening retromac would only reach the windowless agent.
    public static func executable(in app: URL) -> URL {
        app.appending(path: "Contents/Library/LoginItems/retromac-console.app/Contents/MacOS/retromac-console")
    }

    /// The agent gets retromac.app's path as its argument, to open the home screen on exit.
    public static func plist(app: URL) -> String {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable(in: app).path, app.path],
            "RunAtLoad": true,
            // Relaunch after a crash, not after the agent exits cleanly.
            "KeepAlive": ["SuccessfulExit": false],
            "LimitLoadToSessionType": "Aqua",
            "ProcessType": "Interactive",
        ]
        let data = try! PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        return String(decoding: data, as: UTF8.self)
    }

    public var isInstalled: Bool { FileManager.default.fileExists(atPath: paths.consoleAgentPlist.path) }

    /// Installed, but for a different copy of retromac (it was moved or replaced): install again.
    public var needsRepair: Bool {
        guard let data = FileManager.default.contents(atPath: paths.consoleAgentPlist.path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return false }
        return plist["ProgramArguments"] as? [String] != [Self.executable(in: appBundle).path, appBundle.path]
    }

    /// Writes the plist and (re)loads it, which starts the agent now as well as at every login.
    public func install() throws {
        // Not translocated, not in Downloads: somewhere the path in the plist keeps working.
        let parent = appBundle.deletingLastPathComponent().standardizedFileURL.path
        guard parent == "/Applications" || parent == paths.home.appending(path: "Applications").standardizedFileURL.path else {
            throw ConsoleAgentError.notInApplications
        }
        try FileManager.default.createDirectory(at: paths.consoleAgentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.plist(app: appBundle).utf8).write(to: paths.consoleAgentPlist, options: .atomic)
        bootout()
        // launchd starts the agent right away (RunAtLoad). That isn't a login: it should wait for Play
        // rather than launch ES-DE over the app.
        if let login = ConsoleLogin.current() { ConsoleLogin.markStarted(root: paths.root, login: login) }
        try? FileManager.default.removeItem(at: paths.consoleSession)
        try runner.run(Self.launchctl, ["bootstrap", "gui/\(uid)", paths.consoleAgentPlist.path])
    }

    public func uninstall() throws {
        bootout()
        if isInstalled { try FileManager.default.removeItem(at: paths.consoleAgentPlist) }
    }

    /// Fails when the agent isn't loaded, which is fine either way: without the plist it won't start again.
    private func bootout() {
        _ = try? runner.run(Self.launchctl, ["bootout", "gui/\(uid)/\(Self.label)"])
    }
}

/// Tells the agent's first start in a login session (a login) from launchd restarting it after a crash,
/// with one marker file per login session.
public enum ConsoleLogin {
    /// This login: boot time plus the audit session ID. Session IDs restart from the same counter on
    /// every boot, so the ID alone can repeat across a reboot and a login would look like a restart.
    public static func current() -> String? {
        var id = SecuritySessionId()
        var attributes = SessionAttributeBits()
        // SecuritySessionId(-1) is callerSecuritySession, which Swift doesn't import.
        guard SessionGetInfo(SecuritySessionId.max, &id, &attributes) == errSecSuccess else { return nil }
        var boot = timeval(), size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else { return nil }
        return "\(boot.tv_sec)-\(id)"
    }

    /// True the first time it's called for `login`; older logins' markers are removed.
    public static func claimFirstStart(root: URL, login: String) -> Bool {
        guard !FileManager.default.fileExists(atPath: marker(root, login).path) else { return false }
        markStarted(root: root, login: login)
        return true
    }

    static func markStarted(root: URL, login: String) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where name.hasPrefix("console-login-") {
            try? fm.removeItem(at: root.appending(path: name))
        }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        fm.createFile(atPath: marker(root, login).path, contents: nil)
    }

    private static func marker(_ root: URL, _ login: String) -> URL {
        root.appending(path: "console-login-\(login)")
    }
}
