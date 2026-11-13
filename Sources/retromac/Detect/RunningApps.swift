// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit

enum RunningApps {
    /// Matches by bundle name ("ES-DE.app"): ES-DE's bundle identifier is its version string.
    static func isRunning(_ appName: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.lastPathComponent == appName }
    }
}
