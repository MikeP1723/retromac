// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Dolphin (GameCube and Wii) settings. Key names from Dolphin's MainSettings.cpp and GraphicsSettings.cpp.
public enum DolphinRenderer {
    public static func files(_ p: Profile, rules: DisplayRules, paths: Paths, chip: String) -> [RenderedFile] {
        guard !p.systems.isDisjoint(with: [.gc, .wii]) else { return [] }
        var files = [RenderedFile(url: paths.dolphinConfig.appending(path: "Dolphin.ini"), kind: .iniKeys([
            "General": [
                "ISOPaths": "2",
                "ISOPath0": p.libraryRoot.appending(path: SystemID.gc.rawValue).path,
                "ISOPath1": p.libraryRoot.appending(path: SystemID.wii.rawValue).path,
            ],
            // Not Vulkan: on macOS that's MoltenVK, whose output froze Beetle PSX HW in Phase 3b.
            "Core": ["GFXBackend": "Metal"],
            "Display": ["Fullscreen": "True"],
            "Interface": ["ConfirmStop": "False"],
            // No first-run analytics prompt in front of a controller-only user.
            "Analytics": ["PermissionAsked": "True", "Enabled": "False"],
            // retromac owns updates.
            "AutoUpdate": ["UpdateTrack": ""],
        ]))]
        if let scale = rules.internalScale(for: .gc, display: p.display, chip: chip) {
            files.append(RenderedFile(url: paths.dolphinConfig.appending(path: "GFX.ini"),
                                      kind: .iniKeys(["Settings": ["InternalResolution": String(scale)]])))
        }
        return files
    }
}
