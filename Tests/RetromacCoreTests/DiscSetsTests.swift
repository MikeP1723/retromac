// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

private func folder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "discsets-\(UUID().uuidString)/psx")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Two raw 2352-byte sectors with the CD sync pattern and the given mode byte.
@discardableResult
private func rawImage(_ url: URL, mode: UInt8 = 2) throws -> URL {
    var sector = [UInt8](repeating: 0, count: 2352)
    sector[1...10] = ArraySlice(repeating: 0xFF, count: 10)
    sector[15] = mode
    try Data(sector + sector).write(to: url)
    return url
}

/// A cue/bin set named `stem`, with `tracks` bin files.
private func cueSet(_ dir: URL, _ stem: String, tracks: Int = 1) throws {
    let names = tracks == 1 ? ["\(stem).bin"] : (1...tracks).map { "\(stem) (Track \($0)).bin" }
    var sheet = ""
    for (i, name) in names.enumerated() {
        try rawImage(dir.appending(path: name))
        sheet += "FILE \"\(name)\" BINARY\n  TRACK \(String(format: "%02d", i + 1)) MODE2/2352\n    INDEX 01 00:00:00\n"
    }
    try sheet.write(to: dir.appending(path: "\(stem).cue"), atomically: true, encoding: .utf8)
}

private func listing(_ dir: URL) -> [String] {
    (FileManager.default.enumerator(atPath: dir.path)?.allObjects as? [String] ?? []).sorted()
}

@Test func bareBinGetsACue() throws {
    let dir = try folder()
    let bin = try rawImage(dir.appending(path: "Game.bin"))
    let moves = try DiscSets.organize(dir)
    let cue = dir.appending(path: "Game.cue")
    let sheet = try String(contentsOf: cue, encoding: .utf8)
    #expect(sheet.contains("FILE \"Game.bin\" BINARY"))
    #expect(sheet.contains("TRACK 01 MODE2/2352"))
    #expect(moves[bin] == cue)
}
@Test func bareIsoGetsMode1Cue() throws {
    let dir = try folder()
    try Data(count: 2048 * 4).write(to: dir.appending(path: "Game.iso"))
    try DiscSets.organize(dir)
    #expect(try String(contentsOf: dir.appending(path: "Game.cue"), encoding: .utf8).contains("TRACK 01 MODE1/2048"))
}
@Test func mode1RawImageGetsMode1Cue() throws {
    let dir = try folder()
    try rawImage(dir.appending(path: "Saturn.bin"), mode: 1)
    try DiscSets.organize(dir)
    #expect(try String(contentsOf: dir.appending(path: "Saturn.cue"), encoding: .utf8).contains("TRACK 01 MODE1/2352"))
}
@Test func unknownLayoutIsLeftAlone() throws {
    let dir = try folder()
    try Data(count: 1000).write(to: dir.appending(path: "Odd.bin"))
    #expect(try DiscSets.organize(dir).isEmpty)
    #expect(listing(dir) == ["Odd.bin"])
}
@Test func referencedBinIsLeftAlone() throws {
    let dir = try folder()
    try cueSet(dir, "Game")
    #expect(try DiscSets.organize(dir).isEmpty)
    #expect(listing(dir) == ["Game.bin", "Game.cue"])
}
@Test func twoDiscsBecomeOneEntry() throws {
    let dir = try folder()
    try cueSet(dir, "G (Disc 1)")
    try cueSet(dir, "G (Disc 2)")
    let moves = try DiscSets.organize(dir)
    #expect(listing(dir) == ["G.m3u", "G.m3u/G (Disc 1).bin", "G.m3u/G (Disc 1).cue", "G.m3u/G (Disc 2).bin",
                             "G.m3u/G (Disc 2).cue", "G.m3u/G.m3u"])
    #expect(try String(contentsOf: dir.appending(path: "G.m3u/G.m3u"), encoding: .utf8) == "G (Disc 1).cue\nG (Disc 2).cue\n")
    #expect(moves[dir.appending(path: "G (Disc 2).cue")] == dir.appending(path: "G.m3u/G (Disc 2).cue"))
}
@Test func multiTrackCueMovesItsTracks() throws {
    let dir = try folder()
    try cueSet(dir, "G (Disc 1)", tracks: 2)
    try cueSet(dir, "G (Disc 2)")
    try DiscSets.organize(dir)
    #expect(listing(dir).filter { !$0.hasPrefix("G.m3u") }.isEmpty)
    #expect(listing(dir).contains("G.m3u/G (Disc 1) (Track 2).bin"))
}
@Test func loneDiscOneStaysFlat() throws {
    let dir = try folder()
    try cueSet(dir, "G (Disc 1)")
    #expect(try DiscSets.organize(dir).isEmpty)
    #expect(listing(dir) == ["G (Disc 1).bin", "G (Disc 1).cue"])
}
@Test func discNumbersSortNumerically() throws {
    let dir = try folder()
    for n in [10, 2, 1] { try cueSet(dir, "G (Disc \(n))") }
    try DiscSets.organize(dir)
    #expect(try String(contentsOf: dir.appending(path: "G.m3u/G.m3u"), encoding: .utf8)
        == "G (Disc 1).cue\nG (Disc 2).cue\nG (Disc 10).cue\n")
}
@Test func chdPreferredInPlaylist() throws {
    let dir = try folder()
    let set = dir.appending(path: "G.m3u")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    try Data("chd".utf8).write(to: set.appending(path: "G (Disc 1).chd"))
    try cueSet(set, "G (Disc 1)")
    try cueSet(set, "G (Disc 2)")
    try DiscSets.organize(dir)
    #expect(try String(contentsOf: set.appending(path: "G.m3u"), encoding: .utf8) == "G (Disc 1).chd\nG (Disc 2).cue\n")
}
@Test func newDiscJoinsExistingSetFolder() throws {
    let dir = try folder()
    try cueSet(dir, "G (Disc 1)")
    try cueSet(dir, "G (Disc 2)")
    try DiscSets.organize(dir)
    try cueSet(dir, "G (Disc 3)")
    try DiscSets.organize(dir)
    #expect(try String(contentsOf: dir.appending(path: "G.m3u/G.m3u"), encoding: .utf8)
        == "G (Disc 1).cue\nG (Disc 2).cue\nG (Disc 3).cue\n")
}
@Test func organizeIsIdempotent() throws {
    let dir = try folder()
    try cueSet(dir, "G (Disc 1)")
    try cueSet(dir, "G (Disc 2)")
    try rawImage(dir.appending(path: "Bare.bin"))
    try DiscSets.organize(dir)
    let before = listing(dir)
    #expect(try DiscSets.organize(dir).isEmpty)
    #expect(listing(dir) == before)
}
@Test func organizeLibraryTouchesOnlyDiscSystems() throws {
    let root = try folder().deletingLastPathComponent()
    try rawImage(root.appending(path: "psx/A.bin"))
    try FileManager.default.createDirectory(at: root.appending(path: "ps2"), withIntermediateDirectories: true)
    try rawImage(root.appending(path: "ps2/B.bin"))
    DiscSets.organizeLibrary(root)
    #expect(FileManager.default.fileExists(atPath: root.appending(path: "psx/A.cue").path))
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "ps2/B.cue").path))
}
