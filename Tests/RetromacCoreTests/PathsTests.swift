// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func pathsResolveUnderHome() {
    let p = Paths(home: URL(filePath: "/tmp/h"))
    #expect(p.retroarchConfig.path == "/tmp/h/Library/Application Support/RetroArch/config/retroarch.cfg")
    #expect(p.coreOverride(libraryName: "Mesen").path == "/tmp/h/Library/Application Support/RetroArch/config/Mesen/Mesen.cfg")
    #expect(p.esdeCustomSystems.path == "/tmp/h/ES-DE/custom_systems/es_systems.xml")
}
