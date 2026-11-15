// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

func iniKeys(_ files: [RenderedFile], _ url: URL) -> [String: [String: String]]? {
    for f in files where f.url == url { if case .iniKeys(let keys) = f.kind { return keys } }
    return nil
}

private let qhd = DisplayProfile(widthPx: 3440, heightPx: 1440, refreshHz: 60, hdr: false, vrr: false, diagonalInches: 34, distanceInches: 30)

@Test func dolphinSettingsForGameCube() throws {
    let library = URL(filePath: "/tmp/h/Mike's \"Games\"")
    let files = try render(profile(qhd, systems: [.gc], library: library))
    let config = Paths(home: URL(filePath: "/tmp/h")).dolphinConfig
    #expect(config.path == "/tmp/h/Library/Application Support/Dolphin/Config")
    let main = try #require(iniKeys(files, config.appending(path: "Dolphin.ini")))
    #expect(main["General"] == ["ISOPaths": "2", "ISOPath0": "/tmp/h/Mike's \"Games\"/gc", "ISOPath1": "/tmp/h/Mike's \"Games\"/wii"])
    #expect(main["Core"] == ["GFXBackend": "Metal"])
    #expect(main["Display"] == ["Fullscreen": "True"])
    #expect(main["Interface"] == ["ConfirmStop": "False"])
    #expect(main["Analytics"] == ["PermissionAsked": "True", "Enabled": "False"])
    #expect(main["AutoUpdate"] == ["UpdateTrack": ""])
    #expect(iniKeys(files, config.appending(path: "GFX.ini")) == ["Settings": ["InternalResolution": "3"]])
    // Dolphin's INI values run unquoted to the end of the line.
    #expect(IniConfig.merge(existing: "", owned: main).contains("ISOPath0 = /tmp/h/Mike's \"Games\"/gc\n"))
}
@Test func noDolphinFilesWithoutGameCubeOrWii() throws {
    #expect(!(try render(profile(systems: [.nes]))).contains { $0.url.path.contains("/Dolphin/") })
    #expect((try render(profile(systems: [.wii]))).contains { $0.url.lastPathComponent == "Dolphin.ini" })
}
@Test func userDolphinSettingsSurviveReapply() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    let p = profile(systems: [.gc], library: home.appending(path: "Library"))
    let files = ProfileRenderer.render(p, manifest: .fixture(), rules: try DisplayRules.bundled(), paths: paths, chip: "Apple M4 Pro")
    let applier = Applier(paths: paths, apps: [], isRunning: { _ in false })
    _ = try applier.apply(files)
    let ini = paths.dolphinConfig.appending(path: "Dolphin.ini")
    let edited = try read(ini).replacingOccurrences(of: "ISOPath0 = ", with: "ISOPath0 = /elsewhere") + "\n[Display]\nRenderToMain = True\n"
    try edited.write(to: ini, atomically: true, encoding: .utf8)
    _ = try applier.apply(files)
    let after = try read(ini)
    #expect(after.contains("RenderToMain = True"))
    #expect(after.contains("ISOPath0 = \(home.appending(path: "Library/gc").path)\n"))
}

@Test func anyPadExpressionCoversEveryKnownSdlName() {
    let expr = DolphinPads.anyPad("Button S")
    #expect(expr.hasPrefix("`SDL/0/Nintendo Switch Pro Controller:Button S` | "))
    for name in ["Xbox Series X Controller", "Xbox One Wireless Controller", "DualSense Wireless Controller", "PS4 Controller"] {
        #expect(expr.contains("`SDL/0/\(name):Button S`"))
    }
    #expect(expr.components(separatedBy: " | ").count == DolphinPads.sdlNames.count)
}
@Test func gamecubePadMapping() throws {
    let config = Paths(home: URL(filePath: "/tmp/h")).dolphinConfig
    let pad = try #require(iniKeys(try render(profile(systems: [.gc])), config.appending(path: "GCPadNew.ini"))?["GCPad1"])
    #expect(pad["Device"] == "SDL/0/Nintendo Switch Pro Controller")
    let expected = ["Buttons/A": "Button S", "Buttons/B": "Button W", "Buttons/X": "Button E", "Buttons/Y": "Button N",
                    "Buttons/Z": "Shoulder R", "Buttons/Start": "Start",
                    "Main Stick/Up": "Left Y-", "Main Stick/Down": "Left Y+", "Main Stick/Left": "Left X-", "Main Stick/Right": "Left X+",
                    "C-Stick/Up": "Right Y-", "C-Stick/Down": "Right Y+", "C-Stick/Left": "Right X-", "C-Stick/Right": "Right X+",
                    "Triggers/L": "Trigger L", "Triggers/R": "Trigger R", "Triggers/L-Analog": "Trigger L", "Triggers/R-Analog": "Trigger R",
                    "D-Pad/Up": "Pad N", "D-Pad/Down": "Pad S", "D-Pad/Left": "Pad W", "D-Pad/Right": "Pad E"]
    for (key, input) in expected { #expect(pad[key] == DolphinPads.anyPad(input), "\(key)") }
    #expect(pad.count == expected.count + 1)
}
@Test func wiimoteWithNunchukMapping() throws {
    let config = Paths(home: URL(filePath: "/tmp/h")).dolphinConfig
    let mote = try #require(iniKeys(try render(profile(systems: [.wii])), config.appending(path: "WiimoteNew.ini"))?["Wiimote1"])
    #expect(mote["Source"] == "1" && mote["Extension"] == "Nunchuk")
    let expected = ["Buttons/A": "Button S", "Buttons/B": "Trigger R", "Buttons/1": "Button W", "Buttons/2": "Button N",
                    "Buttons/-": "Back", "Buttons/+": "Start", "Buttons/Home": "Guide",
                    "D-Pad/Up": "Pad N", "D-Pad/Down": "Pad S", "D-Pad/Left": "Pad W", "D-Pad/Right": "Pad E",
                    "IR/Up": "Right Y-", "IR/Down": "Right Y+", "IR/Left": "Right X-", "IR/Right": "Right X+",
                    "Nunchuk/Buttons/C": "Shoulder L", "Nunchuk/Buttons/Z": "Trigger L",
                    "Nunchuk/Stick/Up": "Left Y-", "Nunchuk/Stick/Down": "Left Y+", "Nunchuk/Stick/Left": "Left X-", "Nunchuk/Stick/Right": "Left X+",
                    "Shake/X": "Button E", "Shake/Y": "Button E", "Shake/Z": "Button E"]
    for (key, input) in expected { #expect(mote[key] == DolphinPads.anyPad(input), "\(key)") }
}
@Test func exitHotkeyIsSelectStart() throws {
    let config = Paths(home: URL(filePath: "/tmp/h")).dolphinConfig
    let keys = try #require(iniKeys(try render(profile(systems: [.gc])), config.appending(path: "Hotkeys.ini"))?["Hotkeys"])
    let stop = try #require(keys["General/Stop"])
    #expect(stop.hasPrefix("@(`SDL/0/Nintendo Switch Pro Controller:Back`+`SDL/0/Nintendo Switch Pro Controller:Start`) | @("))
    #expect(stop.components(separatedBy: " | ").count == DolphinPads.sdlNames.count)
}
