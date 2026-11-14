// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

/// Records every command; `bootout` fails like launchctl does for a service that isn't loaded.
final class LaunchctlRecorder: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var calls: [[String]] { lock.withLock { _calls } }

    func run(_ executable: String, _ args: [String], input: String?) throws -> String {
        lock.withLock { _calls.append([executable] + args) }
        if args.first == "bootout" { throw InstallError.commandFailed(executable, 3, "Boot-out failed: 3: No such process") }
        return ""
    }
}

private func rig() -> (Paths, URL) {
    let home = FileManager.default.temporaryDirectory.appending(path: "agent-\(UUID().uuidString)")
    return (Paths(home: home), URL(filePath: "/Applications/retromac.app"))
}

@Test func plistContent() throws {
    let xml = ConsoleAgent.plist(executable: URL(filePath: "/Applications/retromac.app/Contents/MacOS/retromac-console"))
    let plist = try #require(try PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? [String: Any])
    #expect(plist["Label"] as? String == "petersoft.retromac.console")
    #expect(plist["ProgramArguments"] as? [String] == ["/Applications/retromac.app/Contents/MacOS/retromac-console"])
    #expect(plist["RunAtLoad"] as? Bool == true)
    #expect(plist["KeepAlive"] as? [String: Bool] == ["SuccessfulExit": false])
    #expect(plist["LimitLoadToSessionType"] as? String == "Aqua")
    #expect(plist["ProcessType"] as? String == "Interactive")
    #expect(xml.hasPrefix("<?xml"))
}
@Test func installWritesAndBootstraps() throws {
    let (paths, app) = rig()
    let runner = LaunchctlRecorder()
    let agent = ConsoleAgent(paths: paths, appBundle: app, runner: runner, uid: 501)
    try agent.install()
    #expect(agent.isInstalled)
    let written = try String(contentsOf: paths.consoleAgentPlist, encoding: .utf8)
    #expect(written == ConsoleAgent.plist(executable: app.appending(path: "Contents/MacOS/retromac-console")))
    #expect(runner.calls == [
        ["/bin/launchctl", "bootout", "gui/501/petersoft.retromac.console"],
        ["/bin/launchctl", "bootstrap", "gui/501", paths.consoleAgentPlist.path],
    ])
}
@Test func uninstallBootsOutAndRemoves() throws {
    let (paths, app) = rig()
    let agent = ConsoleAgent(paths: paths, appBundle: app, runner: LaunchctlRecorder(), uid: 501)
    try agent.install()
    let runner = LaunchctlRecorder()
    try ConsoleAgent(paths: paths, appBundle: app, runner: runner, uid: 501).uninstall()
    #expect(!agent.isInstalled)
    #expect(!FileManager.default.fileExists(atPath: paths.consoleAgentPlist.path))
    #expect(runner.calls == [["/bin/launchctl", "bootout", "gui/501/petersoft.retromac.console"]])
}
@Test func uninstallWhenNotInstalledIsQuiet() throws {
    let (paths, app) = rig()
    let agent = ConsoleAgent(paths: paths, appBundle: app, runner: LaunchctlRecorder(), uid: 501)
    try agent.uninstall()
    #expect(!agent.isInstalled)
}

@Test func firstStartIsClaimedOncePerLoginSession() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: "login-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    #expect(ConsoleLogin.claimFirstStart(root: root, sessionID: 100))
    #expect(!ConsoleLogin.claimFirstStart(root: root, sessionID: 100))
    // A new login session is a login again, and clears the old session's marker.
    #expect(ConsoleLogin.claimFirstStart(root: root, sessionID: 101))
    #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).filter { $0.hasPrefix("console-login-") } == ["console-login-101"])
}
@Test func installFromTheAppDoesNotCountAsLogin() throws {
    let (paths, app) = rig()
    try FileManager.default.createDirectory(at: paths.root, withIntermediateDirectories: true)
    try Data(#"{"active":true}"#.utf8).write(to: paths.consoleSession)
    try ConsoleAgent(paths: paths, appBundle: app, runner: LaunchctlRecorder(), uid: 501).install()
    // The agent launchd starts now sees a mid-session start with no active session: it waits for Play.
    let session = try #require(ConsoleLogin.currentSessionID())
    #expect(!ConsoleLogin.claimFirstStart(root: paths.root, sessionID: session))
    #expect(!ConsoleSession(settings: ConsoleSettings(enabled: true, sleep: .standby), stateFile: paths.consoleSession).active)
}
