// SPDX-License-Identifier: GPL-3.0-or-later

public enum AppVersion {
    /// Matches Support/Info.plist; used when running outside an .app (swift run, tests).
    public static let fallback = "0.1.0"

    public static func current(infoDictionary: [String: Any]?) -> String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? fallback
    }
}
