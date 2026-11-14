// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Security

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

    public static func plist(executable: URL) -> String {
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [executable.path],
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

    /// Writes the plist and (re)loads it, which starts the agent now as well as at every login.
    public func install() throws {
        let executable = appBundle.appending(path: "Contents/MacOS/retromac-console")
        try FileManager.default.createDirectory(at: paths.consoleAgentPlist.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.plist(executable: executable).utf8).write(to: paths.consoleAgentPlist, options: .atomic)
        bootout()
        // launchd starts the agent right away (RunAtLoad). That isn't a login: it should wait for Play
        // rather than launch ES-DE over the app.
        if let session = ConsoleLogin.currentSessionID() { ConsoleLogin.markStarted(root: paths.root, sessionID: session) }
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
    public static func currentSessionID() -> SecuritySessionId? {
        var id = SecuritySessionId()
        var attributes = SessionAttributeBits()
        // SecuritySessionId(-1) is callerSecuritySession, which Swift doesn't import.
        guard SessionGetInfo(SecuritySessionId.max, &id, &attributes) == errSecSuccess else { return nil }
        return id
    }

    /// True the first time it's called for `sessionID`; older sessions' markers are removed.
    public static func claimFirstStart(root: URL, sessionID: SecuritySessionId) -> Bool {
        guard !FileManager.default.fileExists(atPath: marker(root, sessionID).path) else { return false }
        markStarted(root: root, sessionID: sessionID)
        return true
    }

    static func markStarted(root: URL, sessionID: SecuritySessionId) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: root.path)) ?? [] where name.hasPrefix("console-login-") {
            try? fm.removeItem(at: root.appending(path: name))
        }
        try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        fm.createFile(atPath: marker(root, sessionID).path, contents: nil)
    }

    private static func marker(_ root: URL, _ sessionID: SecuritySessionId) -> URL {
        root.appending(path: "console-login-\(sessionID)")
    }
}
