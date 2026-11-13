// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

func profile(_ display: DisplayProfile = tv65_4k, look: Look = .crt, systems: Set<SystemID> = Set(SystemID.allCases),
             controllers: [ControllerProfile] = [.init(deviceName: "Xbox Wireless Controller", kind: .xbox)],
             library: URL = URL(filePath: "/tmp/h/retromac/Library")) -> Profile {
    Profile(display: display, look: look, systems: systems, controllers: controllers, facePolicy: .position, libraryRoot: library)
}

func render(_ p: Profile, home: String = "/tmp/h") throws -> [RenderedFile] {
    ProfileRenderer.render(p, manifest: .fixture(), rules: try DisplayRules.bundled(), paths: Paths(home: URL(filePath: home)))
}

func retroarchKeys(_ files: [RenderedFile]) -> [String: String] {
    for f in files { if case .retroarchKeys(let keys) = f.kind { return keys } }
    return [:]
}

func wholeContent(_ files: [RenderedFile], _ url: URL) -> String? {
    for f in files where f.url == url { if case .whole(let s) = f.kind { return s } }
    return nil
}

@Test func rendersRetroArchKeysForCrtOn4K() throws {
    let keys = retroarchKeys(try render(profile()))
    #expect(keys["video_shader_enable"] == "true")
    #expect(keys["vrr_runloop_enable"] == "true")
    #expect(keys["video_refresh_rate"] == "120.000000")
    #expect(keys["video_scale_integer"] == "true")
    #expect(keys["input_joypad_driver"] == "mfi")
}
@Test func smoothDisablesIntegerScaling() throws {
    #expect(retroarchKeys(try render(profile(look: .smooth)))["video_scale_integer"] == "false")
}
@Test func crispDisablesShaderAndWritesNoPreset() throws {
    let files = try render(profile(look: .crisp))
    #expect(retroarchKeys(files)["video_shader_enable"] == "false")
    #expect(!files.contains { $0.url.lastPathComponent == "global.slangp" })
}
@Test func runAheadOnlyForCheapCores() throws {
    let paths = Paths(home: URL(filePath: "/tmp/h"))
    let files = try render(profile())
    for lib in ["Mesen", "bsnes", "BlastEm"] {
        #expect(wholeContent(files, paths.coreOverride(libraryName: lib))?.contains("run_ahead_enabled = \"true\"") == true)
    }
    #expect(wholeContent(files, paths.coreOverride(libraryName: "Mupen64Plus-Next")) == nil)
}
@Test func noControllersMeansNoAutoconfig() throws {
    let paths = Paths(home: URL(filePath: "/tmp/h"))
    let files = try render(profile(controllers: []))
    #expect(!files.contains { $0.url.path.hasPrefix(paths.retroarchAutoconfigMFi.path) })
    #expect(files.contains { $0.url == paths.retroarchConfig })
}
@Test func shaderReferenceQuotesPathWithSpaces() throws {
    let paths = Paths(home: URL(filePath: "/tmp/my home"))
    let files = try render(profile(), home: "/tmp/my home")
    #expect(wholeContent(files, paths.globalShaderPreset)?.contains(
        "#reference \"/tmp/my home/Library/Application Support/RetroArch/shaders/shaders_slang/crt/crt-guest-advanced.slangp\"") == true)
}
@Test func esdeSystemsOnlySelected() throws {
    let paths = Paths(home: URL(filePath: "/tmp/h"))
    let xml = try #require(wholeContent(try render(profile(systems: [.nes, .n64])), paths.esdeCustomSystems))
    #expect(xml.contains("<name>nes</name>")); #expect(xml.contains("<name>n64</name>"))
    #expect(!xml.contains("<name>snes</name>"))
    #expect(xml.contains("%CORE_RETROARCH%/mesen_libretro.dylib %ROM%"))
}
@Test func libraryDirectoriesForSelectedSystems() throws {
    let files = try render(profile(systems: [.snes]))
    #expect(files.filter { $0.kind == .directory }.map(\.url.path) == ["/tmp/h/retromac/Library/snes"])
}
@Test func renderIsDeterministic() throws {
    let a = try render(profile()), b = try render(profile())
    #expect(a == b)
    #expect(a.map(\.url.path) == a.map(\.url.path).sorted())
}
