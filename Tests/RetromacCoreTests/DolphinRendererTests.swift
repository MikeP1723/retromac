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
