// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func detectsNESAndHashesHeaderless() throws {
    let rom = nesROM()
    let s = try #require(RomSniffer.sniff(rom, ext: "nes"))
    #expect(s.system == .nes && s.ext == "nes" && s.normalized == rom)
    #expect(s.hashes == [sha1hex(rom.dropFirst(16)), sha1hex(rom)])
    #expect(s.headerTitle == nil)
}
@Test func n64ByteOrdersNormalizeToSameZ64() throws {
    let z = try #require(RomSniffer.sniff(n64ROM(order: .z64), ext: "z64"))
    let v = try #require(RomSniffer.sniff(n64ROM(order: .v64), ext: "v64"))
    let n = try #require(RomSniffer.sniff(n64ROM(order: .n64), ext: "n64"))
    #expect(v.normalized == z.normalized && n.normalized == z.normalized)
    #expect(z.system == .n64 && z.ext == "z64" && v.headerTitle == "MARIO")
    #expect(z.hashes == [sha1hex(z.normalized)])
    #expect(v.hashes == [sha1hex(z.normalized), sha1hex(n64ROM(order: .v64))])
}
@Test func detectsGenesisOverseasTitle() throws {
    let s = try #require(RomSniffer.sniff(genesisROM(), ext: "md"))
    #expect(s.system == .genesis && s.ext == "md" && s.headerTitle == "SONIC THE HEDGEHOG")
    #expect(RomSniffer.sniff(genesisROM(overseas: ""), ext: "md")?.headerTitle == "SONIC JP")
}
@Test func snesCopierHeaderStrippedAndChecksumValidated() throws {
    let headered = snesROM(copier: true)
    let s = try #require(RomSniffer.sniff(headered, ext: "smc"))
    #expect(s.system == .snes && s.ext == "sfc" && s.headerTitle == "SUPER GAME")
    #expect(s.normalized == headered.dropFirst(512))
    #expect(RomSniffer.sniff(snesROM(hiROM: true, title: "HI GAME"), ext: "sfc")?.headerTitle == "HI GAME")
    #expect(RomSniffer.sniff(snesROM(validChecksum: false), ext: "sfc") == nil)
}
@Test func unknownBytesAreNil() {
    #expect(RomSniffer.sniff(Data(repeating: 0, count: 4096), ext: "sfc") == nil)
    #expect(RomSniffer.sniff(Data(), ext: "sfc") == nil)
}
@Test func sanitizesNames() {
    #expect(RomSniffer.sanitize("  ../Evil: Name/Part  ") == "-Evil- Name-Part")
    #expect(RomSniffer.sanitize(String(repeating: "é", count: 300)).utf8.count <= 200)
    #expect(RomSniffer.sanitize(" .. ") == "Untitled")
}
@Test func snesHeuristicOnlyForSnesExtensions() {
    #expect(RomSniffer.sniff(snesROM(), ext: "dat") == nil)
    #expect(RomSniffer.sniff(snesROM(), ext: "sfc")?.system == .snes)
    #expect(RomSniffer.sniff(snesROM(), ext: "bin")?.system == .snes)
    #expect(RomSniffer.sniff(nesROM(), ext: "dat")?.system == .nes)
}
@Test func snesRequiresPlausibleMapMode() {
    #expect(RomSniffer.sniff(snesROM(mapMode: 0x00), ext: "sfc") == nil)
}
