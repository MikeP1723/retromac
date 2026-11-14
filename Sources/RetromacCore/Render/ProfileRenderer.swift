// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct RenderedFile: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Keys merged into an existing RetroArch .cfg.
        case retroarchKeys([String: String])
        /// ROMDirectory merged into es_settings.xml.
        case esdeSettings(romDirectory: String)
        /// ES-DE custom systems: these <system> entries replace same-named ones; others are kept.
        case esdeSystems(String)
        /// Keys (section → key → value) merged into an INI file; every other line is kept.
        case iniKeys([String: [String: String]])
        /// A file retromac owns entirely.
        case whole(String)
        case directory
    }

    public var url: URL
    public var kind: Kind

    public init(url: URL, kind: Kind) {
        self.url = url
        self.kind = kind
    }
}

public enum ProfileRenderer {
    static let header = "# Managed by retromac — edits will be overwritten\n"

    public static func render(_ p: Profile, manifest: Manifest, rules: DisplayRules, paths: Paths,
                              chip: String = Chip.brand()) -> [RenderedFile] {
        let preset = rules.shaderPreset(for: p.display, look: p.look)
        var files: [RenderedFile] = []

        var keys = [
            "video_fullscreen": "true",
            "video_refresh_rate": String(format: "%.6f", p.display.refreshHz),
            "vrr_runloop_enable": String(p.display.vrr),
            "video_frame_delay_auto": "true",
            "video_scale_integer": String(p.look != .smooth),
            "video_aspect_ratio_auto": "true",
            "video_shader_enable": String(preset != nil),
            "auto_shaders_enable": "true",
            "input_joypad_driver": "mfi",
            "input_autodetect_enable": "true",
            "system_directory": paths.retroarchSystem.path,
            // RetroArch binds its command port on every interface, so it stays off (and older installs that
            // turned it on for console mode get it turned off).
            "network_cmd_enable": "false",
        ]
        // Console mode pauses a game by hiding RetroArch; pause_nonactive makes that a pause.
        if p.console?.enabled == true { keys["pause_nonactive"] = "true" }
        // RetroArch's defaults are under ~/Documents/RetroArch; keep the user's data with everything else.
        let support = paths.retroarchSupport, builtin = support.appending(path: "playlists/builtin")
        keys["savefile_directory"] = support.appending(path: "saves").path
        keys["savestate_directory"] = support.appending(path: "states").path
        keys["playlist_directory"] = support.appending(path: "playlists").path
        for list in ["favorites", "history", "image_history", "music_history", "video_history"] {
            keys["content_\(list)_path"] = builtin.appending(path: "content_\(list).lpl").path
        }
        keys["log_dir"] = support.appending(path: "logs").path
        keys["recording_output_directory"] = support.appending(path: "records").path
        keys["recording_config_directory"] = support.appending(path: "records_config").path
        keys.merge(ControllerBinds.keys(for: p.controllers, policy: p.facePolicy)) { $1 }
        files.append(RenderedFile(url: paths.retroarchConfig, kind: .retroarchKeys(keys)))

        if let preset {
            let target = paths.retroarchShadersSlang.appending(path: preset.path).path
            files.append(RenderedFile(url: paths.globalShaderPreset, kind: .whole(header + "#reference \"\(target)\"\n")))
        }

        for system in p.systems.intersection(rules.runAheadSystems) {
            guard let core = manifest.core(for: system) else { continue }
            files.append(RenderedFile(url: paths.coreOverride(libraryName: core.libraryName), kind: .retroarchKeys([
                "run_ahead_enabled": "true",
                "run_ahead_frames": "1",
                "run_ahead_secondary_instance": "true",
            ])))
        }

        // DualShock (RETRO_DEVICE_SUBCLASS(RETRO_DEVICE_ANALOG, 1), beetle-psx input.h): analog games need it.
        if p.systems.contains(.psx), let core = manifest.core(for: .psx) {
            files.append(RenderedFile(url: paths.coreRemap(libraryName: core.libraryName), kind: .retroarchKeys([
                "input_libretro_device_p1": "517",
                "input_libretro_device_p2": "517",
            ])))
        }

        files += DolphinRenderer.files(p, rules: rules, paths: paths, chip: chip)

        files.append(RenderedFile(url: paths.esdeSettings, kind: .esdeSettings(romDirectory: p.libraryRoot.path)))
        files.append(RenderedFile(url: paths.esdeFindRules,
                                  kind: .whole(ESDESystems.findRules(paths: paths))))
        files.append(RenderedFile(url: paths.esdeCustomSystems, kind: .esdeSystems(ESDESystems.xml(for: p.systems, manifest: manifest))))

        for system in p.systems {
            files.append(RenderedFile(url: p.libraryRoot.appending(path: system.rawValue), kind: .directory))
        }

        return files.sorted { $0.url.path < $1.url.path }
    }
}
