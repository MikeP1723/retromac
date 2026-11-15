// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

/// Answers per executable: nil succeeds, a string throws commandFailed with that stderr.
final class FailingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var calls: [[String]] { lock.withLock { _calls } }
    let failures: [String: String]

    init(failing failures: [String: String] = [:]) { self.failures = failures }

    func run(_ executable: String, _ args: [String], input: String?) throws -> String {
        lock.withLock { _calls.append([executable] + args) }
        if let stderr = failures[executable] { throw InstallError.commandFailed(executable, 1, stderr) }
        return ""
    }
}

@Test func installedWhenX86Runs() {
    let runner = FailingRunner()
    #expect(Rosetta(runner: runner).isInstalled)
    #expect(runner.calls == [["/usr/bin/arch", "-x86_64", "/usr/bin/true"]])
}
@Test func notInstalledWhenX86Fails() {
    #expect(!Rosetta(runner: FailingRunner(failing: ["/usr/bin/arch": "Bad CPU type in executable"])).isInstalled)
}
@Test func installRunsTheFixedAdminCommand() {
    let runner = FailingRunner()
    #expect(Rosetta(runner: runner).install() == .installed)
    #expect(runner.calls == [["/usr/bin/osascript", "-e",
        #"do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges"#]])
}
@Test func cancelledPromptIsDeclined() {
    let runner = FailingRunner(failing: ["/usr/bin/osascript": "0:91: execution error: User canceled. (-128)"])
    #expect(Rosetta(runner: runner).install() == .declined)
}
@Test func otherFailureIsReported() {
    let runner = FailingRunner(failing: ["/usr/bin/osascript": "execution error: softwareupdate failed (1)"])
    #expect(Rosetta(runner: runner).install() == .failed("execution error: softwareupdate failed (1)"))
}
@Test func supportedThroughMacOS27() {
    #expect(Rosetta.isSupported(osMajor: 27) && !Rosetta.isSupported(osMajor: 28))
    #expect(Rosetta.warning == "This system depends on Rosetta, which Apple is phasing out after macOS 27.")
}
