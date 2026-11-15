// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Where everything lives. retromac keeps all of its own files, the game library, RetroArch, ES-DE
/// and ES-DE's data under one hidden folder, so the only thing a user sees is retromac.app.
public struct Paths: Sendable {
    public let home: URL
    /// Where RetroArch.app and ES-DE.app are installed; retromac's own `Apps` folder by default.
    public let applications: URL

    public init(home: URL, applications: URL? = nil) {
        self.home = home
        self.applications = applications ?? home.appending(path: "Library/Application Support/retromac/Apps")
    }

    public var root: URL { home.appending(path: "Library/Application Support/retromac") }
    /// Older name for `root`.
    public var retromacRoot: URL { root }
    public var profile: URL { root.appending(path: "profile.json") }
    public var state: URL { root.appending(path: "state.json") }
    public var backups: URL { root.appending(path: "backups") }
    public var defaultLibraryRoot: URL { root.appending(path: "Library") }
    /// The rollback slot: one previous generation per updated component.
    public var previous: URL { root.appending(path: "previous") }
    /// Imported No-Intro/Redump DAT indexes, one JSON file per system.
    public var dats: URL { root.appending(path: "dats") }
    /// Whether a console session is running, so a restarted agent knows not to relaunch ES-DE.
    public var consoleSession: URL { root.appending(path: "console-session.json") }
    public var consoleAgentPlist: URL { home.appending(path: "Library/LaunchAgents/petersoft.retromac.console.plist") }
    /// The manifest the current install was last updated to.
    public var appliedManifest: URL { root.appending(path: "manifest.json") }

    public var retroarchExecutable: URL { applications.appending(path: "RetroArch.app/Contents/MacOS/RetroArch") }
    public var retroarchSupport: URL { home.appending(path: "Library/Application Support/RetroArch") }
    public var retroarchConfig: URL { retroarchSupport.appending(path: "config/retroarch.cfg") }
    public var retroarchCores: URL { retroarchSupport.appending(path: "cores") }
    /// BIOS files; set explicitly in retroarch.cfg, whose default is each game's own folder.
    public var retroarchSystem: URL { retroarchSupport.appending(path: "system") }
    /// RetroArch's own default for saves, states and playlists; retromac moves them out (RetroArchDocuments).
    public var retroarchDocuments: URL { home.appending(path: "Documents/RetroArch") }
    public var globalShaderPreset: URL { retroarchSupport.appending(path: "config/global.slangp") }
    public var retroarchShadersSlang: URL { retroarchSupport.appending(path: "shaders/shaders_slang") }

    public func coreOverride(libraryName: String) -> URL {
        retroarchSupport.appending(path: "config/\(libraryName)/\(libraryName).cfg")
    }

    /// RetroArch reads a core's controller types (input_libretro_device_pN) only from remap files.
    public func coreRemap(libraryName: String) -> URL {
        retroarchSupport.appending(path: "config/remaps/\(libraryName)/\(libraryName).rmp")
    }

    /// Dolphin's user folder on macOS (its default; retromac doesn't move it).
    public var dolphinConfig: URL { home.appending(path: "Library/Application Support/Dolphin/Config") }
    /// PCSX2's data folder on macOS (QtHost.cpp MAC_DATA_DIR); settings in inis/PCSX2.ini.
    public var pcsx2Settings: URL { home.appending(path: "Library/Application Support/PCSX2/inis/PCSX2.ini") }
    /// PS2 BIOS files, apart from RetroArch's own so PCSX2 only scans its own.
    public var ps2Bios: URL { retroarchSystem.appending(path: "pcsx2/bios") }
    /// xemu's own folder (`SDL_GetPrefPath("xemu", "xemu")` is `xemu/xemu` inside it).
    public var xemuSupport: URL { home.appending(path: "Library/Application Support/xemu") }
    /// The emulated Xbox's hard disk; it holds game saves, so it's installed once and never replaced.
    public var xemuHDD: URL { xemuSupport.appending(path: "xbox_hdd.qcow2") }

    public var xemuConfig: URL { xemuSupport.appending(path: "xemu/xemu.toml") }

    /// Where a manifest data asset is installed.
    public func assetTarget(_ asset: AssetEntry) -> URL {
        switch asset.system {
        case .xbox: xemuSupport.appending(path: asset.fileName)
        default: root.appending(path: "assets/\(asset.fileName)")
        }
    }

    /// Passed to ES-DE as `--home`; ES-DE keeps its data in `<esdeHome>/ES-DE`.
    public var esdeHome: URL { root }
    public var esdeRoot: URL { esdeHome.appending(path: "ES-DE") }
    public var esdeSettings: URL { esdeRoot.appending(path: "settings/es_settings.xml") }
    public var esdeCustomSystems: URL { esdeRoot.appending(path: "custom_systems/es_systems.xml") }
    public var esdeFindRules: URL { esdeRoot.appending(path: "custom_systems/es_find_rules.xml") }
}

/// Where Phase 1–3 put things, before everything moved under Application Support.
public struct LegacyPaths: Sendable {
    public let home: URL
    public let applications: URL

    public init(home: URL, applications: URL = URL(filePath: "/Applications")) {
        self.home = home
        self.applications = applications
    }

    public var root: URL { home.appending(path: "retromac") }
    public var esde: URL { home.appending(path: "ES-DE") }
}
