# retromac Console Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An opt-in console mode for a Mac dedicated to the TV.
- **Login and wake** land the player in ES-DE, full screen.
- **Controller combos** put the Mac to rest (true sleep or console standby, the user's choice) or return to the desktop.
- **A wizard step** walks the user through each choice and its security trade-off without ever changing a security setting itself.

**Architecture:**
- **Core logic** lives in `RetromacCore`, and its pure parts are unit-tested:
  - settings
  - a `ComboDetector` state machine fed with button snapshots
  - a `ConsoleSession` state machine that turns events into actions
  - a UDP client for RetroArch's network commands
  - parsers for the system-status probes
  - LaunchAgent install and removal
- **A new executable target, `retromac-console`,** is a background AppKit agent (accessory activation policy) bundled in `retromac.app/Contents/MacOS/`. launchd starts it at login. It wires GameController background monitoring, NSWorkspace wake and app-termination notifications, IOKit power assertions, and `pmset` into `ConsoleSession`.
- **The app** gains a **Console Mode** wizard step. It also tells the agent to start a session when **Play** is pressed, using a distributed notification.

**Tech Stack:** Swift 6, SwiftPM, SwiftUI and AppKit, GameController (`shouldMonitorBackgroundEvents`), IOKit (`IOPMAssertionCreateWithName`, `IOPMAssertionDeclareUserActivity`), Network (`NWConnection` UDP), launchd (`launchctl bootstrap`/`bootout`), `pmset`, `fdesetup`, `sysadminctl`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-13-retromac-design.md`, the "Console mode" section and Resolved decision 9. **Branch:** `console-mode`, stacked on `encapsulation` (PR #4, unmerged).

## Global Constraints

- All earlier constraints still apply: arm64, macOS 14+, zero third-party packages, SPDX headers, and bundle ID `petersoft.retromac`.
- **Opt-in only.** `Profile.console == nil` or `.enabled == false` means no LaunchAgent, no assertions and no RetroArch network commands. Nothing turns console mode on except the user's toggle in the wizard.
- **retromac never writes FileVault, automatic-login or lock-screen settings.** It only reads them (`fdesetup isactive`, the `com.apple.loginwindow` `autoLoginUser` key, `sysadminctl -screenLock status`) and opens System Settings panes.
- **Combos:**
  - L1 + R1 + Start held 2.0 s means sleep.
  - L1 + R1 + Select held 2.0 s means exit.
  - Home + Start and Home + Select are equivalent when the system delivers Home.
  - All buttons must be on the **same** controller.
  - A combo fires once per hold and must be fully released before it can fire again.
- **The exit path always works.** A combo exit asks RetroArch to `QUIT`, terminates it after 5 s, then quits ES-DE (terminating it after 5 s) and opens retromac's home screen.
- **The LaunchAgent** is labelled `petersoft.retromac.console`, lives at `~/Library/LaunchAgents/petersoft.retromac.console.plist`, and runs `<app>/Contents/MacOS/retromac-console`. It sets `RunAtLoad`, `KeepAlive` = `{SuccessfulExit: false}` and `LimitLoadToSessionType` = `Aqua`.
- **Session state persists** in `<root>/console-session.json` (`{"active": Bool, "exitedAt": Date?}`), so a crash-restarted agent never relaunches ES-DE behind a user who exited.
- **Exact UI copy** is in Task 8; use it verbatim.

## Review Focus

1. **ES-DE frozen or not responding when the exit combo fires.** Expected: termination after 5 s, and the home screen opens anyway. The test is in Task 3, through the session's action sequence and its timeouts; the hands-on check is in Task 9.
2. **The agent crashes while the user is at the desktop after exiting.** Expected: launchd restarts it, it reads `console-session.json` (`active: false`), and it does **not** relaunch ES-DE. Test in Task 3.
3. **Console mode turned off while ES-DE is running.** Expected: the agent is booted out, every assertion is released, and ES-DE keeps running (the user can quit it normally). Tests in Tasks 3 and 6.
4. **Combo buttons split across two controllers, or a controller disconnecting mid-hold.** Expected: nothing fires. Test in Task 2.
5. **The sleep combo while the display is already off in standby, or pressed twice quickly.** Expected: one action, no toggling back on, and RetroArch's pause is not toggled off again. Tests in Tasks 3 and 4 (the `GET_STATUS` check before `PAUSE_TOGGLE`).

---

### Task 1: Console settings in the profile, and RetroArch network commands

**Files:**
- Modify: `Sources/RetromacCore/Model/Profile.swift`, `Sources/RetromacCore/Render/ProfileRenderer.swift`, `Sources/RetromacCore/Support/Paths.swift`
- Test: `Tests/RetromacCoreTests/ConsoleSettingsTests.swift`

**Interfaces:**
- Produces:
  - `enum SleepBehavior: String, Codable, Sendable { case trueSleep, standby }`
  - `struct ConsoleSettings: Codable, Equatable, Sendable { var enabled: Bool; var sleep: SleepBehavior }`, with default `ConsoleSettings(enabled: false, sleep: .standby)`
  - `Profile.console: ConsoleSettings?`. It's optional, so existing profiles decode as nil.
  - `Paths.consoleSession` = `<root>/console-session.json`
  - `Paths.consoleAgentPlist` = `home/Library/LaunchAgents/petersoft.retromac.console.plist`
  - The renderer adds `network_cmd_enable = "true"` and `network_cmd_port = "55355"` to the retroarch.cfg keys **only when** `console?.enabled == true`. Otherwise it writes `network_cmd_enable = "false"`, because retromac owns the key.

- [ ] **Step 1: Write the failing tests.**
  - `oldProfilesDecodeWithoutConsole`: profile JSON with no `console` key → `console == nil`.
  - `networkCommandsOnlyInConsoleMode`: render with `console = .init(enabled: true, sleep: .standby)` → keys contain `network_cmd_enable == "true"` and `network_cmd_port == "55355"`. With nil → `network_cmd_enable == "false"`.
  - `consolePaths`: exact paths under `/tmp/h`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `feat: console settings in the profile; RetroArch network commands in console mode`

---

### Task 2: `ComboDetector`

**Files:**
- Create: `Sources/RetromacCore/Console/ComboDetector.swift`
- Test: `Tests/RetromacCoreTests/ComboDetectorTests.swift`

**Interfaces:**
- Produces:
  - `struct PadButtons: OptionSet, Sendable` with `l1, r1, start, select, home`
  - `enum Combo: Equatable, Sendable { case sleep, exit }`
  - `struct ComboDetector { static let hold: TimeInterval = 2.0; mutating func update(pad: Int, buttons: PadButtons, at time: TimeInterval) -> Combo?; mutating func disconnected(pad: Int) }`
    - **Matching:** a pad matches `sleep` when its buttons contain `[l1, r1, start]` or `[home, start]`, and `exit` when they contain `[l1, r1, select]` or `[home, select]`. A pad holding both counts as neither.
    - **Firing:** a combo fires on the first update at which the same pad has held the same match for at least `hold`. It fires once, and after firing the pad must release **all** of those buttons before it can fire again.
    - **Pads:** state is tracked per pad, so buttons never combine across pads.
    - **Disconnecting:** `disconnected` clears that pad's state.

- [ ] **Step 1: Write the failing tests:**
  - `firesAfterTwoSecondHold`: `[l1, r1, start]` at t=0 → nil; at 1.9 → nil; at 2.0 → `.sleep`; at 3.0 → nil (no repeat).
  - `releaseThenHoldAgainFiresAgain`.
  - `homeVariant`: `[home, select]` held for 2 s → `.exit`.
  - `splitAcrossPadsNeverFires`: pad 0 `[l1, r1]` and pad 1 `[start]` for 3 s → nil.
  - `disconnectMidHoldResets`: hold 1.5 s, disconnect, reconnect and hold 1.0 s → nil.
  - `bothCombosHeldIsNeither`: `[l1, r1, start, select]` for 3 s → nil.
  - `changingComboRestartsTimer`: sleep for 1.5 s, then switch to exit at 1.5 → exit fires at 3.5, not earlier.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `feat: controller combo detector`

---

### Task 3: `ConsoleSession` state machine

**Files:**
- Create: `Sources/RetromacCore/Console/ConsoleSession.swift`
- Test: `Tests/RetromacCoreTests/ConsoleSessionTests.swift`

**Interfaces:**
- Consumes: `ConsoleSettings`, `SleepBehavior`, `Combo`, `Paths.consoleSession`
- Produces:
  - `enum ConsoleEvent: Equatable, Sendable { case agentStarted(atLogin: Bool), play, wake, esdeTerminated(byAgent: Bool), combo(Combo), controllerActivity(displayAsleep: Bool), consoleDisabled }`
  - `enum ConsoleAction: Equatable, Sendable { case launchESDE, bringESDEToFront, holdStandbyAssertion, releaseStandbyAssertion, pauseGame, sleepDisplay, sleepSystem, declareUserActivity, quitRetroArch(graceSeconds: Int), quitESDE(graceSeconds: Int), openHome }`
  - `struct ConsoleSession { init(settings: ConsoleSettings, stateFile: URL); private(set) var active: Bool; mutating func handle(_ event: ConsoleEvent) -> [ConsoleAction] }`. `active` is persisted to `stateFile` on every change.

**Transition rules** (anything not listed returns `[]`):

| Event | Condition | Actions | `active` afterwards |
|---|---|---|---|
| `agentStarted(atLogin: true)` | — | `launchESDE, bringESDEToFront` plus `holdStandbyAssertion` if standby | true |
| `agentStarted(atLogin: false)` (crash restart) | persisted `active` is true | `bringESDEToFront` plus `holdStandbyAssertion` if standby | true |
| `agentStarted(atLogin: false)` | persisted `active` is false | `[]` | false |
| `play` | not active | `launchESDE, bringESDEToFront` plus `holdStandbyAssertion` if standby | true |
| `wake` | active | `launchESDE, bringESDEToFront` (`launchESDE` is a no-op if it's running; the agent checks) | true |
| `combo(.sleep)` | active, standby | `pauseGame, sleepDisplay` | true |
| `combo(.sleep)` | active, true sleep | `sleepSystem` | true |
| `combo(.exit)` | active | `quitRetroArch(graceSeconds: 5), quitESDE(graceSeconds: 5), releaseStandbyAssertion, openHome` | false |
| `esdeTerminated(byAgent: false)` | active | `releaseStandbyAssertion` (the user quit ES-DE, which counts as exiting) | false |
| `esdeTerminated(byAgent: true)` | — | `[]` | unchanged |
| `controllerActivity(displayAsleep: true)` | active, standby | `declareUserActivity, bringESDEToFront` | true |
| `consoleDisabled` | — | `releaseStandbyAssertion` (ES-DE keeps running) | false |

- [ ] **Step 1: Write the failing tests.** There's one test per table row, plus:
  - `crashRestartAfterExitDoesNotRelaunch` (Review Focus 2): exit, then build a new session from the same `stateFile`, then `agentStarted(atLogin: false)` → `[]`.
  - `sleepComboTwiceInStandby` (Review Focus 5): the second `combo(.sleep)` while the display is asleep → `pauseGame, sleepDisplay` again. The idempotence is handled in Task 4's pause check, and this test documents it.
  - `disableWhileRunningKeepsESDE` (Review Focus 3): `consoleDisabled` → exactly `[releaseStandbyAssertion]`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `feat: console session state machine`

---

### Task 4: RetroArch command client

**Files:**
- Create: `Sources/RetromacCore/Console/RetroArchCommands.swift`
- Test: `Tests/RetromacCoreTests/RetroArchCommandsTests.swift`

**Interfaces:**
- Produces:
  - `protocol DatagramTransport: Sendable { func send(_ text: String) async throws; func request(_ text: String, timeout: TimeInterval) async throws -> String? }`
  - `struct UDPTransport: DatagramTransport`: `NWConnection` to `127.0.0.1:55355`. `request` returns nil on timeout.
  - `enum PlaybackState: Equatable, Sendable { case playing, paused, contentless, unknown }`, with `static func parse(_ status: String) -> PlaybackState`. It parses replies like `GET_STATUS PLAYING snes,Game,crc32=…`, `GET_STATUS PAUSED …` and `GET_STATUS CONTENTLESS`.
  - `struct RetroArchCommands { init(transport: any DatagramTransport); func pauseIfPlaying() async; func quit() async }`
    - `pauseIfPlaying` sends `GET_STATUS` (1 s timeout) and sends `PAUSE_TOGGLE` only when `.playing`. That keeps a repeated sleep combo from unpausing.
    - `quit` sends `QUIT`.
    - Both swallow errors, because RetroArch might not be running.

- [ ] **Step 1: Verify the command names against the pinned RetroArch v1.22.2 source.** Run `curl -fsSL https://raw.githubusercontent.com/libretro/RetroArch/v1.22.2/command.c | grep -nE '"(GET_STATUS|PAUSE_TOGGLE|QUIT)"'` and look at the `GET_STATUS` reply format in the same file. Record the line numbers in the ledger. If any name differs, **stop and use the real name**, and adjust the tests.
- [ ] **Step 2: Write the failing tests** with a fake transport that records what was sent and returns scripted replies:
  - `pausesOnlyWhenPlaying`: PLAYING → sends `GET_STATUS` then `PAUSE_TOGGLE`. PAUSED → only `GET_STATUS`.
  - `noReplyMeansNoToggle`: timeout → only `GET_STATUS`.
  - `quitSendsQuit`.
  - `parsesStatuses`, covering all four states including garbage → `.unknown`.
- [ ] **Step 3: Run them.** Expected: FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run `swift test`.** Expected: all pass.
- [ ] **Step 6: Commit:** `feat: RetroArch network command client`

---

### Task 5: System status probes and settings panes

**Files:**
- Create: `Sources/RetromacCore/Console/SystemStatus.swift`
- Test: `Tests/RetromacCoreTests/SystemStatusTests.swift`

**Interfaces:**
- Produces:
  - `struct SystemStatus: Equatable, Sendable { var fileVaultOn: Bool?; var autoLoginUser: String?; var passwordAfterWake: PasswordAfterWake }`. A nil `fileVaultOn` means unknown.
  - `enum PasswordAfterWake: Equatable, Sendable { case immediately, after(seconds: Int), off, unknown }`
  - `enum SystemStatusProbe { static func read(runner: any CommandRunner) -> SystemStatus; static func parseFileVault(_ out: String) -> Bool?; static func parseScreenLock(_ out: String) -> PasswordAfterWake }`. The commands it runs:
    - FileVault: `/usr/bin/fdesetup isactive`. "true" means on, "false" means off. A non-zero exit with "false" in the output also means off.
    - Automatic login: `/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser`. A failure means nil.
    - Wake password: `/usr/sbin/sysadminctl -screenLock status`. The status may arrive on stderr, so `CommandRunner` gets a `runCombined` variant (or the probe uses `Process` directly) that captures both streams. It parses `screenLock delay is immediate`, `… is N seconds` and `screenLock is off`.
  - `enum SettingsPane: String { case usersAndGroups = "x-apple.systempreferences:com.apple.Users-Groups-Settings.extension", fileVault = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?FileVault", lockScreen = "x-apple.systempreferences:com.apple.Lock-Screen-Settings.extension" }`

- [ ] **Step 1: Capture the real outputs on this Mac (read-only):** `fdesetup isactive; echo $?`, then `defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser; echo $?`, then `sysadminctl -screenLock status 2>&1`. Paste them into the ledger, and use them verbatim as test fixtures alongside the synthetic variants.
- [ ] **Step 2: Write the failing tests:** `parseFileVault` for "true\n", "false\n" and garbage; `parseScreenLock` for the immediate, 300-seconds and off strings, plus the captured real one; and `readUsesRunner`, a fake runner wiring all three.
- [ ] **Step 3: Run them.** Expected: FAIL.
- [ ] **Step 4: Implement.**
- [ ] **Step 5: Run `swift test`.** Expected: all pass.
- [ ] **Step 6: Verify the panes.** Run `open "<url>"` for each `SettingsPane` and have Mike confirm the right pane appears. Record the result. If one opens the wrong pane, replace it with the URL that works (test with `open`).
- [ ] **Step 7: Commit:** `feat: read FileVault, automatic login and lock-screen status`

---

### Task 6: LaunchAgent install and removal

**Files:**
- Create: `Sources/RetromacCore/Console/ConsoleAgent.swift`
- Test: `Tests/RetromacCoreTests/ConsoleAgentTests.swift`

**Interfaces:**
- Produces: `struct ConsoleAgent { init(paths: Paths, appBundle: URL, runner: any CommandRunner, uid: uid_t = getuid()); static func plist(executable: URL) -> String; func install() throws; func uninstall() throws; var isInstalled: Bool }`
  - **The plist** is an XML property list with:
    - `Label` = `petersoft.retromac.console`
    - `ProgramArguments` = `[<appBundle>/Contents/MacOS/retromac-console]`
    - `RunAtLoad` = true
    - `KeepAlive` = `{SuccessfulExit: false}`
    - `LimitLoadToSessionType` = `Aqua`
    - `ProcessType` = `Interactive`
  - **`install`** writes the plist atomically to `paths.consoleAgentPlist`, then runs `launchctl bootout gui/<uid>/petersoft.retromac.console`, ignoring failure, then `launchctl bootstrap gui/<uid> <plist>`.
  - **`uninstall`** runs `launchctl bootout gui/<uid>/petersoft.retromac.console`, ignoring a "not loaded" failure, then removes the plist.

- [ ] **Step 1: Write the failing tests:**
  - `plistContent`: decode with `PropertyListSerialization` and check every key.
  - `installWritesAndBootstraps`: a recording fake runner checks the exact `launchctl` argument lists and order.
  - `uninstallBootsOutAndRemoves`.
  - `uninstallWhenNotInstalledIsQuiet`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `feat: console LaunchAgent install and removal`

---

### Task 7: The `retromac-console` agent

**Files:**
- Modify: `Package.swift` (adds executable target `retromac-console`, depending on `RetromacCore`), `scripts/bundle.sh` (also builds `retromac-console` and copies it to `Contents/MacOS/`)
- Create: `Sources/retromac-console/main.swift`, `Sources/retromac-console/AgentController.swift`, `Sources/retromac-console/Power.swift`

**Interfaces:**
- Consumes: `ConsoleSession`, `ComboDetector`, `RetroArchCommands`/`UDPTransport`, `ESDELauncher`, `Paths`, `Profile`
- Produces (agent-internal):
  - **`main.swift`:** `NSApplication.shared.setActivationPolicy(.accessory)`, create an `AgentController`, run.
  - **`AgentController`** is `@MainActor`. It loads the profile and exits(0) if console mode is disabled, so launchd doesn't restart it because `SuccessfulExit` is false. Otherwise:
    - **Startup:** builds a `ConsoleSession`, then sends `agentStarted(atLogin:)`.
      - `atLogin` is true when this is the agent's first start in the current login session. The session ID comes from `SessionGetInfo(callerSecuritySession, &id, &attributes)` (Security framework).
      - The marker file `<root>/console-login-<id>` is checked. If it's missing, this is a login: create it (removing older `console-login-*` markers). If it's present, this is a launchd restart after a crash.
    - **Controllers:** `GCController.shouldMonitorBackgroundEvents = true`. On `.GCControllerDidConnect`, it installs `extendedGamepad.valueChangedHandler`, maps the buttons to `PadButtons` (`leftShoulder`, `rightShoulder`, `buttonMenu`, `buttonOptions`, `buttonHome`), and feeds `ComboDetector` with `CACurrentMediaTime()`. A 0.1 s repeating timer also feeds the current snapshot, so a hold fires at 2.0 s even without a new event.
    - **Wake and activity:** `NSWorkspace.didWakeNotification` and `screensDidWakeNotification` send `.wake`. A button press while the display is asleep (`CGDisplayIsAsleep(CGMainDisplayID())`) sends `controllerActivity(displayAsleep: true)`.
    - **ES-DE quitting:** `NSWorkspace.didTerminateApplicationNotification` for ES-DE.app sends `esdeTerminated(byAgent:)`. `byAgent` is true while the agent's own quit is in flight.
    - **Messages from the app:** `DistributedNotificationCenter` notifications `petersoft.retromac.console.play` and `petersoft.retromac.console.disabled` send `.play` and `.consoleDisabled`. After `.consoleDisabled`, it exits(0).
    - **Actions:**

      | Action | What the agent does |
      |---|---|
      | `launchESDE` | If ES-DE isn't running, `NSWorkspace.openApplication` with `ESDELauncher.arguments`. |
      | `bringESDEToFront` | `NSRunningApplication.activate()` |
      | `hold`/`releaseStandbyAssertion` | `IOPMAssertionCreateWithName(kIOPMAssertPreventUserIdleSystemSleep, …, "retromac console standby")` / `IOPMAssertionRelease` |
      | `pauseGame` | `RetroArchCommands.pauseIfPlaying()` |
      | `sleepDisplay` | `/usr/bin/pmset displaysleepnow` |
      | `sleepSystem` | `/usr/bin/pmset sleepnow` |
      | `declareUserActivity` | `IOPMAssertionDeclareUserActivity` |
      | `quitRetroArch(grace)` | `RetroArchCommands.quit()`, then `forceTerminate` RetroArch if still running after `grace` seconds |
      | `quitESDE(grace)` | `terminate()`, then `forceTerminate()` after `grace` seconds |
      | `openHome` | Open retromac.app: the agent's own executable path (`CommandLine.arguments[0]`) with three path components removed (`retromac-console` → `MacOS` → `Contents` → `retromac.app`). It shows the home screen because the app routes there. |

- [ ] **Step 1: Implement.** The agent target has no test target. Its logic lives in the tested core types, and this file only wires system events to them.
- [ ] **Step 2: Run `swift build`, then `scripts/bundle.sh`.** Expected: `build/retromac.app/Contents/MacOS/retromac-console` exists, and `codesign --verify --strict build/retromac.app` exits 0.
- [ ] **Step 3: Check the agent alone with no console settings.** Run `build/retromac.app/Contents/MacOS/retromac-console` with a scratch profile that has console disabled (set the `RETROMAC_HOME` debug override, `#if DEBUG` only, to point `Paths` at the scratchpad). Expected: it exits 0 immediately.
- [ ] **Step 4: Commit:** `feat: retromac-console background agent`

---

### Task 8: Console Mode wizard step and Play integration

**Files:**
- Create: `Sources/retromac/Views/ConsoleStep.swift`, `Sources/retromac/ConsoleModel.swift`
- Modify: `Sources/retromac/WizardModel.swift` (step order display, systems, controllers, **console**, apply; and the apply installs or uninstalls the agent), `Sources/retromac/AppModel.swift` (`play()` posts `petersoft.retromac.console.play` when console is enabled), `Sources/retromac/RetromacApp.swift` (the step switch)

**Interfaces:**
- Produces:
  - `@Observable @MainActor final class ConsoleModel { var status: SystemStatus; func refresh(); func open(_ pane: SettingsPane) }`. `refresh` runs `SystemStatusProbe.read` off the main actor.
  - **Applying.** After a successful Install & Apply:
    - console enabled → `ConsoleAgent.install()`
    - console disabled → `ConsoleAgent.uninstall()`, plus post `petersoft.retromac.console.disabled`

**ConsoleStep layout and exact copy:**
- **Title:** "Console Mode"
- **Intro:** "Turn this Mac into a game console for your TV. When it's on, starting or waking the Mac takes you straight to your games. Only use this on a Mac that's dedicated to gaming."
- **Master toggle: "Start in my games when this Mac turns on or wakes"** (off by default). When it's off, nothing below is shown except the off-flow notes.
- **When it's on, four rows, each with a status line and a button:**
  1. **"Log in automatically"**
     - **Status:**
       - FileVault on → "Off — FileVault disk encryption is on. macOS doesn't allow automatic login while FileVault is on."
       - Automatic login set → "On for <user>".
       - Otherwise → "Off".
     - **Explanation:** "Without this, you'll see the login screen when the Mac starts. Turning off FileVault lets anyone who has this Mac read what's on its disk. retromac doesn't change these settings — you choose in System Settings."
     - **Buttons:** "Open FileVault Settings" (when FileVault is on), otherwise "Open Users & Groups".
  2. **"Skip the password when waking"**
     - **Status:** immediately/after N seconds → "Password required after sleep"; off → "No password after sleep".
     - **Explanation:** "Without this, waking the Mac shows a password prompt. With it, anyone at the TV can get into this Mac account."
     - **Button:** "Open Lock Screen Settings".
  3. **"When you put the console to sleep"**, a segmented picker:
     - **Console standby** — "The screen turns off but the Mac stays awake. Press any button on your controller to come back. Uses a little power while resting."
     - **Sleep** — "The Mac fully sleeps and uses almost no power. Wake it with the power button or a keyboard — macOS can't wake from a game controller."
  4. **"Controller shortcuts"** (information only): "Hold L + R + Start for 2 seconds to put the console to sleep. Hold L + R + Select for 2 seconds to go back to the desktop."
- **Check again** re-runs the status probe.
- **Off-flow notes,** shown when the master toggle goes from on to off and any relaxed setting is detected: "You may want to turn these back on:", followed by rows for automatic login (if set), the password after sleep (if off), and FileVault (if off), each with its open-pane button.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run `swift build && swift test`, then `scripts/bundle.sh` and `codesign --verify --strict build/retromac.app`.** Expected: success.
- [ ] **Step 3: Commit:** `feat: Console Mode wizard step and Play integration`

---

### Task 9: End-to-end on Mike's Mac

These steps install a login agent, and may involve Mike changing system settings himself. **Confirm with Mike before Step 2.**

- [ ] **Step 1: Install the build as `/Applications/retromac.app`** (stamped `0.3.0`, as in the encapsulation E2E), after quitting the running copy.
- [ ] **Step 2: Mike runs Settings › Console Mode.** He turns it on, reads the rows, follows the System Settings buttons for whatever he chooses, presses **Check again**, picks **Console standby**, then clicks Install & Apply. Verify `launchctl print gui/$(id -u)/petersoft.retromac.console` shows it running, and that the plist exists.
- [ ] **Step 3: Log out and back in, or restart.** Expected: ES-DE opens full screen without touching the mouse.
- [ ] **Step 4: Sleep in standby.** Mike starts a game, then holds L + R + Start for 2 s. Expected: the game pauses and the screen turns off. Pressing a controller button turns the screen back on, in the game (still paused), with ES-DE or RetroArch in front. `pmset -g assertions` shows "retromac console standby" while the session runs.
- [ ] **Step 5: Exit.** Mike holds L + R + Select for 2 s. Expected: RetroArch and ES-DE quit, and retromac's home screen appears. Waking the display afterwards does **not** relaunch ES-DE.
- [ ] **Step 6: Mike presses Play.** Expected: ES-DE opens, and the session is active again (combos work).
- [ ] **Step 7: Mike turns console mode off in Settings.** Expected: the agent is gone from `launchctl print`, `pmset -g assertions` no longer lists it, and the off-flow notes list any settings he relaxed.
- [ ] **Step 8: Report the results with command output.**
