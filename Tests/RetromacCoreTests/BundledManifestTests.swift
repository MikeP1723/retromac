// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func bundledManifestIsCompliant() throws {
    let m = try Manifest.bundled()
    #expect(ManifestPolicy.violations(m).isEmpty)
    #expect(Set(m.cores.map(\.system)).union(m.apps.flatMap { $0.systems ?? [] }) == Set(m.installableSystems))
    #expect(Set(m.apps.map(\.id)) == ["retroarch", "esde", "dolphin", "xemu"])
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
    #expect(m.installableSystems == [.nes, .snes, .genesis, .n64, .psx, .saturn, .gc, .wii, .xbox])
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
