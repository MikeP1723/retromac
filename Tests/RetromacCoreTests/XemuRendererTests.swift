// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

private func tomlKeys(_ files: [RenderedFile], _ url: URL) -> [String: [String: TomlValue]]? {
    for f in files where f.url == url { if case .tomlKeys(let keys) = f.kind { return keys } }
    return nil
}

@Test func xemuSettingsForXbox() throws {
    let paths = Paths(home: URL(filePath: "/tmp/h"))
    #expect(paths.xemuConfig.path == "/tmp/h/Library/Application Support/xemu/xemu/xemu.toml")
    let qhd = DisplayProfile(widthPx: 3440, heightPx: 1440, refreshHz: 60, hdr: false, vrr: false, diagonalInches: 34, distanceInches: 30)
    let keys = try #require(tomlKeys(try render(profile(qhd, systems: [.xbox], library: URL(filePath: "/tmp/h/Lib"))), paths.xemuConfig))
    #expect(keys["general"] == ["show_welcome": .bool(false), "skip_boot_anim": .bool(true), "games_dir": .string("/tmp/h/Lib/xbox")])
    #expect(keys["display.window"] == ["fullscreen_on_startup": .bool(true)])
    #expect(keys["display.quality"] == ["surface_scale": .int(3)])
    #expect(keys["sys.files"] == [
        "bootrom_path": .string("/tmp/h/Library/Application Support/RetroArch/system/mcpx_1.0.bin"),
        "flashrom_path": .string("/tmp/h/Library/Application Support/RetroArch/system/Complex_4627.bin"),
        "hdd_path": .string("/tmp/h/Library/Application Support/xemu/xbox_hdd.qcow2"),
    ])
    #expect(keys["display"] == nil)  // renderer stays xemu's default (OpenGL), not MoltenVK
}
@Test func noXemuFileWithoutXbox() throws {
    #expect(!(try render(profile(systems: [.gc]))).contains { $0.url.lastPathComponent == "xemu.toml" })
}
@Test func userXemuSettingsSurviveReapply() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    let files = ProfileRenderer.render(profile(systems: [.xbox], library: home.appending(path: "Library")), manifest: .fixture(),
                                       rules: try DisplayRules.bundled(), paths: paths, chip: "Apple M4 Pro")
    let applier = Applier(paths: paths, apps: [], isRunning: { _ in false })
    _ = try applier.apply(files)
    try (try read(paths.xemuConfig) + "\n[audio]\nvolume_limit = 0.5\n").write(to: paths.xemuConfig, atomically: true, encoding: .utf8)
    _ = try applier.apply(files)
    #expect(try read(paths.xemuConfig).contains("[audio]\nvolume_limit = 0.5"))
    #expect(try read(paths.xemuConfig).contains("show_welcome = false"))
}
