// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

private func switchProfile(library: URL = URL(filePath: "/lib"), confirmed: Bool = true) -> Profile {
    var p = profile(systems: [.nes, .switch], library: library)
    p.switchSetup = SwitchSetup(confirmed: confirmed)
    return p
}

private func renderWith(_ p: Profile, _ paths: Paths) throws -> [RenderedFile] {
    ProfileRenderer.render(p, manifest: .fixture(), rules: try DisplayRules.bundled(), paths: paths, chip: "Apple M4 Pro")
}

private func systemsXML(_ files: [RenderedFile], _ paths: Paths) -> String? {
    for f in files where f.url == paths.esdeCustomSystems { if case .esdeSystems(let xml) = f.kind { return xml } }
    return nil
}

private func findRules(_ files: [RenderedFile], _ paths: Paths) -> String? {
    for f in files where f.url == paths.esdeFindRules { if case .whole(let xml) = f.kind { return xml } }
    return nil
}

@Test func nothingForRyubingUnlessSwitchIsChosen() throws {
    let paths = try ryubingPaths(config: #"{"version": 70}"#)
    var p = switchProfile(); p.systems = [.nes]
    let files = try renderWith(p, paths)
    #expect(!files.contains { $0.url == paths.ryubingConfig })
    #expect(!(try #require(systemsXML(files, paths))).contains("<name>switch</name>"))
}

@Test func liveSwitchRendersConfigAndESDEEntry() throws {
    let paths = try ryubingPaths(config: #"{"version": 70}"#)
    let files = try renderWith(switchProfile(), paths)
    #expect(files.first { $0.url == paths.ryubingConfig }?.kind == .ryubingConfig(gameDir: "/lib/switch", replacing: nil))
    let xml = try #require(systemsXML(files, paths))
    #expect(xml.contains("<name>switch</name>"))
    #expect(xml.contains("<fullname>Nintendo Switch</fullname>"))
    #expect(xml.contains(#"<command label="Ryubing">%EMULATOR_RYUJINX% --fullscreen --docked-mode --hide-updates %ROM%</command>"#))
    #expect(xml.contains("<extension>.nca .NCA .nro .NRO .nso .NSO .nsp .NSP .xci .XCI</extension>"))
    let rules = try #require(findRules(files, paths))
    #expect(rules.contains(#"<emulator name="RYUJINX">"#))
    #expect(rules.contains("<entry>\(paths.ryubingExecutable.path)</entry>"))
}

@Test func switchLeavesESDEWhenConfigIsUnknown() throws {
    let live = try ryubingPaths(config: #"{"version": 70}"#)
    let before = try #require(systemsXML(try renderWith(switchProfile(), live), live))
    let paths = try ryubingPaths(config: #"{"version": 71}"#)
    let files = try renderWith(switchProfile(), paths)
    #expect(!files.contains { $0.url == paths.ryubingConfig })
    let after = try #require(systemsXML(files, paths))
    #expect(!after.contains("<name>switch</name>"))
    #expect(!(try ESDESystems.merge(existing: before, ours: after)).contains("<name>switch</name>"))
}

@Test func switchOnANetworkLibrary() throws {
    let paths = try ryubingPaths(config: #"{"version": 70}"#)
    var p = switchProfile()
    p.useNetworkLibrary(URL(string: "smb://nas/roms")!, at: URL(filePath: "/Volumes/roms"))
    let files = try renderWith(p, paths)
    #expect(files.first { $0.url == paths.ryubingConfig }?.kind == .ryubingConfig(gameDir: "/Volumes/roms/switch", replacing: nil))
    #expect(!files.contains { $0.kind == .directory && $0.url.path.hasPrefix("/Volumes/roms") })
}

@Test func ryujinxIsAnEmulatorAppForConsoleMode() {
    #expect(ESDESystems.emulatorApps.contains("Ryujinx.app"))
}

@Test func applyWritesRyubingConfigOnlyWhenKnown() throws {
    let paths = try ryubingPaths(config: #"{"version": 70, "show_confirm_exit": true}"#)
    let applier = Applier(paths: paths, apps: [], isRunning: { _ in false })
    let file = RenderedFile(url: paths.ryubingConfig, kind: .ryubingConfig(gameDir: "/lib/switch", replacing: nil))
    let report = try applier.apply([file])
    #expect(report.written == [paths.ryubingConfig])
    #expect(try String(contentsOf: paths.ryubingConfig, encoding: .utf8).contains(#""show_confirm_exit" : false"#))
    let backup = try #require(report.backup)
    #expect(try String(contentsOf: backup.appending(path: "Library/Application Support/Ryujinx/Config.json"), encoding: .utf8)
        == #"{"version": 70, "show_confirm_exit": true}"#)
    #expect(try applier.apply([file]).written.isEmpty)  // a second apply changes nothing

    let unknown = try ryubingPaths(config: #"{"version": 71}"#)
    let untouched = try Applier(paths: unknown, apps: [], isRunning: { _ in false })
        .apply([RenderedFile(url: unknown.ryubingConfig, kind: .ryubingConfig(gameDir: "/lib/switch", replacing: nil))])
    #expect(untouched.written.isEmpty && untouched.backup == nil)
    #expect(try String(contentsOf: unknown.ryubingConfig, encoding: .utf8) == #"{"version": 71}"#)
}
