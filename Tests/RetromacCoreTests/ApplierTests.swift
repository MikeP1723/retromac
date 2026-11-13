// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

let appNames = ["RetroArch.app", "ES-DE.app"]

func renderInto(_ home: URL) throws -> [RenderedFile] {
    ProfileRenderer.render(profile(library: home.appending(path: "retromac/Library")), manifest: .fixture(),
                           rules: try DisplayRules.bundled(), paths: Paths(home: home))
}

@Test func applyRefusesWhileAppRunning() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    try write("x", to: paths.retroarchConfig)
    let applier = Applier(paths: paths, apps: appNames, isRunning: { $0 == "ES-DE.app" })
    #expect(throws: ApplyError.appRunning("ES-DE.app")) { try applier.apply(try renderInto(home)) }
    #expect(try read(paths.retroarchConfig) == "x")
    #expect(!FileManager.default.fileExists(atPath: paths.backups.path))
}
@Test func applyBacksUpThenWrites() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    try write("menu_driver = \"ozone\"\n", to: paths.retroarchConfig)
    let report = try Applier(paths: paths, apps: appNames, isRunning: { _ in false }).apply(try renderInto(home))
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
    let applier = Applier(paths: paths, apps: appNames, isRunning: { _ in false })
    let files = try renderInto(home)
    _ = try applier.apply(files)
    let second = try applier.apply(files)
    #expect(second.written.isEmpty)
    #expect(second.backup == nil)
    #expect(second.unchanged.count == files.count)
}
@Test func unreadableConfigFailsInsteadOfBeingReplaced() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    let bytes = Data("menu_driver = \"ozone\"\n".utf8) + Data([0xFF, 0xFE, 0x0A])
    try FileManager.default.createDirectory(at: paths.retroarchConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bytes.write(to: paths.retroarchConfig)
    #expect(throws: (any Error).self) {
        try Applier(paths: paths, apps: appNames, isRunning: { _ in false }).apply(try renderInto(home))
    }
    #expect(try Data(contentsOf: paths.retroarchConfig) == bytes)
}
@Test func restoreUndoesFirstApplyOnCleanMachine() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    let report = try Applier(paths: paths, apps: appNames, isRunning: { _ in false }).apply(try renderInto(home))
    let backup = try #require(report.backup)
    try BackupStore(root: paths.backups, home: home).restore(backup)
    #expect(!FileManager.default.fileExists(atPath: paths.retroarchConfig.path))
    #expect(!FileManager.default.fileExists(atPath: paths.globalShaderPreset.path))
    #expect(!FileManager.default.fileExists(atPath: paths.esdeCustomSystems.path))
}
@Test func restoreKeepsPreexistingFilesAndRemovesCreatedOnes() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    try write("menu_driver = \"ozone\"\n", to: paths.retroarchConfig)
    let report = try Applier(paths: paths, apps: appNames, isRunning: { _ in false }).apply(try renderInto(home))
    try BackupStore(root: paths.backups, home: home).restore(try #require(report.backup))
    #expect(try read(paths.retroarchConfig) == "menu_driver = \"ozone\"\n")
    #expect(!FileManager.default.fileExists(atPath: paths.globalShaderPreset.path))
}
@Test func keepsUserSystemsAndCoreOverrideKeys() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    try write("""
        <?xml version="1.0"?>
        <systemList>
            <system><name>ps2</name><fullname>Mine</fullname><command label="PCSX2">pcsx2 %ROM%</command></system>
            <system><name>nes</name><fullname>Old</fullname><command label="Old">old %ROM%</command></system>
        </systemList>
        """, to: paths.esdeCustomSystems)
    try write("mesen_aspect_ratio = \"NTSC\"\n", to: paths.coreOverride(libraryName: "Mesen"))
    let applier = Applier(paths: paths, apps: appNames, isRunning: { _ in false })
    _ = try applier.apply(try renderInto(home))
    let xml = try read(paths.esdeCustomSystems)
    #expect(xml.contains("<name>ps2</name>"))
    #expect(xml.components(separatedBy: "<name>nes</name>").count == 2)
    #expect(xml.contains("mesen_libretro.dylib"))
    #expect(!xml.contains("old %ROM%"))
    let override = try read(paths.coreOverride(libraryName: "Mesen"))
    #expect(override.contains("mesen_aspect_ratio = \"NTSC\""))
    #expect(override.contains("run_ahead_enabled = \"true\""))
    #expect(try applier.apply(try renderInto(home)).written.isEmpty)
}
