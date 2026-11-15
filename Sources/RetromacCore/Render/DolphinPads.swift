// SPDX-License-Identifier: GPL-3.0-or-later

/// Dolphin controller mappings that work with whichever common pad is connected, with nothing to set up.
/// Dolphin binds by SDL device name, so every input is an OR across the names SDL gives these pads.
/// Input names are Dolphin's positional SDL names (SDLGamepad.h).
public enum DolphinPads {
    /// SDL's names at the SDL commit Dolphin 2609 builds with (f87239e7): HIDAPI drivers for Switch Pro
    /// and PlayStation, the GameController (MFi) driver for Bluetooth Xbox pads. Index 0: port 1 is the
    /// first pad.
    static let sdlNames = [
        "Nintendo Switch Pro Controller",
        "Xbox Series X Controller", "Xbox One Wireless Controller", "Xbox One S Controller", "Xbox One Elite 2 Controller",
        "DualSense Wireless Controller", "DualSense Edge Wireless Controller", "PS4 Controller",
    ]

    static func qualified(_ name: String, _ input: String) -> String { "`SDL/0/\(name):\(input)`" }

    /// `input` on any known pad.
    static func anyPad(_ input: String) -> String {
        sdlNames.map { qualified($0, input) }.joined(separator: " | ")
    }

    /// `a` and `b` held together on the same pad.
    static func anyPadCombo(_ a: String, _ b: String) -> String {
        sdlNames.map { "@(\(qualified($0, a))+\(qualified($0, b)))" }.joined(separator: " | ")
    }

    static let device = "SDL/0/\(sdlNames[0])"

    static let gameCube: [String: String] = [
        "Buttons/A": "Button S", "Buttons/B": "Button W", "Buttons/X": "Button E", "Buttons/Y": "Button N",
        "Buttons/Z": "Shoulder R", "Buttons/Start": "Start",
        "Main Stick/Up": "Left Y-", "Main Stick/Down": "Left Y+", "Main Stick/Left": "Left X-", "Main Stick/Right": "Left X+",
        "C-Stick/Up": "Right Y-", "C-Stick/Down": "Right Y+", "C-Stick/Left": "Right X-", "C-Stick/Right": "Right X+",
        "Triggers/L": "Trigger L", "Triggers/R": "Trigger R", "Triggers/L-Analog": "Trigger L", "Triggers/R-Analog": "Trigger R",
        "D-Pad/Up": "Pad N", "D-Pad/Down": "Pad S", "D-Pad/Left": "Pad W", "D-Pad/Right": "Pad E",
    ]

    /// An emulated Wiimote with a Nunchuk: pointer on the right stick, shake on the right face button.
    static let wiimote: [String: String] = [
        "Buttons/A": "Button S", "Buttons/B": "Trigger R", "Buttons/1": "Button W", "Buttons/2": "Button N",
        "Buttons/-": "Back", "Buttons/+": "Start", "Buttons/Home": "Guide",
        "D-Pad/Up": "Pad N", "D-Pad/Down": "Pad S", "D-Pad/Left": "Pad W", "D-Pad/Right": "Pad E",
        "IR/Up": "Right Y-", "IR/Down": "Right Y+", "IR/Left": "Right X-", "IR/Right": "Right X+",
        "Nunchuk/Buttons/C": "Shoulder L", "Nunchuk/Buttons/Z": "Trigger L",
        "Nunchuk/Stick/Up": "Left Y-", "Nunchuk/Stick/Down": "Left Y+", "Nunchuk/Stick/Left": "Left X-", "Nunchuk/Stick/Right": "Left X+",
        "Shake/X": "Button E", "Shake/Y": "Button E", "Shake/Z": "Button E",
    ]
}
