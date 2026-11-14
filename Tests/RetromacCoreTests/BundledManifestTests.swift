// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func bundledManifestIsCompliant() throws {
    let m = try Manifest.bundled()
    #expect(ManifestPolicy.violations(m).isEmpty)
    #expect(m.cores.map(\.system) == m.installableSystems)
    #expect(Set(m.apps.map(\.id)) == ["retroarch", "esde"])
    #expect(m.manifestVersion == 1); #expect(m.minAppVersion == "0.1.0")
}

@Test func discCoresAreInstallable() throws {
    let manifest = try Manifest.bundled()
    #expect(manifest.installableSystems == [.nes, .snes, .genesis, .n64, .psx, .saturn])
    #expect(manifest.core(for: .psx)?.libraryName == "PCSX-ReARMed")
    #expect(manifest.core(for: .psx)?.license == "GPL-2.0-or-later")
    #expect(manifest.core(for: .saturn)?.libraryName == "Beetle Saturn")
    #expect(manifest.core(for: .saturn)?.license == "GPL-2.0-or-later")
}
