// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

let supportRoot = "/tmp/h/Library/Application Support/retromac"

@Test func pathsResolveUnderApplicationSupport() {
    let p = Paths(home: URL(filePath: "/tmp/h"))
    #expect(p.root.path == supportRoot)
    #expect(p.retromacRoot == p.root)
    #expect(p.defaultLibraryRoot.path == "\(supportRoot)/Library")
    #expect(p.applications.path == "\(supportRoot)/Apps")
    #expect(p.esdeHome.path == supportRoot)
    #expect(p.esdeSettings.path == "\(supportRoot)/ES-DE/settings/es_settings.xml")
    #expect(p.esdeCustomSystems.path == "\(supportRoot)/ES-DE/custom_systems/es_systems.xml")
    #expect(p.esdeFindRules.path == "\(supportRoot)/ES-DE/custom_systems/es_find_rules.xml")
    #expect(p.retroarchExecutable.path == "\(supportRoot)/Apps/RetroArch.app/Contents/MacOS/RetroArch")
    #expect(p.retroarchConfig.path == "/tmp/h/Library/Application Support/RetroArch/config/retroarch.cfg")
    #expect(p.coreOverride(libraryName: "Mesen").path == "/tmp/h/Library/Application Support/RetroArch/config/Mesen/Mesen.cfg")
}
@Test func explicitApplicationsStillWins() {
    #expect(Paths(home: URL(filePath: "/tmp/h"), applications: URL(filePath: "/tmp/apps")).applications.path == "/tmp/apps")
}
@Test func legacyPaths() {
    let l = LegacyPaths(home: URL(filePath: "/tmp/h"))
    #expect(l.root.path == "/tmp/h/retromac")
    #expect(l.esde.path == "/tmp/h/ES-DE")
    #expect(l.applications.path == "/Applications")
}
