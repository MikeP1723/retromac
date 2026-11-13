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

public struct DisplayRules: Codable, Equatable, Sendable {
    public var crtTiers: [ShaderTier]
    public var smoothPreset: ShaderPreset
    public var runAheadSystems: Set<SystemID>

    public static func bundled() throws -> DisplayRules {
        guard let url = Resources.url("display_rules", ext: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(DisplayRules.self, from: Data(contentsOf: url))
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
