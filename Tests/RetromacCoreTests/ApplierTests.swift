// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

let bundleIDs = ["com.libretro.dist.RetroArch", "org.es-de.frontend"]

func renderInto(_ home: URL) throws -> [RenderedFile] {
    ProfileRenderer.render(profile(library: home.appending(path: "retromac/Library")), manifest: .fixture(),
                           rules: try DisplayRules.bundled(), paths: Paths(home: home))
}

@Test func applyRefusesWhileAppRunning() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    try write("x", to: paths.retroarchConfig)
    let applier = Applier(paths: paths, bundleIDs: bundleIDs, isRunning: { $0 == "org.es-de.frontend" })
    #expect(throws: ApplyError.appRunning("org.es-de.frontend")) { try applier.apply(try renderInto(home)) }
    #expect(try read(paths.retroarchConfig) == "x")
    #expect(!FileManager.default.fileExists(atPath: paths.backups.path))
}
@Test func applyBacksUpThenWrites() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    try write("menu_driver = \"ozone\"\n", to: paths.retroarchConfig)
    let report = try Applier(paths: paths, bundleIDs: bundleIDs, isRunning: { _ in false }).apply(try renderInto(home))
    let cfg = try read(paths.retroarchConfig)
    #expect(cfg.hasPrefix("menu_driver = \"ozone\"\n"))
    #expect(cfg.contains("video_fullscreen = \"true\""))
    let backup = try #require(report.backup)
    #expect(try read(backup.appending(path: "Library/Application Support/RetroArch/config/retroarch.cfg")) == "menu_driver = \"ozone\"\n")
    #expect(FileManager.default.fileExists(atPath: home.appending(path: "retromac/Library/nes").path))
    #expect(try read(paths.esdeSettings).contains("name=\"ROMDirectory\""))
}
@Test func reapplyIsNoOp() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    let applier = Applier(paths: paths, bundleIDs: bundleIDs, isRunning: { _ in false })
    let files = try renderInto(home)
    _ = try applier.apply(files)
    let second = try applier.apply(files)
    #expect(second.written.isEmpty)
    #expect(second.backup == nil)
    #expect(second.unchanged.count == files.count)
}
