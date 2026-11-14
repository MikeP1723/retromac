// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func findRulesPointAtEncapsulatedRetroArch() throws {
    let paths = Paths(home: URL(filePath: "/tmp/my home"))
    let xml = ESDESystems.findRules(retroarch: paths.retroarchExecutable, cores: paths.retroarchCores)
    #expect(xml.contains("<entry>/tmp/my home/Library/Application Support/retromac/Apps/RetroArch.app/Contents/MacOS/RetroArch</entry>"))
    #expect(xml.contains("<entry>/tmp/my home/Library/Application Support/RetroArch/cores</entry>"))
    let doc = try XMLDocument(xmlString: xml)
    #expect(doc.rootElement()?.name == "ruleList")
}
@Test func findRulesEscapeXML() {
    let xml = ESDESystems.findRules(retroarch: URL(filePath: "/a&b/RetroArch"), cores: URL(filePath: "/c<d"))
    #expect(xml.contains("/a&amp;b/RetroArch") && xml.contains("/c&lt;d"))
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
