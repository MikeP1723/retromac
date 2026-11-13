// SPDX-License-Identifier: GPL-3.0-or-later

/// Renders a RetroArch autoconfig profile for the mfi joypad driver.
public enum AutoconfigRenderer {
    public static func render(_ c: ControllerProfile, policy: FacePolicy) -> String {
        // RetroPad A/B/X/Y follow SNES positions; only Xbox pads print different letters there.
        let byLabel = policy == .label && c.kind == .xbox
        let face: [(String, MFiButton)] = byLabel
            ? [("a", .south), ("b", .east), ("x", .west), ("y", .north)]
            : [("a", .east), ("b", .south), ("x", .north), ("y", .west)]
        let fixed: [(String, MFiButton)] = [
            ("select", .select), ("start", .start),
            ("up", .up), ("down", .down), ("left", .left), ("right", .right),
            ("l", .l1), ("r", .r1), ("l2", .l2), ("r2", .r2), ("l3", .l3), ("r3", .r3),
        ]
        var lines = [
            "# Managed by retromac — edits will be overwritten",
            "input_driver = \"mfi\"",
            "input_device = \"\(c.deviceName)\"",
            "input_device_display_name = \"\(c.deviceName)\"",
        ]
        lines += (face + fixed).map { "input_\($0.0)_btn = \"\($0.1.rawValue)\"" }
        lines += [
            "input_enable_hotkey_btn = \"\(MFiButton.select.rawValue)\"",
            "input_exit_emulator_btn = \"\(MFiButton.start.rawValue)\"",
        ]
        for (stick, x, y) in [("l", 0, 1), ("r", 2, 3)] {
            lines += [
                "input_\(stick)_x_plus_axis = \"+\(x)\"", "input_\(stick)_x_minus_axis = \"-\(x)\"",
                "input_\(stick)_y_plus_axis = \"+\(y)\"", "input_\(stick)_y_minus_axis = \"-\(y)\"",
            ]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    public static func fileName(for c: ControllerProfile) -> String {
        c.deviceName.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_") + ".cfg"
    }
}
