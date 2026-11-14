// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

extension ImportRig {
    func importClrMame(_ header: String, _ games: String) throws {
        let url = dir.appending(path: "\(UUID().uuidString).dat")
        try clrmame(header, games).write(to: url)
        _ = try DatStore(paths: paths).importDats([url], runner: ProcessRunner())
    }
}

@Test func ps2IsoIdentifiedBySerial() throws {
    let rig = try ImportRig()
    try rig.importClrMame("Sony - PlayStation 2", "game ( name \"Gran Turismo 3 - A-Spec (USA)\" serial \"SLUS-20062\" rom ( name \"gt3.iso\" sha1 AA ) )")
    let iso = try isoImage(rig.drops.appending(path: "gt3.iso"), systemCNF: "BOOT2 = cdrom0:\\SLUS_200.62;1\n")
    let (_, candidates) = try rig.importer.analyze([iso])
    #expect(candidates.map(\.status) == [.identified(.ps2, name: "Gran Turismo 3 - A-Spec (USA)")])
    #expect(candidates[0].destination == rig.library.appending(path: "ps2/Gran Turismo 3 - A-Spec (USA).iso"))
}
@Test func bigImageCopiedOnceNeverLoaded() throws {
    let rig = try ImportRig()
    let iso = try gcmImage(rig.drops.appending(path: "Wind Waker (U).iso"), id: "GZLE", wii: false, size: 6 << 30)
    let start = Date()
    let (session, candidates) = try rig.importer.analyze([iso])
    #expect(Date().timeIntervalSince(start) < 1)
    #expect(candidates.map(\.status) == [.unverified(.gc)])
    let done = try rig.importer.commit(session, candidates)
    let filed = try #require(done[0].destination)
    #expect(filed == rig.library.appending(path: "gc/Wind Waker (USA).iso"))
    #expect(try FileManager.default.attributesOfItem(atPath: filed.path)[.size] as? UInt64 == 6 << 30)
    #expect(FileManager.default.fileExists(atPath: iso.path))
}
@Test func zippedCueBinSetIsFiledTogether() throws {
    let rig = try ImportRig()
    let src = rig.dir.appending(path: "zipsrc")
    _ = try isoImage(src.appending(path: "Track 1.bin"), systemCNF: "BOOT = cdrom:\\SCUS_941.63;1\n", raw: true, size: 1 << 20)
    try write("audio", to: src.appending(path: "Track 2.bin"))
    try write("FILE \"Track 1.bin\" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\nFILE \"Track 2.bin\" BINARY\n  TRACK 02 AUDIO\n    INDEX 01 00:00:00\n",
              to: src.appending(path: "Game (U).cue"))
    let zip = rig.drops.appending(path: "game.zip")
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", zip.path, "-C", src.path, "Game (U).cue", "Track 1.bin", "Track 2.bin"])

    let (session, candidates) = try rig.importer.analyze([zip])
    #expect(candidates.map(\.status) == [.unverified(.psx)])
    #expect(candidates[0].source == "game.zip › Game (U).cue")
    _ = try rig.importer.commit(session, candidates)
    let psx = rig.library.appending(path: "psx")
    #expect(try FileManager.default.contentsOfDirectory(atPath: psx.path).sorted()
        == ["Game (USA) (Track 1).bin", "Game (USA) (Track 2).bin", "Game (USA).cue"])
    let cue = try read(psx.appending(path: "Game (USA).cue"))
    #expect(cue.contains("FILE \"Game (USA) (Track 1).bin\" BINARY") && cue.contains("FILE \"Game (USA) (Track 2).bin\" BINARY"))
    #expect(try read(psx.appending(path: "Game (USA) (Track 2).bin")) == "audio")
    #expect(!Importer(libraryRoot: rig.library, dats: DatStore(paths: rig.paths), runner: ProcessRunner())
        .walk(session.dir).contains { $0.0.pathExtension == "bin" })
}
@Test func chdReportedNotCopied() throws {
    let rig = try ImportRig()
    let chd = try magicFile(rig.drops.appending(path: "game.chd"), Array("MComprHD".utf8))
    let (session, candidates) = try rig.importer.analyze([chd])
    #expect(candidates.map(\.status) == [.unidentified(reason: "CHD images can't be identified yet — drop the .cue/.bin or .iso instead")])
    #expect(candidates[0].destination == nil)
    _ = try rig.importer.commit(session, candidates)
    #expect(!FileManager.default.fileExists(atPath: rig.library.path))
}
@Test func switchNamedFromFilename() throws {
    let rig = try ImportRig()
    let nsp = try magicFile(rig.drops.appending(path: "Game Name [0100ABCD00010000][v0].nsp"), Array("PFS0".utf8))
    let (_, candidates) = try rig.importer.analyze([nsp])
    #expect(candidates.map(\.status) == [.unverified(.switch)])
    #expect(candidates[0].destination == rig.library.appending(path: "switch/Game Name.nsp"))
}
@Test func sameSerialTwiceIsDuplicate() throws {
    let rig = try ImportRig()
    let a = try gcmImage(rig.drops.appending(path: "a.iso"), id: "GALE", wii: false)
    let b = try gcmImage(rig.drops.appending(path: "copy/b.iso"), id: "GALE", wii: false)
    let (_, candidates) = try rig.importer.analyze([a, b])
    #expect(candidates.map(\.status) == [.unverified(.gc), .duplicate(.gc)])
}
@Test func discAlreadyInLibraryIsDuplicate() throws {
    let rig = try ImportRig()
    let iso = try gcmImage(rig.drops.appending(path: "Zelda (U).iso"), id: "GZLE", wii: false)
    let (s1, c1) = try rig.importer.analyze([iso])
    _ = try rig.importer.commit(s1, c1)
    #expect(try rig.importer.analyze([iso]).1.map(\.status) == [.duplicate(.gc)])
}
@Test func unknownLargeIsoIsNotCopied() throws {
    let rig = try ImportRig()
    let iso = rig.drops.appending(path: "linux.iso")
    try sparseFile(iso)
    let (_, candidates) = try rig.importer.analyze([iso])
    #expect(candidates.map(\.status) == [.unidentified(reason: "not a recognized game image")])
    #expect(candidates[0].destination == nil)
}
