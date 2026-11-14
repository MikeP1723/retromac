// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

func id(_ url: URL) -> DiscID? {
    if case .success(let id) = DiscSniffer.sniff(url) { return id }
    return nil
}

@Test func ps1SerialFromRawBin() throws {
    let dir = try makeTempDir()
    let bin = try isoImage(dir.appending(path: "game.bin"), systemCNF: "BOOT = cdrom:\\SLUS_000.67;1\r\nTCB = 4\r\n", raw: true)
    #expect(id(bin) == DiscID(system: .psx, serial: "SLUS-00067", title: nil))
}
@Test func ps2FromBoot2() throws {
    let iso = try isoImage(try makeTempDir().appending(path: "game.iso"), systemCNF: "BOOT2 = cdrom0:\\SLUS_200.62;1\nVER = 1.00\n")
    #expect(id(iso) == DiscID(system: .ps2, serial: "SLUS-20062", title: nil))
}
@Test func playstationWithoutSystemCNF() throws {
    let iso = try isoImage(try makeTempDir().appending(path: "x.iso"), systemCNF: nil)
    #expect(id(iso) == DiscID(system: .psx, serial: nil, title: nil))
}
@Test func cueFollowsFirstDataTrack() throws {
    let dir = try makeTempDir()
    _ = try isoImage(dir.appending(path: "Game (Track 1).bin"), systemCNF: "BOOT = cdrom:\\SCUS_941.63;1\n", raw: true)
    try write("FILE \"Game (Track 1).bin\" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\nFILE \"Game (Track 2).bin\" BINARY\n  TRACK 02 AUDIO\n",
              to: dir.appending(path: "Game.cue"))
    #expect(id(dir.appending(path: "Game.cue")) == DiscID(system: .psx, serial: "SCUS-94163", title: nil))
}
@Test func saturnHeader() throws {
    let img = try saturnImage(try makeTempDir().appending(path: "s.iso"), serial: "T-4305G", title: "PANZER DRAGOON")
    #expect(id(img) == DiscID(system: .saturn, serial: "T-4305G", title: "PANZER DRAGOON", disc: 1))
}
@Test func gameCubeAndWiiAcrossContainers() throws {
    let dir = try makeTempDir()
    #expect(id(try gcmImage(dir.appending(path: "a.iso"), id: "GW7P", wii: false)) == DiscID(system: .gc, serial: "GW7P", title: "Test Disc", disc: 1))
    #expect(id(try gcmImage(dir.appending(path: "b.rvz"), id: "SP3E", wii: true, wrap: .rvz))?.system == .wii)
    #expect(id(try gcmImage(dir.appending(path: "c.wbfs"), id: "RJ2J", wii: true, wrap: .wbfs))?.serial == "RJ2J")
}
@Test func xboxSerialFromTitleID() throws {
    let dir = try makeTempDir()
    #expect(id(try xisoImage(dir.appending(path: "x.iso"), titleID: 0x4541_000D, title: "Test Game", redumpOffset: false))
        == DiscID(system: .xbox, serial: "EA-013", title: "Test Game", region: "USA"))
    #expect(id(try xisoImage(dir.appending(path: "z.iso"), titleID: 0x4541_000D, title: "T", redumpOffset: false, regions: 0x4))?.region == "Europe")
    #expect(id(try xisoImage(dir.appending(path: "y.iso"), titleID: 0x4D53_0004, title: "Halo", redumpOffset: true))?.serial == "MS-004")
}
@Test func wiiUAndSwitchContainers() throws {
    let dir = try makeTempDir()
    #expect(id(try magicFile(dir.appending(path: "a.wux"), Array("WUX0".utf8)))?.system == .wiiu)
    #expect(id(try magicFile(dir.appending(path: "b.wuhb"), Array("WUHB".utf8)))?.system == .wiiu)
    #expect(id(try magicFile(dir.appending(path: "c.nsp"), Array("PFS0".utf8)))?.system == .switch)
    #expect(id(try magicFile(dir.appending(path: "d.xci"), Array("HEAD".utf8), at: 0x100))?.system == .switch)
    #expect(id(try magicFile(dir.appending(path: "e.pbp"), [0x00, 0x50, 0x42, 0x50])) == DiscID(system: .psx, serial: nil, title: nil))
}
@Test func chdIsUnsupported() throws {
    let chd = try magicFile(try makeTempDir().appending(path: "a.chd"), Array("MComprHD".utf8))
    #expect(DiscSniffer.sniff(chd) == .failure(.init(reason: "CHD images can't be identified yet — drop the .cue/.bin or .iso instead")))
}
@Test func gczIsUnsupported() throws {
    let gcz = try magicFile(try makeTempDir().appending(path: "a.gcz"), [0x01, 0xC0, 0x0B, 0xB1])
    #expect(DiscSniffer.sniff(gcz) == .failure(.init(reason: "GCZ images aren't supported — convert to RVZ with Dolphin")))
}
@Test func loneCartridgeBinIsNil() throws {
    let url = try makeTempDir().appending(path: "sonic.bin")
    try genesisROM().write(to: url)
    #expect(DiscSniffer.sniff(url) == nil)
}
@Test func neverReadsWholeFile() throws {
    let iso = try gcmImage(try makeTempDir().appending(path: "big.iso"), id: "GALE", wii: false, size: 8 << 30)
    let start = Date()
    #expect(id(iso)?.system == .gc)
    #expect(Date().timeIntervalSince(start) < 1)
}
