// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum ConsoleEvent: Equatable, Sendable {
    case agentStarted(atLogin: Bool)
    case play
    case wake
    case esdeTerminated(byAgent: Bool)
    case combo(Combo)
    case controllerActivity(displayAsleep: Bool)
    case consoleDisabled
}

public enum ConsoleAction: Equatable, Sendable {
    case launchESDE
    case bringESDEToFront
    case holdStandbyAssertion
    case releaseStandbyAssertion
    case pauseGame
    case sleepDisplay
    case sleepSystem
    case declareUserActivity
    case quitRetroArch(graceSeconds: Int)
    case quitESDE(graceSeconds: Int)
    case openHome
}

/// Decides what the console agent does for each event. `active` (a console session is running) is
/// persisted so a crash-restarted agent resumes the session rather than starting one the user exited.
public struct ConsoleSession {
    let settings: ConsoleSettings
    let stateFile: URL

    public private(set) var active: Bool {
        didSet { if active != oldValue { save() } }
    }

    struct State: Codable { var active: Bool }

    public init(settings: ConsoleSettings, stateFile: URL) {
        self.settings = settings
        self.stateFile = stateFile
        active = (try? JSONDecoder().decode(State.self, from: Data(contentsOf: stateFile)))?.active ?? false
    }

    public mutating func handle(_ event: ConsoleEvent) -> [ConsoleAction] {
        let standby = settings.sleep == .standby
        let hold: [ConsoleAction] = standby ? [.holdStandbyAssertion] : []
        switch event {
        case .agentStarted(atLogin: true):
            active = true
            return [.launchESDE, .bringESDEToFront] + hold
        case .agentStarted(atLogin: false):
            return active ? [.bringESDEToFront] + hold : []
        case .play:
            guard !active else { return [] }
            active = true
            return [.launchESDE, .bringESDEToFront] + hold
        case .wake:
            return active ? [.launchESDE, .bringESDEToFront] : []
        case .combo(.sleep):
            guard active else { return [] }
            return standby ? [.pauseGame, .sleepDisplay] : [.sleepSystem]
        case .combo(.exit):
            guard active else { return [] }
            active = false
            return [.quitRetroArch(graceSeconds: 5), .quitESDE(graceSeconds: 5), .releaseStandbyAssertion, .openHome]
        case .esdeTerminated(byAgent: false):
            guard active else { return [] }
            active = false
            return [.releaseStandbyAssertion]
        case .esdeTerminated(byAgent: true):
            return []
        case .controllerActivity(let displayAsleep):
            return active && standby && displayAsleep ? [.declareUserActivity, .bringESDEToFront] : []
        case .consoleDisabled:
            active = false
            return [.releaseStandbyAssertion]
        }
    }

    /// Best effort: losing the file only means a crash restart won't resume the session.
    private func save() {
        try? FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(State(active: active)).write(to: stateFile, options: .atomic)
    }
}
