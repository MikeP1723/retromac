// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

private let standby = ConsoleSettings(enabled: true, sleep: .standby)
private let trueSleep = ConsoleSettings(enabled: true, sleep: .trueSleep)

private func stateFile() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "console-\(UUID().uuidString)/console-session.json")
}

/// A session that is already active (started at login).
private func activeSession(_ settings: ConsoleSettings = standby, file: URL = stateFile()) -> ConsoleSession {
    var s = ConsoleSession(settings: settings, stateFile: file)
    _ = s.handle(.agentStarted(atLogin: true))
    return s
}

@Test func loginStartLaunchesAndHoldsStandby() {
    var s = ConsoleSession(settings: standby, stateFile: stateFile())
    #expect(s.handle(.agentStarted(atLogin: true)) == [.launchESDE, .bringConsoleToFront, .holdStandbyAssertion])
    #expect(s.active)
}
@Test func loginStartInTrueSleepHoldsNothing() {
    var s = ConsoleSession(settings: trueSleep, stateFile: stateFile())
    #expect(s.handle(.agentStarted(atLogin: true)) == [.launchESDE, .bringConsoleToFront])
    #expect(s.active)
}
@Test func crashRestartWhileActiveResumes() {
    let file = stateFile()
    _ = activeSession(file: file)
    var restarted = ConsoleSession(settings: standby, stateFile: file)
    #expect(restarted.handle(.agentStarted(atLogin: false)) == [.bringConsoleToFront, .holdStandbyAssertion])
    #expect(restarted.active)
}
@Test func crashRestartWhileInactiveDoesNothing() {
    var s = ConsoleSession(settings: standby, stateFile: stateFile())
    #expect(s.handle(.agentStarted(atLogin: false)) == [])
    #expect(!s.active)
}
@Test func playWhenInactiveStarts() {
    var s = ConsoleSession(settings: standby, stateFile: stateFile())
    #expect(s.handle(.play) == [.launchESDE, .bringConsoleToFront, .holdStandbyAssertion])
    #expect(s.active)
}
@Test func wakeWhenActiveRelaunches() {
    var s = activeSession()
    #expect(s.handle(.wake) == [.launchESDE, .bringConsoleToFront])
    #expect(s.active)
}
@Test func wakeWhenInactiveDoesNothing() {
    var s = ConsoleSession(settings: standby, stateFile: stateFile())
    #expect(s.handle(.wake) == [])
}
@Test func sleepComboInStandbyPausesAndDims() {
    var s = activeSession()
    #expect(s.handle(.combo(.sleep)) == [.pauseGame, .sleepDisplay])
    #expect(s.active)
}
@Test func sleepComboInTrueSleepSleepsSystem() {
    var s = activeSession(trueSleep)
    #expect(s.handle(.combo(.sleep)) == [.sleepSystem])
    #expect(s.active)
}
@Test func exitComboQuitsEverything() {
    var s = activeSession()
    #expect(s.handle(.combo(.exit)) == [.quitRetroArch(graceSeconds: 5), .quitESDE(graceSeconds: 5), .releaseStandbyAssertion, .openHome])
    #expect(!s.active)
}
@Test func combosWhenInactiveDoNothing() {
    var s = ConsoleSession(settings: standby, stateFile: stateFile())
    #expect(s.handle(.combo(.sleep)) == [])
    #expect(s.handle(.combo(.exit)) == [])
}
@Test func userQuittingESDEEndsSession() {
    var s = activeSession()
    #expect(s.handle(.esdeTerminated(byAgent: false)) == [.releaseStandbyAssertion])
    #expect(!s.active)
}
@Test func agentQuittingESDEChangesNothing() {
    var s = activeSession()
    #expect(s.handle(.esdeTerminated(byAgent: true)) == [])
    #expect(s.active)
}
@Test func controllerWakesDisplayInStandby() {
    var s = activeSession()
    #expect(s.handle(.controllerActivity(displayAsleep: true)) == [.declareUserActivity, .bringConsoleToFront])
    #expect(s.handle(.controllerActivity(displayAsleep: false)) == [])
}
@Test func controllerActivityInTrueSleepDoesNothing() {
    var s = activeSession(trueSleep)
    #expect(s.handle(.controllerActivity(displayAsleep: true)) == [])
}
@Test func disableWhileRunningKeepsESDE() {
    var s = activeSession()
    #expect(s.handle(.consoleDisabled) == [.releaseStandbyAssertion])
    #expect(!s.active)
}
@Test func crashRestartAfterExitDoesNotRelaunch() {
    let file = stateFile()
    var s = activeSession(file: file)
    _ = s.handle(.combo(.exit))
    var restarted = ConsoleSession(settings: standby, stateFile: file)
    #expect(restarted.handle(.agentStarted(atLogin: false)) == [])
    #expect(!restarted.active)
}
@Test func sleepComboTwiceInStandby() {
    var s = activeSession()
    _ = s.handle(.combo(.sleep))
    #expect(s.handle(.combo(.sleep)) == [.pauseGame, .sleepDisplay])
}
