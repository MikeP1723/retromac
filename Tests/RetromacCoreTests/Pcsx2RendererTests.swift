// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

/// 4 MiB with a ROM directory whose first entry is RESET at 0x2700, like a real dump; never a real BIOS.
func syntheticPs2Bios(_ url: URL, size: Int = 4_194_304, reset: Bool = true) throws {
    var data = Data(count: size)
    if reset { data.replaceSubrange(0x2700..<0x2706, with: Array("RESET".utf8) + [0]) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url)
}

private let qhd = DisplayProfile(widthPx: 3440, heightPx: 1440, refreshHz: 60, hdr: false, vrr: false, diagonalInches: 34, distanceInches: 30)

private func pcsx2(_ files: [RenderedFile], _ paths: Paths) -> [String: [String: String]]? {
    iniKeys(files, paths.pcsx2Settings)
}

@Test func pcsx2SettingsForPs2() throws {
    let paths = Paths(home: URL(filePath: "/tmp/h"))
    #expect(paths.pcsx2Settings.path == "/tmp/h/Library/Application Support/PCSX2/inis/PCSX2.ini")
    #expect(paths.ps2Bios.path == "/tmp/h/Library/Application Support/RetroArch/system/pcsx2/bios")
    let ini = try #require(pcsx2(try render(profile(qhd, systems: [.ps2], library: URL(filePath: "/tmp/h/Mike's \"Games\""))), paths))
    #expect(ini["GameList"] == ["RecursivePaths": "/tmp/h/Mike's \"Games\"/ps2"])
    #expect(ini["Folders"] == ["Bios": paths.ps2Bios.path])
    #expect(ini["Filenames"] == nil)
    #expect(ini["EmuCore/GS"] == ["Renderer": "17", "upscale_multiplier": "4"])
    let pad = try #require(ini["Pad1"])
    let expected = ["Type": "DualShock2",
                    "Cross": "SDL-0/FaceSouth", "Circle": "SDL-0/FaceEast", "Square": "SDL-0/FaceWest", "Triangle": "SDL-0/FaceNorth",
                    "Select": "SDL-0/Back", "Start": "SDL-0/Start", "L1": "SDL-0/LeftShoulder", "R1": "SDL-0/RightShoulder",
                    "L2": "SDL-0/+LeftTrigger", "R2": "SDL-0/+RightTrigger", "L3": "SDL-0/LeftStick", "R3": "SDL-0/RightStick",
                    "Up": "SDL-0/DPadUp", "Down": "SDL-0/DPadDown", "Left": "SDL-0/DPadLeft", "Right": "SDL-0/DPadRight",
                    "LUp": "SDL-0/-LeftY", "LDown": "SDL-0/+LeftY", "LLeft": "SDL-0/-LeftX", "LRight": "SDL-0/+LeftX",
                    "RUp": "SDL-0/-RightY", "RDown": "SDL-0/+RightY", "RLeft": "SDL-0/-RightX", "RRight": "SDL-0/+RightX"]
    #expect(pad == expected)
    #expect(ini["Hotkeys"] == ["ShutdownVM": "SDL-0/Back & SDL-0/Start"])
}
@Test func pcsx2NeverShowsItsWizardOrQuitPrompt() throws {
    let ui = try #require(pcsx2(try render(profile(systems: [.ps2])), Paths(home: URL(filePath: "/tmp/h")))?["UI"])
    #expect(ui == ["SetupWizardIncomplete": "false", "StartFullscreen": "true", "ConfirmShutdown": "false"])
}
@Test func biosFileNameComesFromTheBiosFolder() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    func filenames() -> [String: String]? {
        pcsx2(ProfileRenderer.render(profile(systems: [.ps2]), manifest: .fixture(), rules: try! .bundled(), paths: paths, chip: "Apple M4 Pro"), paths)?["Filenames"]
    }
    #expect(filenames() == nil)
    try syntheticPs2Bios(paths.ps2Bios.appending(path: "notes.bin"), reset: false)
    try syntheticPs2Bios(paths.ps2Bios.appending(path: "SCPH-70012.bin"))
    try syntheticPs2Bios(paths.ps2Bios.appending(path: "SCPH-39001.bin"))
    #expect(filenames() == ["BIOS": "SCPH-39001.bin"])
}
@Test func noPcsx2FileWithoutPs2() throws {
    #expect(!(try render(profile(systems: [.gc]))).contains { $0.url.lastPathComponent == "PCSX2.ini" })
}
@Test func userPcsx2SettingsSurviveReapply() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    let files = ProfileRenderer.render(profile(systems: [.ps2], library: home.appending(path: "Library")), manifest: .fixture(),
                                       rules: try DisplayRules.bundled(), paths: paths, chip: "Apple M4 Pro")
    let applier = Applier(paths: paths, apps: [], isRunning: { _ in false })
    _ = try applier.apply(files)
    try (try read(paths.pcsx2Settings) + "\n[EmuCore/Speedhacks]\nvuThread = true\n").write(to: paths.pcsx2Settings, atomically: true, encoding: .utf8)
    _ = try applier.apply(files)
    #expect(try read(paths.pcsx2Settings).contains("[EmuCore/Speedhacks]\nvuThread = true"))
}
@Test func ps2BiosNeedsTheResetEntry() throws {
    let dir = try makeTempDir()
    try syntheticPs2Bios(dir.appending(path: "a.bin"))
    try syntheticPs2Bios(dir.appending(path: "b.bin"), reset: false)
    try syntheticPs2Bios(dir.appending(path: "c.bin"), size: 524_288)
    #expect(Ps2Bios.isBios(dir.appending(path: "a.bin")))
    #expect(!Ps2Bios.isBios(dir.appending(path: "b.bin")))
    #expect(!Ps2Bios.isBios(dir.appending(path: "c.bin")))
}
