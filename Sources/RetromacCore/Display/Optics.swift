// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum Optics {
    /// Horizontal pixels per degree of visual angle at the seating distance.
    public static func pixelsPerDegree(_ d: DisplayProfile) -> Double {
        let aspect = Double(d.widthPx) / Double(d.heightPx)
        let width = d.diagonalInches * aspect / (aspect * aspect + 1).squareRoot()
        let fov = 2 * atan(width / 2 / d.distanceInches) * 180 / .pi
        return Double(d.widthPx) / fov
    }
}
