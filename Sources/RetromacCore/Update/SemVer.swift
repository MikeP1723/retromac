// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum SemVer {
    /// Numeric dotted comparison; a leading "v" is ignored and missing or non-numeric parts count as 0.
    public static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l < r ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    static func parts(_ s: String) -> [Int] {
        let trimmed = s.hasPrefix("v") ? String(s.dropFirst()) : s
        return trimmed.split(separator: ".").map { Int($0) ?? 0 }
    }
}
