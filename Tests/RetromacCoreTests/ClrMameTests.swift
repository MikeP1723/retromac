// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

func clrmame(_ header: String, _ games: String) -> Data {
    Data("""
        clrmamepro (
        \tname "\(header)"
        \tdescription "\(header)"
        \tversion "2026.10.07"
        )

        \(games)
        """.utf8)
}

@Test func parsesNoIntroClrMame() throws {
    let dat = try ClrMameParser.parse(clrmame("Nintendo - Nintendo Entertainment System", """
        game (
        \tname "!Clik! (World) (Proto 1)"
        \trom ( name "!Clik! (World) (Proto 1) (Aftermarket) (Unl).nes" size 16400 crc 865709AB md5 C0 sha1 953472C36D709D168763F5EBA662C460D74EB925 )
        )
        game (
        \tname "!Clik! (World) (Proto 1)"
        \trom ( name "!Clik! (World) (Proto 1) (Aftermarket) (Unl).unh" size 16384 crc A2C2C172 md5 D1 sha1 B975DF7F8F4FD0D57B860390CAEE4B437D1F2469 )
        )
        """))
    #expect(dat.system == .nes && dat.version == "2026.10.07")
    #expect(dat.entries == ["953472c36d709d168763f5eba662c460d74eb925": DatEntry(name: "!Clik! (World) (Proto 1)"),
                            "b975df7f8f4fd0d57b860390caee4b437d1f2469": DatEntry(name: "!Clik! (World) (Proto 1)")])
}
@Test func parsesRedumpSerials() throws {
    let dat = try ClrMameParser.parse(clrmame("Sony - PlayStation", """
        game (
        \tname "Crash Bandicoot (USA)"
        \tregion "USA"
        \tserial "SCUS-94900"
        \trom ( name "Crash Bandicoot (USA).bin" size 1 crc 0 md5 0 sha1 AB serial "SCUS-94900" )
        )
        """))
    #expect(dat.system == .psx)
    #expect(dat.serials["SCUS94900"] == [DatEntry(name: "Crash Bandicoot (USA)")])
}
@Test func gameCubeGameIDKey() throws {
    let home = try makeTempDir()
    let url = home.appending(path: "gc.dat")
    try clrmame("Nintendo - GameCube", """
        game (
        \tname "007 - Agent Under Fire (Europe)"
        \tserial "DL-DOL-GW7P-EUR"
        \trom ( name "007.iso" size 1 crc 0 sha1 CD serial "DL-DOL-GW7P-EUR" )
        )
        """).write(to: url)
    let store = DatStore(paths: Paths(home: home))
    _ = try store.importDats([url], runner: ProcessRunner())
    #expect(store.lookup(.gc, serial: "GW7P") == DatEntry(name: "007 - Agent Under Fire (Europe)"))
}
@Test func multiSerialSplit() {
    #expect(SerialKey.keys(for: "SLUS-00892, SLUS-00908", system: .psx) == ["SLUS00892", "SLUS00908"])
    #expect(SerialKey.keys(for: "RVL-SP3E-USA-B0", system: .wii) == ["RVLSP3EUSAB0", "SP3E"])
    #expect(SerialKey.normalize("slus_000.67") == "SLUS00067")
}
@Test func distinguishesPS1FromPS2AndPSP() throws {
    #expect(try ClrMameParser.parse(clrmame("Sony - PlayStation 2", "")).system == .ps2)
    #expect(throws: DatError.unknownSystem("Sony - PlayStation Portable")) {
        try ClrMameParser.parse(clrmame("Sony - PlayStation Portable", ""))
    }
    #expect(try DatParser.systemFor(headerName: "Microsoft - Xbox") == .xbox)
    #expect(try DatParser.systemFor(headerName: "Sega - Saturn") == .saturn)
    #expect(try DatParser.systemFor(headerName: "Nintendo - Wii") == .wii)
}
@Test func escapedQuotes() throws {
    let dat = try ClrMameParser.parse(clrmame("Sega - Saturn", """
        game ( name "Say \\"Hi\\" (Japan)" serial "T-1234G" rom ( name "x.bin" sha1 EF ) )
        """))
    #expect(dat.serials["T1234G"] == [DatEntry(name: "Say \"Hi\" (Japan)")])
}
@Test func old3aJSONStillLoads() throws {
    let json = #"{"system":"nes","source":"x","version":"1","entries":{"aa":{"name":"A"}}}"#
    let dat = try JSONDecoder().decode(DatFile.self, from: Data(json.utf8))
    #expect(dat.serials.isEmpty && dat.entries["aa"]?.name == "A")
}
@Test func clrMameImportedThroughStore() throws {
    let home = try makeTempDir()
    let url = home.appending(path: "nes.dat")
    try clrmame("Nintendo - Nintendo Entertainment System", "game ( name \"A\" rom ( name \"a.nes\" sha1 AA ) )").write(to: url)
    let outcomes = try DatStore(paths: Paths(home: home)).importDats([url], runner: ProcessRunner())
    #expect(outcomes.compactMap(\.imported).map(\.system) == [.nes])
}
func storeWith(_ header: String, _ games: [(name: String, serial: String)]) throws -> DatStore {
    let home = try makeTempDir()
    let url = home.appending(path: "x.dat")
    try clrmame(header, games.map { "game ( name \"\($0.name)\" serial \"\($0.serial)\" rom ( name \"x\" sha1 \(UUID().uuidString.prefix(8)) ) )" }
        .joined(separator: "\n")).write(to: url)
    let store = DatStore(paths: Paths(home: home))
    _ = try store.importDats([url], runner: ProcessRunner())
    return store
}

@Test func multiDiscSameSerialUsesBaseName() throws {
    let store = try storeWith("Sony - PlayStation", [("Final Fantasy VII (USA) (Disc 1)", "SCUS-94163"),
                                                   ("Final Fantasy VII (USA) (Disc 2)", "SCUS-94163"),
                                                   ("Final Fantasy VII (USA) (Disc 3)", "SCUS-94163")])
    #expect(store.lookup(.psx, serial: "SCUS-94163") == DatEntry(name: "Final Fantasy VII (USA)"))
}
@Test func conflictingNamesAreNotGuessed() throws {
    let store = try storeWith("Microsoft - Xbox", [("007 - Agent Under Fire (USA)", "EA-013"), ("007 - Agent Under Fire (Europe)", "EA-013")])
    #expect(store.lookup(.xbox, serial: "EA-013") == nil)
}
@Test func gameCubeDiscNumberSelectsDisc() throws {
    let store = try storeWith("Nintendo - GameCube", [("Resident Evil 4 (USA) (Disc 1)", "DL-DOL-G4BE-0-USA"),
                                                    ("Resident Evil 4 (USA) (Disc 2)", "DL-DOL-G4BE-1-USA")])
    #expect(store.lookup(.gc, serial: "G4BE", disc: 1) == DatEntry(name: "Resident Evil 4 (USA) (Disc 1)"))
    #expect(store.lookup(.gc, serial: "G4BE", disc: 2) == DatEntry(name: "Resident Evil 4 (USA) (Disc 2)"))
    #expect(store.lookup(.gc, serial: "G4BE") == DatEntry(name: "Resident Evil 4 (USA)"))
}
@Test func saturnDiscNumberSelectsDisc() throws {
    let store = try storeWith("Sega - Saturn", [("Panzer Dragoon Saga (USA) (Disc 1)", "MK-81307-1"),
                                              ("Panzer Dragoon Saga (USA) (Disc 2)", "MK-81307-2")])
    #expect(store.lookup(.saturn, serial: "MK-81307", disc: 2) == DatEntry(name: "Panzer Dragoon Saga (USA) (Disc 2)"))
}
@Test func regionHintPicksRegionalRelease() throws {
    let store = try storeWith("Microsoft - Xbox", [("007 - Agent Under Fire (USA)", "EA-013"), ("007 - Agent Under Fire (Europe)", "EA-013")])
    #expect(store.load()[.xbox]?.lookup(serial: "EA-013", disc: nil, region: "Europe") == DatEntry(name: "007 - Agent Under Fire (Europe)"))
    #expect(store.load()[.xbox]?.lookup(serial: "EA-013", disc: nil, region: "Japan") == nil)
}
