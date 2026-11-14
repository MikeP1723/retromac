// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// How retromac starts ES-DE: with its data kept under retromac's own folder.
public enum ESDELauncher {
    public static func arguments(paths: Paths) -> [String] {
        ["--home", paths.esdeHome.path]
    }
}
