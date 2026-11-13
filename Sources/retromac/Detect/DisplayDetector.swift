// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import RetromacCore

enum DisplayDetector {
    /// Size and seating distance can't be detected; callers keep the user's values.
    @MainActor
    static func detect(diagonalInches: Double = 55, distanceInches: Double = 96) -> DisplayProfile {
        guard let screen = NSScreen.main else {
            return DisplayProfile(widthPx: 1920, heightPx: 1080, refreshHz: 60, hdr: false, vrr: false,
                                  diagonalInches: diagonalInches, distanceInches: distanceInches)
        }
        let scale = screen.backingScaleFactor
        return DisplayProfile(
            widthPx: Int(screen.frame.width * scale),
            heightPx: Int(screen.frame.height * scale),
            refreshHz: Double(screen.maximumFramesPerSecond),
            hdr: screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1,
            vrr: screen.minimumRefreshInterval != screen.maximumRefreshInterval,
            diagonalInches: diagonalInches,
            distanceInches: distanceInches)
    }
}
