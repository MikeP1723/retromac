// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// PCSX2 (PlayStation 2) settings. Key names from PCSX2 v2.8.2 (Pcsx2Config.cpp, QtHost.cpp, GameList.cpp).
/// Pads bind by SDL player index (`SDL-0/…`, SDLInputSource.cpp), so any pad works with no name table.
public enum Pcsx2Renderer {
    static let pad: [String: String] = [
        "Type": "DualShock2",
        "Cross": "SDL-0/FaceSouth", "Circle": "SDL-0/FaceEast", "Square": "SDL-0/FaceWest", "Triangle": "SDL-0/FaceNorth",
        "Select": "SDL-0/Back", "Start": "SDL-0/Start", "L1": "SDL-0/LeftShoulder", "R1": "SDL-0/RightShoulder",
        "L2": "SDL-0/+LeftTrigger", "R2": "SDL-0/+RightTrigger", "L3": "SDL-0/LeftStick", "R3": "SDL-0/RightStick",
        "Up": "SDL-0/DPadUp", "Down": "SDL-0/DPadDown", "Left": "SDL-0/DPadLeft", "Right": "SDL-0/DPadRight",
        "LUp": "SDL-0/-LeftY", "LDown": "SDL-0/+LeftY", "LLeft": "SDL-0/-LeftX", "LRight": "SDL-0/+LeftX",
        "RUp": "SDL-0/-RightY", "RDown": "SDL-0/+RightY", "RLeft": "SDL-0/-RightX", "RRight": "SDL-0/+RightX",
    ]

    public static func files(_ p: Profile, rules: DisplayRules, paths: Paths, chip: String) -> [RenderedFile] {
        guard p.systems.contains(.ps2) else { return [] }
        var keys: [String: [String: String]] = [
            // No first-run wizard and no "are you sure?" in front of a controller-only user.
            "UI": ["SetupWizardIncomplete": "false", "StartFullscreen": "true", "ConfirmShutdown": "false"],
            "GameList": ["RecursivePaths": p.libraryRoot.appending(path: SystemID.ps2.rawValue).path],
            "Folders": ["Bios": paths.ps2Bios.path],
            // Metal (GSRendererType 17): not Vulkan, which on macOS is MoltenVK.
            "EmuCore/GS": ["Renderer": "17"],
            "Pad1": pad,
            // Select+Start, as in RetroArch and Dolphin; with -batch, PCSX2 then exits to ES-DE.
            "Hotkeys": ["ShutdownVM": "SDL-0/Back & SDL-0/Start"],
        ]
        if let bios = Ps2Bios.first(in: paths.ps2Bios) { keys["Filenames"] = ["BIOS": bios] }
        if let scale = rules.internalScale(for: .ps2, display: p.display, chip: chip) {
            keys["EmuCore/GS"]?["upscale_multiplier"] = String(scale)
        }
        return [RenderedFile(url: paths.pcsx2Settings, kind: .iniKeys(keys))]
    }
}
