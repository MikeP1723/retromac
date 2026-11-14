// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import Testing
@testable import RetromacCore

func datXML(header: String, version: String = "20261001-000000", games: [(name: String, sha1: String)]) -> Data {
    var xml = """
        <?xml version="1.0"?>
        <!DOCTYPE datafile PUBLIC "-//Logiqx//DTD ROM Management Datafile//EN" "http://www.logiqx.com/Dats/datafile.dtd">
        <datafile>
        <header><name>\(header)</name><description>\(header)</description><version>\(version)</version></header>

        """
    for game in games {
        xml += "<game name=\"\(game.name)\"><description>\(game.name)</description>"
        xml += "<rom name=\"\(game.name).bin\" size=\"16\" crc=\"00000000\" sha1=\"\(game.sha1)\"/></game>\n"
    }
    return Data((xml + "</datafile>\n").utf8)
}

func sha1hex(_ data: some DataProtocol) -> String {
    Insecure.SHA1.hash(data: Data(data)).map { String(format: "%02x", $0) }.joined()
}

@Test func parsesNoIntroNES() throws {
    let dat = try DatParser.parse(datXML(header: "Nintendo - Nintendo Entertainment System (Headerless)",
                                         games: [("Alpha (USA)", "AA11"), ("Beta (Japan)", "bb22")]))
    #expect(dat.system == .nes)
    #expect(dat.version == "20261001-000000")
    #expect(dat.entries == ["aa11": DatEntry(name: "Alpha (USA)"), "bb22": DatEntry(name: "Beta (Japan)")])
}
@Test func mapsAllFourSystems() throws {
    for (header, system) in [("Nintendo - Super Nintendo Entertainment System", SystemID.snes),
                             ("Sega - Mega Drive - Genesis", .genesis), ("Nintendo - Nintendo 64 (BigEndian)", .n64)] {
        #expect(try DatParser.parse(datXML(header: header, games: [])).system == system)
    }
}
@Test func rejectsByteSwappedN64() {
    #expect(throws: DatError.unsupportedVariant("use the BigEndian DAT")) {
        try DatParser.parse(datXML(header: "Nintendo - Nintendo 64 (ByteSwapped)", games: []))
    }
}
@Test func rejectsUnknownSystem() {
    #expect(throws: DatError.unknownSystem("Atari - 2600")) { try DatParser.parse(datXML(header: "Atari - 2600", games: [])) }
}
@Test func rejectsNonDat() {
    #expect(throws: DatError.notADat) { try DatParser.parse(Data("hello".utf8)) }
}
@Test func importsDatAndZipAndReplaces() throws {
    let home = try makeTempDir()
    let store = DatStore(paths: Paths(home: home))
    let one = home.appending(path: "nes.dat")
    try datXML(header: "Nintendo - Nintendo Entertainment System (Headerless)", games: [("Alpha (USA)", "aa11")]).write(to: one)
    _ = try store.importDats([one], runner: ProcessRunner())
    #expect(store.load()[.nes]?.entries.count == 1)

    let staging = home.appending(path: "zipsrc")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    try datXML(header: "Nintendo - Nintendo Entertainment System (Headerless)",
               games: [("Alpha (USA)", "aa11"), ("Beta (Japan)", "bb22")]).write(to: staging.appending(path: "Nintendo NES.dat"))
    let zip = home.appending(path: "dats.zip")
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", zip.path, "-C", staging.path, "Nintendo NES.dat"])
    let imported = try store.importDats([zip], runner: ProcessRunner())
    #expect(imported.map(\.system) == [.nes])
    #expect(store.load()[.nes]?.entries.count == 2)
    #expect(store.lookup(.nes, sha1: ["zz", "bb22"]) == DatEntry(name: "Beta (Japan)"))
    #expect(store.lookup(.snes, sha1: ["bb22"]) == nil)
}
