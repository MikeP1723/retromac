// SPDX-License-Identifier: GPL-3.0-or-later

public enum AppVersion {
    /// Matches Support/Info.plist; used when running outside an .app (swift run, tests).
    public static let fallback = "0.1.0"

    public static func current(infoDictionary: [String: Any]?) -> String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? fallback
    }

    /// Built by scripts/bundle.sh without RETROMAC_VERSION: its version is a placeholder, so it never self-updates.
    public static func isDevelopmentBuild(infoDictionary: [String: Any]?) -> Bool {
        infoDictionary?["RetromacDevelopmentBuild"] as? Bool ?? false
    }
}
