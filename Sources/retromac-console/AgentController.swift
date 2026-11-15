// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import GameController
import QuartzCore
import RetromacCore

/// Wires system events (controllers, wake, ES-DE quitting, messages from retromac.app) to
/// ConsoleSession and carries out the actions it returns.
@MainActor
final class AgentController {
    private let paths: Paths
    private var session: ConsoleSession!
    private var combos = ComboDetector()
    private let standby = StandbyAssertion()
    private var padIDs: [ObjectIdentifier: Int] = [:]
    private var quittingESDE = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var timer: Timer?

    init() {
        var home = FileManager.default.homeDirectoryForCurrentUser
        #if DEBUG
        // Lets a debug build run against a scratch install.
        if let override = ProcessInfo.processInfo.environment["RETROMAC_HOME"] { home = URL(filePath: override) }
        #endif
        paths = Paths(home: home)
    }

    func start() {
        guard let settings = (try? Profile.load(from: paths.profile))?.console, settings.enabled else {
            // A clean exit, so launchd (KeepAlive: SuccessfulExit false) doesn't restart us.
            exit(0)
        }
        session = ConsoleSession(settings: settings, stateFile: paths.consoleSession)
        observeControllers()
        observeSystem()
        handle(.agentStarted(atLogin: isFirstStartThisLogin()))
    }

    // MARK: Events

    private func handle(_ event: ConsoleEvent) {
        let actions = session.handle(event)
        guard !actions.isEmpty else { return }
        Task { await perform(actions) }
    }

    /// launchd restarts a crashed agent in the same login session; that isn't a login.
    private func isFirstStartThisLogin() -> Bool {
        guard let login = ConsoleLogin.current() else { return true }
        return ConsoleLogin.claimFirstStart(root: paths.root, login: login)
    }

    private func observeControllers() {
        GCController.shouldMonitorBackgroundEvents = true
        let center = NotificationCenter.default
        for name in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect] {
            observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncControllers() }
            }))
        }
        syncControllers()
        // Value-change events stop while buttons are held still; poll so a hold fires at 2 s.
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollPads() }
        }
    }

    /// Attaches new controllers and forgets (resetting any half-held combo) ones that went away.
    private func syncControllers() {
        let connected = GCController.controllers()
        let live = Set(connected.map(ObjectIdentifier.init))
        for (key, pad) in padIDs where !live.contains(key) {
            padIDs[key] = nil
            combos.disconnected(pad: pad)
        }
        connected.forEach(attach)
    }

    private func attach(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad, padIDs[ObjectIdentifier(controller)] == nil else { return }
        padIDs[ObjectIdentifier(controller)] = (padIDs.values.max() ?? -1) + 1
        gamepad.valueChangedHandler = { [weak self] gamepad, element in
            let pressed = (element as? GCControllerButtonInput)?.isPressed == true
            MainActor.assumeIsolated {
                guard let self, let controller = gamepad.controller else { return }
                if pressed && CGDisplayIsAsleep(CGMainDisplayID()) != 0 {
                    self.handle(.controllerActivity(displayAsleep: true))
                }
                self.feed(controller)
            }
        }
    }

    private func pollPads() {
        GCController.controllers().forEach(feed)
    }

    private func feed(_ controller: GCController) {
        guard let pad = padIDs[ObjectIdentifier(controller)], let gamepad = controller.extendedGamepad else { return }
        var buttons: PadButtons = []
        if gamepad.leftShoulder.isPressed { buttons.insert(.l1) }
        if gamepad.rightShoulder.isPressed { buttons.insert(.r1) }
        if gamepad.buttonMenu.isPressed { buttons.insert(.start) }
        if gamepad.buttonOptions?.isPressed == true { buttons.insert(.select) }
        if gamepad.buttonHome?.isPressed == true { buttons.insert(.home) }
        if let combo = combos.update(pad: pad, buttons: buttons, at: CACurrentMediaTime()) {
            handle(.combo(combo))
        }
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observers.append((workspace, workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.handle(.wake) }
            }))
        }
        observers.append((workspace, workspace.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleURL?.lastPathComponent == "ES-DE.app" else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                let byAgent = self.quittingESDE
                self.quittingESDE = false
                self.handle(.esdeTerminated(byAgent: byAgent))
            }
        }))

        let distributed = DistributedNotificationCenter.default()
        observers.append((distributed, distributed.addObserver(forName: .init("petersoft.retromac.console.play"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.handle(.play) }
        }))
        observers.append((distributed, distributed.addObserver(forName: .init("petersoft.retromac.console.disabled"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                // Anyone in this login session can post this; act only if the saved profile agrees.
                guard let self, (try? Profile.load(from: self.paths.profile))?.console?.enabled != true else { return }
                _ = self.session.handle(.consoleDisabled)
                self.standby.release()
                exit(0)
            }
        }))
    }

    // MARK: Actions

    private func perform(_ actions: [ConsoleAction]) async {
        for action in actions {
            switch action {
            case .launchESDE: launchESDE()
            case .bringConsoleToFront:
                if let game = running("RetroArch.app") {
                    game.unhide()  // un-pauses (pause_nonactive)
                    game.activate()
                } else {
                    running("ES-DE.app")?.activate()
                }
            case .holdStandbyAssertion: standby.hold()
            case .releaseStandbyAssertion: standby.release()
            case .pauseGame: running("RetroArch.app")?.hide()  // pause_nonactive pauses it while it isn't active
            case .sleepDisplay: Power.sleepDisplay()
            case .sleepSystem: Power.sleepSystem()
            case .declareUserActivity: Power.declareUserActivity()
            case .quitEmulators(let grace):
                // A normal quit lets each emulator save (RetroArch's runs CMD_EVENT_QUIT, which flushes in-game
                // saves); any still running after the grace period (RetroArch can linger idle) is force-quit.
                for name in ESDESystems.emulatorApps {
                    guard let emulator = running(name) else { continue }
                    emulator.terminate()
                    await forceQuit(name, after: grace)
                }
            case .quitESDE(let grace):
                guard let esde = running("ES-DE.app") else { continue }
                quittingESDE = true
                esde.terminate()
                await forceQuit("ES-DE.app", after: grace)
            case .openHome: openHome()
            }
        }
    }

    private func running(_ appName: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.lastPathComponent == appName }
    }

    private func forceQuit(_ appName: String, after grace: Int) async {
        for _ in 0..<(grace * 10) {
            guard running(appName) != nil else { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
        running(appName)?.forceTerminate()
    }

    private func launchESDE() {
        guard running("ES-DE.app") == nil else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ESDELauncher.arguments(paths: paths)
        NSWorkspace.shared.openApplication(at: paths.applications.appending(path: "ES-DE.app"), configuration: configuration)
    }

    /// launchd passes retromac.app's path (see ConsoleAgent.plist).
    private func openHome() {
        guard CommandLine.arguments.count > 1 else { return }
        let app = URL(filePath: CommandLine.arguments[1])
        guard app.pathExtension == "app" else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
