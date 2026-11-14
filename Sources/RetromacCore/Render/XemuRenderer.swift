// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// xemu (original Xbox) settings. Key names from xemu's config_spec.yml. Input isn't written:
/// `input.auto_bind` (on by default) binds the first controller to port 1.
public enum XemuRenderer {
    public static func files(_ p: Profile, rules: DisplayRules, paths: Paths, chip: String) -> [RenderedFile] {
        guard p.systems.contains(.xbox) else { return [] }
        var keys: [String: [String: TomlValue]] = [
            "general": [
                "show_welcome": .bool(false),
                "skip_boot_anim": .bool(true),
                "games_dir": .string(p.libraryRoot.appending(path: SystemID.xbox.rawValue).path),
            ],
            "display.window": ["fullscreen_on_startup": .bool(true)],
            // BIOS files live with the others in RetroArch's system folder, where the importer files them.
            "sys.files": [
                "bootrom_path": .string(paths.retroarchSystem.appending(path: "mcpx_1.0.bin").path),
                "flashrom_path": .string(paths.retroarchSystem.appending(path: "Complex_4627.bin").path),
                "hdd_path": .string(paths.xemuHDD.path),
            ],
            // display.renderer stays xemu's default (OpenGL): Vulkan here is MoltenVK.
        ]
        if let scale = rules.internalScale(for: .xbox, display: p.display, chip: chip) {
            keys["display.quality"] = ["surface_scale": .int(scale)]
        }
        return [RenderedFile(url: paths.xemuConfig, kind: .tomlKeys(keys))]
    }
}
