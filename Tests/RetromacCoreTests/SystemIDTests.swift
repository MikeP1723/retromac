// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func rawValuesAreESDEFolders() {
    #expect(SystemID.allCases.map(\.rawValue)
        == ["nes", "snes", "genesis", "n64", "psx", "ps2", "saturn", "gc", "wii", "xbox", "wiiu", "switch"])
}
@Test func installableIsCartridgeToday() throws {
    #expect(try Manifest.bundled().installableSystems == [.nes, .snes, .genesis, .n64])
    #expect(SystemID.allCases.filter(\.isCartridge) == [.nes, .snes, .genesis, .n64])
}
@Test func displayNamesCoverAll() {
    #expect(SystemID.allCases.allSatisfy { !$0.displayName.isEmpty })
    #expect(SystemID.psx.displayName == "PlayStation")
    #expect(SystemID.gc.displayName == "GameCube")
}
