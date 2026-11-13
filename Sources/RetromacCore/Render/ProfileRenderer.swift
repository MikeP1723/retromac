// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct RenderedFile: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Keys merged into an existing RetroArch .cfg.
        case retroarchKeys([String: String])
        /// ROMDirectory merged into es_settings.xml.
        case esdeSettings(romDirectory: String)
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

    public static func render(_ p: Profile, manifest: Manifest, rules: DisplayRules, paths: Paths) -> [RenderedFile] {
        let preset = rules.shaderPreset(for: p.display, look: p.look)
        var files: [RenderedFile] = []

        files.append(RenderedFile(url: paths.retroarchConfig, kind: .retroarchKeys([
            "video_fullscreen": "true",
            "video_refresh_rate": String(format: "%.6f", p.display.refreshHz),
            "vrr_runloop_enable": String(p.display.vrr),
            "video_frame_delay_auto": "true",
            "video_scale_integer": String(p.look != .smooth),
            "video_aspect_ratio_auto": "true",
            "video_shader_enable": String(preset != nil),
            "input_joypad_driver": "mfi",
            "input_autodetect_enable": "true",
        ])))

        if let preset {
            let target = paths.retroarchShadersSlang.appending(path: preset.path).path
            files.append(RenderedFile(url: paths.globalShaderPreset, kind: .whole(header + "#reference \"\(target)\"\n")))
        }

        for system in p.systems.intersection(rules.runAheadSystems) {
            guard let core = manifest.core(for: system) else { continue }
            let body = "run_ahead_enabled = \"true\"\nrun_ahead_frames = \"1\"\nrun_ahead_secondary_instance = \"true\"\n"
            files.append(RenderedFile(url: paths.coreOverride(libraryName: core.libraryName), kind: .whole(header + body)))
        }

        for controller in p.controllers {
            files.append(RenderedFile(
                url: paths.retroarchAutoconfigMFi.appending(path: AutoconfigRenderer.fileName(for: controller)),
                kind: .whole(AutoconfigRenderer.render(controller, policy: p.facePolicy))))
        }

        files.append(RenderedFile(url: paths.esdeSettings, kind: .esdeSettings(romDirectory: p.libraryRoot.path)))
        files.append(RenderedFile(url: paths.esdeCustomSystems, kind: .whole(ESDESystems.xml(for: p.systems, manifest: manifest))))

        for system in p.systems {
            files.append(RenderedFile(url: p.libraryRoot.appending(path: system.rawValue), kind: .directory))
        }

        return files.sorted { $0.url.path < $1.url.path }
    }
}
