// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct ShaderPreset: Codable, Equatable, Sendable {
    /// Relative to RetroArch's `shaders_slang/` directory.
    public var path: String
    public var license: String
}

public struct ShaderTier: Codable, Equatable, Sendable {
    public var minHeightPx: Int
    public var maxPPD: Double?
    public var preset: ShaderPreset
}

/// A 3D-era system's internal resolution: whole multiples of its native height, up to a cap.
public struct ScaleRule: Codable, Equatable, Sendable {
    public var nativeHeight: Int
    public var maxScale: Int
}

public struct DisplayRules: Codable, Equatable, Sendable {
    public var crtTiers: [ShaderTier]
    public var smoothPreset: ShaderPreset
    public var runAheadSystems: Set<SystemID>
    /// Keyed by SystemID raw value.
    public var internalScale: [String: ScaleRule]
    /// Base chips (exact brand strings, not Pro/Max/Ultra) are capped at `baseChipMaxScale`.
    public var baseChips: [String]
    public var baseChipMaxScale: Int

    public static func bundled() throws -> DisplayRules {
        guard let url = Resources.url("display_rules", ext: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(DisplayRules.self, from: Data(contentsOf: url))
    }

    /// Enough to fill the display's height, capped per system and on base chips; nil for systems without a rule.
    public func internalScale(for system: SystemID, display: DisplayProfile, chip: String) -> Int? {
        guard let rule = internalScale[system.rawValue] else { return nil }
        let wanted = max(1, Int((Double(display.heightPx) / Double(rule.nativeHeight)).rounded(.up)))
        let cap = baseChips.contains(chip) ? min(rule.maxScale, baseChipMaxScale) : rule.maxScale
        return min(wanted, cap)
    }

    public func shaderPreset(for display: DisplayProfile, look: Look) -> ShaderPreset? {
        switch look {
        case .crisp:
            return nil
        case .smooth:
            return smoothPreset
        case .crt:
            let ppd = Optics.pixelsPerDegree(display)
            return crtTiers.first { tier in
                display.heightPx >= tier.minHeightPx && (tier.maxPPD.map { ppd <= $0 } ?? true)
            }?.preset
        }
    }
}
