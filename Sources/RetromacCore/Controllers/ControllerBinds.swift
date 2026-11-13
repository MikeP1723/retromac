// SPDX-License-Identifier: GPL-3.0-or-later

/// Face-button and hotkey binds written into retroarch.cfg.
///
/// RetroArch's mfi driver registers every pad as "mFi Controller", so per-device autoconfig
/// files would collide; its bundled MFi_Controller.cfg already maps by position. Player binds in
/// retroarch.cfg override that profile and survive RetroArch's first-launch asset extraction.
public enum ControllerBinds {
    static let players = 1...4

    public static func keys(for controllers: [ControllerProfile], policy: FacePolicy) -> [String: String] {
        // Only Xbox pads print different letters at the SNES positions. Which pad lands on which
        // player isn't knowable offline, so the label layout applies only when every pad is Xbox.
        let byLabel = policy == .label && !controllers.isEmpty && controllers.allSatisfy { $0.kind == .xbox }
        let face: [(String, MFiButton)] = byLabel
            ? [("a", .south), ("b", .east), ("x", .west), ("y", .north)]
            : [("a", .east), ("b", .south), ("x", .north), ("y", .west)]

        var keys = [
            "input_enable_hotkey_btn": "\(MFiButton.select.rawValue)",
            "input_exit_emulator_btn": "\(MFiButton.start.rawValue)",
        ]
        for n in players {
            for (name, button) in face {
                keys["input_player\(n)_\(name)_btn"] = "\(button.rawValue)"
            }
        }
        return keys
    }
}
