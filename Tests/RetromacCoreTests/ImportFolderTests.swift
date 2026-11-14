// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(Int, Int)] = []
    var all: [(Int, Int)] { lock.withLock { calls } }
    func record(_ scanned: Int, _ total: Int) { lock.withLock { calls.append((scanned, total)) } }
}

@Test func progressReportsEveryFile() throws {
    let rig = try ImportRig()
    for i in 0..<5 { _ = try rig.drop("folder/g\(i).nes", nesROM(prg: Data(repeating: UInt8(i), count: 16384))) }
    let log = ProgressLog()
    _ = try rig.importer.analyze([rig.drops.appending(path: "folder")], progress: { log.record($0, $1) })
    #expect(log.all.last.map { [$0.0, $0.1] } == [5, 5])
    #expect(zip(log.all, log.all.dropFirst()).allSatisfy { $0.0 <= $1.0 })
}
@Test func summaryCountsByStatusAndSystem() throws {
    let rig = try ImportRig()
    let rom = nesROM()
    try rig.importDat(nesHeader, [("Alpha (USA)", sha1hex(rom.dropFirst(16)))])
    let files = [try rig.drop("a.nes", rom), try rig.drop("copy/a.nes", rom),
                 try rig.drop("b.nes", nesROM(prg: Data(repeating: 7, count: 16384))), try rig.drop("readme.txt", Data("hi".utf8))]
    let (_, candidates) = try rig.importer.analyze(files)
    let summary = Importer.summarize(candidates)
    #expect(summary.identified == 1 && summary.unverified == 1 && summary.duplicates == 1 && summary.skipped == 1)
    #expect(summary.bySystem[.nes] == 2)
}
@Test func bytesToCopyExcludesSessionMoves() throws {
    let rig = try ImportRig()
    let src = rig.dir.appending(path: "zipsrc")
    _ = try isoImage(src.appending(path: "Track 1.bin"), systemCNF: "BOOT = cdrom:\\SCUS_941.63;1\n", raw: true, size: 1 << 20)
    try write("FILE \"Track 1.bin\" BINARY\n  TRACK 01 MODE2/2352\n", to: src.appending(path: "Game.cue"))
    let zip = rig.drops.appending(path: "game.zip")
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", zip.path, "-C", src.path, "Game.cue", "Track 1.bin"])
    let iso = try gcmImage(rig.drops.appending(path: "Zelda.iso"), id: "GZLE", wii: false, size: 8 << 20)
    let (_, candidates) = try rig.importer.analyze([zip, iso])
    #expect(Importer.summarize(candidates).bytesToCopy == 8 << 20)
}
@Test func commitRefusesWhenItWontFit() throws {
    let rig = try ImportRig()
    let importer = Importer(libraryRoot: rig.library, dats: DatStore(paths: rig.paths), runner: ProcessRunner(), freeSpace: { _ in 1024 })
    let rom = nesROM()
    let (session, candidates) = try importer.analyze([try rig.drop("a.nes", rom)])
    #expect(throws: ImportError.notEnoughSpace(needed: Int64(rom.count), free: 1024)) { try importer.commit(session, candidates) }
    #expect(!FileManager.default.fileExists(atPath: rig.library.path))
}
