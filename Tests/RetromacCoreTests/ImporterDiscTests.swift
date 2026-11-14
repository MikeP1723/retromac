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
@Test func cancelledAnalysisStopsBetweenFiles() async throws {
    let rig = try ImportRig()
    let files = try (0..<5).map { try rig.drop("g\($0).nes", nesROM(prg: Data(repeating: UInt8($0), count: 16384))) }
    let importer = rig.importer
    let count = await Task { () -> Int in
        withUnsafeCurrentTask { $0?.cancel() }
        return (try? importer.analyze(files).1.count) ?? -1
    }.value
    #expect(count == 0)
}
@Test func cueCannotReachOutsideItsFolder() throws {
    let rig = try ImportRig()
    let victim = try rig.drop("victim.bin", Data("keep me".utf8))
    // From <session>/<extracted>/ two levels up is $TMPDIR, where the test folder lives.
    let escape = "../../\(rig.dir.lastPathComponent)/drops/victim.bin"
    let src = rig.dir.appending(path: "zipsrc")
    _ = try isoImage(src.appending(path: "Track 1.bin"), systemCNF: "BOOT = cdrom:\\SCUS_941.63;1\n", raw: true, size: 1 << 20)
    try write("FILE \"Track 1.bin\" BINARY\n  TRACK 01 MODE2/2352\nFILE \"\(escape)\" BINARY\n  TRACK 02 AUDIO\n",
              to: src.appending(path: "Evil.cue"))
    let zip = rig.drops.appending(path: "evil.zip")
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", zip.path, "-C", src.path, "Evil.cue", "Track 1.bin"])
    let (session, candidates) = try rig.importer.analyze([zip])
    #expect(candidates.map(\.status) == [.failed("the .cue refers to a file outside its folder: \(escape)")])
    _ = try rig.importer.commit(session, candidates)
    #expect(try read(victim) == "keep me")
}
@Test func multiDiscGameCubeImportsEveryDisc() throws {
    let rig = try ImportRig()
    try rig.importClrMame("Nintendo - GameCube", """
        game ( name "Resident Evil 4 (USA) (Disc 1)" serial "DL-DOL-G4BE-0-USA" rom ( name "a" sha1 A1 ) )
        game ( name "Resident Evil 4 (USA) (Disc 2)" serial "DL-DOL-G4BE-1-USA" rom ( name "b" sha1 B1 ) )
        """)
    let d1 = try gcmImage(rig.drops.appending(path: "re4-1.iso"), id: "G4BE", wii: false, disc: 0)
    let d2 = try gcmImage(rig.drops.appending(path: "re4-2.iso"), id: "G4BE", wii: false, disc: 1)
    let (_, candidates) = try rig.importer.analyze([d1, d2])
    #expect(candidates.map(\.status) == [.identified(.gc, name: "Resident Evil 4 (USA) (Disc 1)"),
                                         .identified(.gc, name: "Resident Evil 4 (USA) (Disc 2)")])
}
@Test func unquotedCueFileNames() throws {
    let rig = try ImportRig()
    let dir = rig.drops.appending(path: "ff")
    _ = try isoImage(dir.appending(path: "track01.bin"), systemCNF: "BOOT = cdrom:\\SCUS_941.63;1\n", raw: true, size: 1 << 20)
    try write("audio", to: dir.appending(path: "track02.bin"))
    try write("FILE track01.bin BINARY\r\n  TRACK 01 MODE2/2352\r\nFILE track02.bin BINARY\r\n  TRACK 02 AUDIO\r\n", to: dir.appending(path: "Game (U).cue"))
    let (session, candidates) = try rig.importer.analyze([dir])
    #expect(candidates.map(\.status) == [.unverified(.psx)])
    _ = try rig.importer.commit(session, candidates)
    let cue = try read(rig.library.appending(path: "psx/Game (USA).cue"))
    #expect(cue.contains("FILE \"Game (USA) (Track 1).bin\" BINARY") && cue.contains("FILE \"Game (USA) (Track 2).bin\" BINARY"))
    #expect(try read(rig.library.appending(path: "psx/Game (USA) (Track 2).bin")) == "audio")
}
@Test func caseMismatchedCueNames() throws {
    let rig = try ImportRig()
    let dir = rig.drops.appending(path: "win")
    _ = try isoImage(dir.appending(path: "Game (Track 1).bin"), systemCNF: "BOOT = cdrom:\\SCUS_941.63;1\n", raw: true, size: 1 << 20)
    try write("audio", to: dir.appending(path: "Game (Track 2).bin"))
    try write("FILE \"game (track 1).bin\" BINARY\n  TRACK 01 MODE2/2352\nFILE \"GAME (TRACK 2).BIN\" BINARY\n  TRACK 02 AUDIO\n", to: dir.appending(path: "Game.cue"))
    let (_, candidates) = try rig.importer.analyze([dir])
    #expect(candidates.map(\.status) == [.unverified(.psx)])
}
@Test func ps2LowercaseBootKeyAndDVDSize() throws {
    let dir = try makeTempDir()
    #expect(id(try isoImage(dir.appending(path: "a.iso"), systemCNF: "boot2 = cdrom0:\\SLUS_200.62;1\n"))?.system == .ps2)
    #expect(id(try isoImage(dir.appending(path: "b.iso"), systemCNF: nil, size: 2 << 30))?.system == .ps2)
}
@Test func failedSetCopyLeavesNothingBehind() throws {
    let rig = try ImportRig()
    let dir = rig.drops.appending(path: "set")
    _ = try isoImage(dir.appending(path: "Track 1.bin"), systemCNF: "BOOT = cdrom:\\SCUS_941.63;1\n", raw: true, size: 1 << 20)
    let unreadable = dir.appending(path: "Track 2.bin")
    try write("audio", to: unreadable)
    try write("FILE \"Track 1.bin\" BINARY\n  TRACK 01 MODE2/2352\nFILE \"Track 2.bin\" BINARY\n  TRACK 02 AUDIO\n", to: dir.appending(path: "Game.cue"))
    let cart = try rig.drop("ok.nes", nesROM())
    let (session, candidates) = try rig.importer.analyze([dir, cart])
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: unreadable.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path) }
    let done = try rig.importer.commit(session, candidates)
    guard case .failed = done[0].status else { Issue.record("expected failed, got \(done[0].status)"); return }
    #expect(done[1].status == .unverified(.nes))
    let psx = rig.library.appending(path: "psx")
    #expect(((try? FileManager.default.contentsOfDirectory(atPath: psx.path)) ?? []).isEmpty)
    #expect(FileManager.default.fileExists(atPath: rig.library.appending(path: "nes/ok.nes").path))
}
@Test func discAlreadyInLibraryUnderOtherNameIsDuplicate() throws {
    let rig = try ImportRig()
    let iso = try gcmImage(rig.drops.appending(path: "Zelda (U).iso"), id: "GZLE", wii: false)
    let (s1, c1) = try rig.importer.analyze([iso])
    _ = try rig.importer.commit(s1, c1)
    try rig.importClrMame("Nintendo - GameCube", "game ( name \"The Legend of Zelda - The Wind Waker (USA)\" serial \"DL-DOL-GZLE-USA\" rom ( name \"z\" sha1 A1 ) )")
    #expect(try rig.importer.analyze([iso]).1.map(\.status) == [.duplicate(.gc)])
}
@Test func differentGameSameNameAndSizeIsNotSkipped() throws {
    let rig = try ImportRig()
    let a = try gcmImage(rig.drops.appending(path: "one/Alpha.iso"), id: "GAAE", wii: false)
    let (s1, c1) = try rig.importer.analyze([a])
    _ = try rig.importer.commit(s1, c1)
    let b = try gcmImage(rig.drops.appending(path: "two/Alpha.iso"), id: "GBBE", wii: false)
    let (s2, c2) = try rig.importer.analyze([b])
    #expect(c2.map(\.status) == [.unverified(.gc)])
    let done = try rig.importer.commit(s2, c2)
    #expect(done[0].destination?.lastPathComponent == "Alpha (2).iso")
}
final class CountingRunner: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var extractions = 0
    var extracted: Int { lock.withLock { extractions } }
    func run(_ executable: String, _ args: [String], input: String?) throws -> String {
        if args.first == "-xf" { lock.withLock { extractions += 1 } }
        return try ProcessRunner().run(executable, args, input: input)
    }
}

@Test func reusedSessionDoesNotReextract() throws {
    let rig = try ImportRig()
    let staging = rig.dir.appending(path: "zipsrc")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    try nesROM().write(to: staging.appending(path: "one.nes"))
    let zip = rig.drops.appending(path: "pack.zip")
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", zip.path, "-C", staging.path, "one.nes"])
    let runner = CountingRunner()
    let importer = Importer(libraryRoot: rig.library, dats: DatStore(paths: rig.paths), runner: runner)
    let (session, _) = try importer.analyze([zip])
    let (again, candidates) = try importer.analyze([zip, try rig.drop("two.nes", nesROM(prg: Data(repeating: 2, count: 16384)))], reusing: session)
    #expect(again === session)
    #expect(runner.extracted == 1)
    #expect(candidates.map(\.status) == [.unverified(.nes), .unverified(.nes)])
}
@Test func archiveLargerThanFreeSpaceIsNotUnpacked() throws {
    let rig = try ImportRig()
    let staging = rig.dir.appending(path: "zipsrc")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    try nesROM().write(to: staging.appending(path: "one.nes"))
    let zip = rig.drops.appending(path: "pack.zip")
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", zip.path, "-C", staging.path, "one.nes"])
    let importer = Importer(libraryRoot: rig.library, dats: DatStore(paths: rig.paths), runner: ProcessRunner(), freeSpace: { _ in 1024 })
    #expect(try importer.analyze([zip]).1.map(\.status) == [.unidentified(reason: "not enough free disk space to unpack")])
}
