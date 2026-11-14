// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

struct ImportRig {
    let dir: URL
    let paths: Paths
    let library: URL
    let drops: URL

    init() throws {
        dir = try makeTempDir()
        paths = Paths(home: dir.appending(path: "home"))
        library = dir.appending(path: "Library")
        drops = dir.appending(path: "drops")
        try FileManager.default.createDirectory(at: drops, withIntermediateDirectories: true)
    }

    var importer: Importer { Importer(libraryRoot: library, dats: DatStore(paths: paths), runner: ProcessRunner()) }

    func drop(_ name: String, _ data: Data) throws -> URL {
        let url = drops.appending(path: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
        return url
    }

    func importDat(_ header: String, _ games: [(String, String)]) throws {
        let url = dir.appending(path: "\(UUID().uuidString).dat")
        try datXML(header: header, games: games).write(to: url)
        _ = try DatStore(paths: paths).importDats([url], runner: ProcessRunner())
    }
}

let nesHeader = "Nintendo - Nintendo Entertainment System (Headerless)"

@Test func identifiesFromDatAndCommits() throws {
    let rig = try ImportRig()
    let rom = nesROM()
    try rig.importDat(nesHeader, [("Alpha (USA)", sha1hex(rom.dropFirst(16)))])
    let file = try rig.drop("alpha.nes", rom)
    let (session, candidates) = try rig.importer.analyze([file])
    #expect(candidates.map(\.status) == [.identified(.nes, name: "Alpha (USA)")])
    #expect(candidates[0].destination == rig.library.appending(path: "nes/Alpha (USA).nes"))
    #expect(!FileManager.default.fileExists(atPath: rig.library.path))
    _ = try rig.importer.commit(session, candidates)
    #expect(try Data(contentsOf: rig.library.appending(path: "nes/Alpha (USA).nes")) == rom)
}
@Test func unverifiedWithoutDat() throws {
    let rig = try ImportRig()
    let rom = snesROM(copier: true)
    let (session, candidates) = try rig.importer.analyze([try rig.drop("my game!.smc", rom)])
    #expect(candidates.map(\.status) == [.unverified(.snes)])
    #expect(candidates[0].destination?.lastPathComponent == "my game!.sfc")
    _ = try rig.importer.commit(session, candidates)
    #expect(try Data(contentsOf: rig.library.appending(path: "snes/my game!.sfc")).count == rom.count - 512)
}
@Test func n64V64IsWrittenAsZ64() throws {
    let rig = try ImportRig()
    let (session, candidates) = try rig.importer.analyze([try rig.drop("x.v64", n64ROM(order: .v64))])
    #expect(candidates[0].destination?.lastPathComponent == "x.z64")
    _ = try rig.importer.commit(session, candidates)
    #expect(try Data(contentsOf: rig.library.appending(path: "n64/x.z64")) == n64ROM(order: .z64))
}
@Test func archiveMembersAndFoldersAreImported() throws {
    let rig = try ImportRig()
    let staging = rig.dir.appending(path: "zipsrc")
    try write("", to: staging.appending(path: "a/.keep"))
    try nesROM().write(to: staging.appending(path: "a/one.nes"))
    try FileManager.default.createDirectory(at: staging.appending(path: "b"), withIntermediateDirectories: true)
    try genesisROM().write(to: staging.appending(path: "b/two.md"))
    let zip = rig.drops.appending(path: "pack.zip")
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", zip.path, "-C", staging.path, "a/one.nes", "b/two.md"])
    _ = try rig.drop("folder/sub/three.z64", n64ROM(order: .z64))
    let (_, candidates) = try rig.importer.analyze([zip, rig.drops.appending(path: "folder")])
    #expect(Set(candidates.map(\.source)) == ["pack.zip › a/one.nes", "pack.zip › b/two.md", "folder/sub/three.z64"])
    #expect(Set(candidates.map(\.status)) == [.unverified(.nes), .unverified(.genesis), .unverified(.n64)])
}
@Test func corruptArchiveFailsAloneOthersProceed() throws {
    let rig = try ImportRig()
    let bad = try rig.drop("bad.zip", Data(repeating: 7, count: 1000))
    let good = try rig.drop("good.nes", nesROM())
    let (_, candidates) = try rig.importer.analyze([bad, good])
    guard case .failed(let reason) = candidates[0].status else { Issue.record("expected failed, got \(candidates[0].status)"); return }
    #expect(reason.hasPrefix("couldn't open archive"))
    #expect(candidates[1].status == .unverified(.nes))
}
@Test func duplicatesAreNotCopiedTwice() throws {
    let rig = try ImportRig()
    let one = try rig.drop("one.nes", nesROM()), two = try rig.drop("copy/one.nes", nesROM())
    let (session, candidates) = try rig.importer.analyze([one, two])
    #expect(candidates.map(\.status) == [.unverified(.nes), .duplicate(.nes)])
    _ = try rig.importer.commit(session, candidates)
    #expect(try FileManager.default.contentsOfDirectory(atPath: rig.library.appending(path: "nes").path) == ["one.nes"])
    #expect(try rig.importer.analyze([one]).1.map(\.status) == [.duplicate(.nes)])
}
@Test func differentContentSameNameGetsSuffix() throws {
    let rig = try ImportRig()
    try write("other", to: rig.library.appending(path: "nes/one.nes"))
    let (session, candidates) = try rig.importer.analyze([try rig.drop("one.nes", nesROM())])
    let done = try rig.importer.commit(session, candidates)
    #expect(done[0].destination?.lastPathComponent == "one (2).nes")
    #expect(try read(rig.library.appending(path: "nes/one.nes")) == "other")
}
@Test func largeFilesAreSkippedUnread() throws {
    let rig = try ImportRig()
    func sparse(_ name: String) throws -> URL {
        let url = try rig.drop(name, Data())
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: 100 << 20)
        try handle.close()
        return url
    }
    let (session, candidates) = try rig.importer.analyze([try sparse("movie.mp4"), try sparse("huge.bin")])
    #expect(candidates.map(\.status) == [.notAGame, .unidentified(reason: "too large for a cartridge system")])
    #expect(candidates.allSatisfy { $0.destination == nil })
    _ = try rig.importer.commit(session, candidates)
    #expect(!FileManager.default.fileExists(atPath: rig.library.path))
}
@Test func nonGameAndUnrecognizedFiles() throws {
    let rig = try ImportRig()
    let (session, candidates) = try rig.importer.analyze([try rig.drop("readme.txt", Data("hi".utf8)),
                                                      try rig.drop("x.nes", Data(repeating: 9, count: 4096))])
    #expect(candidates.map(\.status) == [.notAGame, .unidentified(reason: "not a recognized NES, SNES, Genesis or N64 image")])
    #expect(candidates[0].destination == nil)
    _ = try rig.importer.commit(session, candidates)
    #expect(FileManager.default.fileExists(atPath: rig.library.appending(path: "_Unidentified/x.nes").path))
    #expect(try read(rig.library.appending(path: "_Unidentified/x.nes.txt")) == "not a recognized NES, SNES, Genesis or N64 image\n")
}
@Test func originalsAreNeverModified() throws {
    let rig = try ImportRig()
    let files = [try rig.drop("a.nes", nesROM()), try rig.drop("b.v64", n64ROM(order: .v64)), try rig.drop("c.smc", snesROM(copier: true))]
    func fingerprint() throws -> [String] {
        try files.map { "\(sha1hex(try Data(contentsOf: $0)))-\(try FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate]!)" }
    }
    let before = try fingerprint()
    let (session, candidates) = try rig.importer.analyze(files)
    _ = try rig.importer.commit(session, candidates)
    #expect(try fingerprint() == before)
}
@Test func datNameIsSanitized() throws {
    let rig = try ImportRig()
    let rom = nesROM()
    try rig.importDat(nesHeader, [("Evil: ../Name", sha1hex(rom.dropFirst(16)))])
    let (_, candidates) = try rig.importer.analyze([try rig.drop("e.nes", rom)])
    #expect(candidates[0].destination == rig.library.appending(path: "nes/Evil- ..-Name.nes"))
}
func sparseFile(_ url: URL, bytes: UInt64 = 100 << 20) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    FileManager.default.createFile(atPath: url.path, contents: nil)
    let handle = try FileHandle(forWritingTo: url)
    try handle.truncate(atOffset: bytes)
    try handle.close()
}

func folderBytes(_ dir: URL) -> Int {
    let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
    var total = 0
    while let url = walker?.nextObject() as? URL {
        total += (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
    }
    return total
}

@Test func symlinkToLargeFileIsNotLoaded() throws {
    let rig = try ImportRig()
    let target = rig.dir.appending(path: "target.bin")
    try sparseFile(target)
    let link = rig.drops.appending(path: "big.nes")
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
    let (_, candidates) = try rig.importer.analyze([link])
    #expect(candidates.map(\.status) == [.unidentified(reason: "too large for a cartridge system")])
    #expect(candidates[0].destination == nil)
}
@Test func archiveWithHugeMemberIsNotExtracted() throws {
    let rig = try ImportRig()
    let staging = rig.dir.appending(path: "zipsrc")
    try sparseFile(staging.appending(path: "huge.nes"))
    let zip = rig.drops.appending(path: "big.zip")
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", zip.path, "-C", staging.path, "huge.nes"])
    let (session, candidates) = try rig.importer.analyze([zip])
    #expect(candidates.map(\.status) == [.unidentified(reason: "too large for a cartridge system")])
    #expect(candidates[0].source == "big.zip")
    #expect(folderBytes(session.dir) < 1 << 20)
}
@Test func archivesNestOnlyOneLevel() throws {
    let rig = try ImportRig()
    let l3 = rig.dir.appending(path: "l3"), l2 = rig.dir.appending(path: "l2"), l1 = rig.dir.appending(path: "l1")
    try FileManager.default.createDirectory(at: l3, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: l2, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: l1, withIntermediateDirectories: true)
    try nesROM().write(to: l3.appending(path: "deep.nes"))
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", l2.appending(path: "inner.zip").path, "-C", l3.path, "deep.nes"])
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", l1.appending(path: "middle.zip").path, "-C", l2.path, "inner.zip"])
    let outer = rig.drops.appending(path: "outer.zip")
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", outer.path, "-C", l1.path, "middle.zip"])
    let (_, candidates) = try rig.importer.analyze([outer])
    #expect(candidates.map(\.status) == [.failed("archive nested too deeply")])
    #expect(candidates[0].source == "outer.zip › middle.zip › inner.zip")
}
@Test func duplicatesAcrossFilenamesAndAfterDatImport() throws {
    let rig = try ImportRig()
    let rom = nesROM()
    let (s1, c1) = try rig.importer.analyze([try rig.drop("smb.nes", rom)])
    _ = try rig.importer.commit(s1, c1)
    let (_, c2) = try rig.importer.analyze([try rig.drop("Super Mario (copy).nes", rom)])
    #expect(c2.map(\.status) == [.duplicate(.nes)])
    #expect(c2[0].destination == rig.library.appending(path: "nes/smb.nes"))
    try rig.importDat(nesHeader, [("Alpha (USA)", sha1hex(rom.dropFirst(16)))])
    let (_, c3) = try rig.importer.analyze([try rig.drop("again.nes", rom)])
    #expect(c3.map(\.status) == [.duplicate(.nes)])
}
@Test func unidentifiedDuplicatesAreCaught() throws {
    let rig = try ImportRig()
    let junk = Data(repeating: 9, count: 4096)
    let (s1, c1) = try rig.importer.analyze([try rig.drop("mystery.bin", junk), try rig.drop("again/mystery.bin", junk)])
    #expect(c1.map(\.status) == [.unidentified(reason: Importer.unrecognized), .duplicate(nil)])
    _ = try rig.importer.commit(s1, c1)
    let (_, c2) = try rig.importer.analyze([try rig.drop("renamed.bin", junk)])
    #expect(c2.map(\.status) == [.duplicate(nil)])
    #expect(try FileManager.default.contentsOfDirectory(atPath: rig.library.appending(path: "_Unidentified").path).sorted()
        == ["mystery.bin", "mystery.bin.txt"])
}
