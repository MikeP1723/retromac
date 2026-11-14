// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct PadButtons: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let l1 = PadButtons(rawValue: 1 << 0)
    public static let r1 = PadButtons(rawValue: 1 << 1)
    public static let start = PadButtons(rawValue: 1 << 2)
    public static let select = PadButtons(rawValue: 1 << 3)
    public static let home = PadButtons(rawValue: 1 << 4)
}

public enum Combo: Equatable, Sendable {
    case sleep, exit
}

/// Recognizes the console-mode combos: L1+R1+Start / Home+Start (sleep) and L1+R1+Select / Home+Select
/// (exit), held for two seconds on one controller. Each hold fires once.
public struct ComboDetector: Sendable {
    public static let hold: TimeInterval = 2.0

    struct PadState: Sendable {
        var combo: Combo?
        var since: TimeInterval = 0
        /// The combo that already fired and must be released before it can fire again.
        var fired: Combo?
    }

    var pads: [Int: PadState] = [:]

    public init() {}

    public mutating func update(pad: Int, buttons: PadButtons, at time: TimeInterval) -> Combo? {
        var state = pads[pad] ?? PadState()
        let combo = Self.match(buttons)
        if let fired = state.fired, Self.involved(fired).isDisjoint(with: buttons) {
            state.fired = nil
        }
        if combo != state.combo {
            state.combo = combo
            state.since = time
        }
        var result: Combo?
        if let combo, state.fired == nil, time - state.since >= Self.hold {
            state.fired = combo
            result = combo
        }
        pads[pad] = state
        return result
    }

    public mutating func disconnected(pad: Int) {
        pads[pad] = nil
    }

    static func match(_ b: PadButtons) -> Combo? {
        let sleep = b.isSuperset(of: [.l1, .r1, .start]) || b.isSuperset(of: [.home, .start])
        let exit = b.isSuperset(of: [.l1, .r1, .select]) || b.isSuperset(of: [.home, .select])
        if sleep == exit { return nil }
        return sleep ? .sleep : .exit
    }

    /// Buttons that can make up a combo; all must be let go before it fires again.
    static func involved(_ combo: Combo) -> PadButtons {
        combo == .sleep ? [.l1, .r1, .start, .home] : [.l1, .r1, .select, .home]
    }
}
