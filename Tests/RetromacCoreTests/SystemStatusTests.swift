// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func parsesFileVault() {
    #expect(SystemStatusProbe.parseFileVault("true\n") == true)
    #expect(SystemStatusProbe.parseFileVault("false\n") == false)
    #expect(SystemStatusProbe.parseFileVault("fdesetup: something odd\n") == nil)
    #expect(SystemStatusProbe.parseFileVault("") == nil)
}
@Test func parsesScreenLock() {
    // Captured on a real Mac: sysadminctl logs the status to stderr with a timestamp prefix.
    #expect(SystemStatusProbe.parseScreenLock("2026-11-13 21:44:45.598 sysadminctl[3176:1315086] screenLock delay is immediate\n") == .immediately)
    #expect(SystemStatusProbe.parseScreenLock("screenLock delay is immediate") == .immediately)
    #expect(SystemStatusProbe.parseScreenLock("screenLock delay is 300 seconds") == .after(seconds: 300))
    #expect(SystemStatusProbe.parseScreenLock("screenLock is off") == .off)
    #expect(SystemStatusProbe.parseScreenLock("sysadminctl: unrecognized") == .unknown)
}

/// Answers by the command line it is handed; anything unscripted fails like a missing key.
struct ScriptedRunner: CommandRunner {
    let replies: [String: String]

    func run(_ executable: String, _ args: [String], input: String?) throws -> String {
        let line = ([executable] + args).joined(separator: " ")
        guard let reply = replies.first(where: { line.contains($0.key) })?.value else {
            throw InstallError.commandFailed(executable, 1, "not scripted: \(line)")
        }
        return reply
    }
}

@Test func readUsesRunner() {
    let runner = ScriptedRunner(replies: [
        "fdesetup isactive": "false\n",
        "autoLoginUser": "tv\n",
        "sysadminctl -screenLock status": "2026-11-13 21:44:45.598 sysadminctl[1:2] screenLock delay is 60 seconds\n",
    ])
    #expect(SystemStatusProbe.read(runner: runner)
        == SystemStatus(fileVaultOn: false, autoLoginUser: "tv", passwordAfterWake: .after(seconds: 60)))
}
@Test func readWithEverythingFailingIsUnknown() {
    #expect(SystemStatusProbe.read(runner: ScriptedRunner(replies: [:]))
        == SystemStatus(fileVaultOn: nil, autoLoginUser: nil, passwordAfterWake: .unknown))
}
