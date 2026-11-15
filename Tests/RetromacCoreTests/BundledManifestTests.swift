// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func bundledManifestIsCompliant() throws {
    let m = try Manifest.bundled()
    #expect(ManifestPolicy.violations(m).isEmpty)
    #expect(Set(m.cores.map(\.system)).union(m.apps.flatMap { $0.systems ?? [] }) == Set(m.installableSystems))
    #expect(Set(m.apps.map(\.id)) == ["retroarch", "esde", "dolphin", "xemu", "pcsx2"])
    #expect(m.manifestVersion == 1); #expect(m.minAppVersion == "0.1.0")
}

@Test func discCoresAreInstallable() throws {
    let manifest = try Manifest.bundled()
    #expect(manifest.core(for: .psx)?.libraryName == "PCSX-ReARMed")
    #expect(manifest.core(for: .psx)?.license == "GPL-2.0-or-later")
    #expect(manifest.core(for: .saturn)?.libraryName == "Beetle Saturn")
    #expect(manifest.core(for: .saturn)?.license == "GPL-2.0-or-later")
}

@Test func standalonesAreInstallable() throws {
    let m = try Manifest.bundled()
    #expect(m.installableSystems(osMajor: 27) == [.nes, .snes, .genesis, .n64, .psx, .ps2, .saturn, .gc, .wii, .xbox])
    #expect(m.app(for: .gc)?.id == "dolphin" && m.app(for: .wii)?.id == "dolphin")
    #expect(m.app(for: .xbox)?.id == "xemu")
    #expect(m.apps.first { $0.id == "retroarch" }?.systems == nil)
    #expect(m.assets.map(\.id) == ["xemu-hdd"])
    #expect(ManifestPolicy.violations(m).isEmpty)
}
@Test func manifestWithoutAssetsStillDecodes() throws {
    let json = #"{"schemaVersion":1,"manifestVersion":1,"minAppVersion":"0.1.0","apps":[],"cores":[]}"#
    #expect(try JSONDecoder().decode(Manifest.self, from: Data(json.utf8)).assets.isEmpty)
}

@Test func rosettaSystemsHiddenAfterMacOS27() throws {
    let m = try Manifest.bundled()
    #expect(m.installableSystems(osMajor: 27).contains(.ps2))
    #expect(!m.installableSystems(osMajor: 28).contains(.ps2))
    #expect(m.installableSystems(osMajor: 28).contains(.gc))
    #expect(m.app(for: .ps2)?.appName == "PCSX2.app" && m.app(for: .ps2)?.archiveAppName == "PCSX2-v2.8.2.app")
}
@Test func rosettaSystemsAreNotPreselected() throws {
    // A new user isn't asked for an admin password on first setup; PS2 is opt-in.
    let m = try Manifest.bundled()
    #expect(!m.defaultSystems(osMajor: 27).contains(.ps2))
    #expect(m.defaultSystems(osMajor: 27) == m.installableSystems(osMajor: 27).filter { $0 != .ps2 })
}
