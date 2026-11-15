// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func findRulesPointAtEncapsulatedRetroArch() throws {
    let paths = Paths(home: URL(filePath: "/tmp/my home"))
    let xml = ESDESystems.findRules(paths: paths)
    #expect(xml.contains("<entry>/tmp/my home/Library/Application Support/retromac/Apps/RetroArch.app/Contents/MacOS/RetroArch</entry>"))
    #expect(xml.contains("<entry>/tmp/my home/Library/Application Support/RetroArch/cores</entry>"))
    let doc = try XMLDocument(xmlString: xml)
    #expect(doc.rootElement()?.name == "ruleList")
}
@Test func findRulesEscapeXML() {
    let xml = ESDESystems.findRules(paths: Paths(home: URL(filePath: "/a&b<c")))
    #expect(xml.contains("/a&amp;b&lt;c/Library/Application Support/retromac/Apps/RetroArch.app") && !xml.contains("/a&b"))
}
@Test func findRulesPointAtRetromacApps() throws {
    let xml = ESDESystems.findRules(paths: Paths(home: URL(filePath: "/tmp/my home")))
    let apps = "/tmp/my home/Library/Application Support/retromac/Apps"
    #expect(xml.contains("<emulator name=\"DOLPHIN\">") && xml.contains("<entry>\(apps)/Dolphin.app/Contents/MacOS/Dolphin</entry>"))
    #expect(xml.contains("<emulator name=\"XEMU\">") && xml.contains("<entry>\(apps)/xemu.app/Contents/MacOS/xemu</entry>"))
    _ = try XMLDocument(xmlString: xml)
}
@Test func gamecubeLaunchesDolphin() throws {
    let xml = ESDESystems.xml(for: [.gc, .wii], manifest: try Manifest.bundled())
    for needle in ["<name>gc</name>", "<name>wii</name>", "%EMULATOR_DOLPHIN% -b -e %ROM%", "label=\"Dolphin\"", ".rvz", ".wbfs"] {
        #expect(xml.contains(needle), "missing \(needle)")
    }
    #expect(!xml.contains(".gcz"))
}
@Test func xboxLaunchesXemu() throws {
    let xml = ESDESystems.xml(for: [.xbox], manifest: try Manifest.bundled())
    #expect(xml.contains("<name>xbox</name>") && xml.contains("%EMULATOR_XEMU% -dvd_path %ROM%") && xml.contains(".xiso"))
}
@Test func rendererWritesFindRules() throws {
    let paths = Paths(home: URL(filePath: "/tmp/h"))
    let files = try render(profile())
    #expect(files.contains { $0.url == paths.esdeFindRules })
}
@Test func launchArgumentsAreOneHomeArgument() {
    #expect(ESDELauncher.arguments(paths: Paths(home: URL(filePath: "/tmp/my home")))
        == ["--home", "/tmp/my home/Library/Application Support/retromac"])
}
@Test func ps2LaunchesPcsx2() throws {
    let xml = ESDESystems.xml(for: [.ps2], manifest: try Manifest.bundled())
    for needle in ["<name>ps2</name>", "Sony PlayStation 2", "%EMULATOR_PCSX2% -batch -nogui -fullscreen %ROM%", ".chd", ".iso"] {
        #expect(xml.contains(needle), "missing \(needle)")
    }
}
@Test func findRulesIncludePcsx2() {
    let xml = ESDESystems.findRules(paths: Paths(home: URL(filePath: "/tmp/my home")))
    #expect(xml.contains("<emulator name=\"PCSX2\">")
        && xml.contains("<entry>/tmp/my home/Library/Application Support/retromac/Apps/PCSX2.app/Contents/MacOS/PCSX2</entry>"))
    // Console Mode's exit combo quits it too.
    #expect(ESDESystems.emulatorApps.contains("PCSX2.app"))
}
