// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum Look: String, Codable, CaseIterable, Sendable {
    case crisp, crt, smooth
}

public enum FacePolicy: String, Codable, CaseIterable, Sendable {
    case position, label
}

public enum SleepBehavior: String, Codable, Sendable {
    /// Screen off, Mac awake; any controller button brings it back.
    case standby
    /// Real sleep; only the power button or a keyboard wakes it.
    case trueSleep
}

/// Console mode: an opt-in setup for a Mac dedicated to the TV.
public struct ConsoleSettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var sleep: SleepBehavior

    public init(enabled: Bool, sleep: SleepBehavior) {
        self.enabled = enabled
        self.sleep = sleep
    }

    public static let `default` = ConsoleSettings(enabled: false, sleep: .standby)
}

public struct DisplayProfile: Codable, Equatable, Sendable {
    public var widthPx: Int
    public var heightPx: Int
    public var refreshHz: Double
    public var hdr: Bool
    public var vrr: Bool
    public var diagonalInches: Double
    public var distanceInches: Double

    public init(widthPx: Int, heightPx: Int, refreshHz: Double, hdr: Bool, vrr: Bool,
                diagonalInches: Double, distanceInches: Double) {
        self.widthPx = widthPx; self.heightPx = heightPx; self.refreshHz = refreshHz
        self.hdr = hdr; self.vrr = vrr
        self.diagonalInches = diagonalInches; self.distanceInches = distanceInches
    }
}

/// Everything the wizard asks or detects; the single source of truth for rendering.
public struct Profile: Codable, Equatable, Sendable {
    public var display: DisplayProfile
    public var look: Look
    public var systems: Set<SystemID>
    public var controllers: [ControllerProfile]
    public var facePolicy: FacePolicy
    public var libraryRoot: URL
    /// nil (or disabled) means console mode is off; profiles from before it existed decode as nil.
    public var console: ConsoleSettings?

    public init(display: DisplayProfile, look: Look, systems: Set<SystemID>,
                controllers: [ControllerProfile], facePolicy: FacePolicy, libraryRoot: URL) {
        self.display = display; self.look = look; self.systems = systems
        self.controllers = controllers; self.facePolicy = facePolicy; self.libraryRoot = libraryRoot
    }

    public static func load(from url: URL) throws -> Profile {
        try JSONDecoder().decode(Profile.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
