// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

/// Stands in for chdman: `createcd` writes a stub to its `-o` path; either step can be made to fail.
final class FakeChdman: CommandRunner, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [[String]] = []
    var calls: [[String]] { lock.withLock { _calls } }
    let failing: String?

    init(failing: String? = nil) { self.failing = failing }

    func run(_ executable: String, _ args: [String], input: String?) throws -> String {
        lock.withLock { _calls.append([URL(filePath: executable).lastPathComponent] + args) }
        if args.first == "createcd" || args.first == "createdvd", let out = args.firstIndex(of: "-o").map({ args[$0 + 1] }) {
            try Data("MComprHD".utf8).write(to: URL(filePath: out))
        }
        if args.first == failing { throw InstallError.commandFailed(executable, 1, "\(failing!) failed") }
        return ""
    }
}

private func discFolder() throws -> URL {
    let dir = try makeTempDir().appending(path: "Library/psx")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func twoTrackSet(_ dir: URL, _ stem: String) throws -> URL {
    for n in 1...2 { try Data(count: 2352 * 2).write(to: dir.appending(path: "\(stem) (Track \(n)).bin")) }
    let cue = dir.appending(path: "\(stem).cue")
    try """
        FILE "\(stem) (Track 1).bin" BINARY
          TRACK 01 MODE2/2352
            INDEX 01 00:00:00
        FILE "\(stem) (Track 2).bin" BINARY
          TRACK 02 AUDIO
            INDEX 01 00:00:00

        """.write(to: cue, atomically: true, encoding: .utf8)
    return cue
}

private func names(_ dir: URL) throws -> [String] {
    try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
}

@Test func convertRunsCreateThenVerifyAndRemovesOriginals() throws {
    let dir = try discFolder()
    let cue = try twoTrackSet(dir, "Game")
    let runner = FakeChdman()
    let chd = try ChdTool(runner: runner, chdman: URL(filePath: "/opt/homebrew/bin/chdman")).convert(cue: cue)
    #expect(chd == dir.appending(path: "Game.chd"))
    #expect(try names(dir) == ["Game.chd"])
    #expect(runner.calls.count == 2)
    let tmp = try #require(runner.calls.first?.last)
    #expect(runner.calls[0] == ["chdman", "createcd", "-i", cue.path, "-o", tmp])
    #expect(runner.calls[1] == ["chdman", "verify", "-i", tmp])
    #expect(URL(filePath: tmp).lastPathComponent.hasPrefix(".retromac-") && tmp.hasSuffix(".chd"))
}
@Test func failedConversionKeepsOriginals() throws {
    for step in ["createcd", "verify"] {
        let dir = try discFolder()
        let cue = try twoTrackSet(dir, "Game")
        #expect(throws: (any Error).self) { try ChdTool(runner: FakeChdman(failing: step)).convert(cue: cue) }
        #expect(try names(dir) == ["Game (Track 1).bin", "Game (Track 2).bin", "Game.cue"], "after \(step) failed")
    }
}
@Test func existingChdIsNotOverwritten() throws {
    let dir = try discFolder()
    let cue = try twoTrackSet(dir, "Game")
    try Data("theirs".utf8).write(to: dir.appending(path: "Game.chd"))
    let runner = FakeChdman()
    #expect(throws: (any Error).self) { try ChdTool(runner: runner).convert(cue: cue) }
    #expect(runner.calls.isEmpty)
    #expect(try Data(contentsOf: dir.appending(path: "Game.chd")) == Data("theirs".utf8))
}
@Test func convertedSetFolderPlaylistSwitchesToChd() throws {
    let dir = try discFolder()
    let set = dir.appending(path: "G.m3u")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    let first = try twoTrackSet(set, "G (Disc 1)")
    _ = try twoTrackSet(set, "G (Disc 2)")
    try DiscSets.organize(dir)
    _ = try ChdTool(runner: FakeChdman()).convert(cue: first)
    try DiscSets.organize(dir)
    #expect(try String(contentsOf: set.appending(path: "G.m3u"), encoding: .utf8) == "G (Disc 1).chd\nG (Disc 2).cue\n")
}
@Test func convertibleFindsCuesInSetFolders() throws {
    let dir = try discFolder()
    let library = dir.deletingLastPathComponent()
    _ = try twoTrackSet(dir, "Flat")
    let set = dir.appending(path: "G.m3u")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    _ = try twoTrackSet(set, "G (Disc 1)")
    try FileManager.default.createDirectory(at: library.appending(path: "ps2"), withIntermediateDirectories: true)
    _ = try twoTrackSet(library.appending(path: "ps2"), "NotYet")
    #expect(ChdTool.convertible(in: library).map(\.lastPathComponent) == ["Flat.cue", "G (Disc 1).cue"])
}
@Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/chdman")))
func realChdmanRoundTrip() throws {
    let dir = try discFolder()
    var sector = [UInt8](repeating: 0, count: 2352)
    sector[1...10] = ArraySlice(repeating: 0xFF, count: 10)
    sector[15] = 2
    try Data(Array(repeating: sector, count: 300).flatMap { $0 }).write(to: dir.appending(path: "Tiny.bin"))
    let cue = dir.appending(path: "Tiny.cue")
    try "FILE \"Tiny.bin\" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n".write(to: cue, atomically: true, encoding: .utf8)
    let chd = try ChdTool(runner: ProcessRunner()).convert(cue: cue)
    #expect(try names(dir) == ["Tiny.chd"])
    // CHD contents are compressed; retromac can't read their headers (see DiscSniffer).
    if case .failure? = DiscSniffer.sniff(chd) {} else { Issue.record("expected CHD to be reported unidentifiable") }
}
@Test func leftoverPartialsAreRemoved() throws {
    let dir = try discFolder()
    let library = dir.deletingLastPathComponent()
    let set = dir.appending(path: "G.m3u")
    try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
    for url in [dir.appending(path: ".retromac-1.chd"), set.appending(path: ".retromac-2.chd")] { try Data("x".utf8).write(to: url) }
    try Data("keep".utf8).write(to: dir.appending(path: ".other"))
    _ = try twoTrackSet(dir, "Game")
    ChdTool.removeLeftovers(in: library)
    #expect(try names(dir) == [".other", "G.m3u", "Game (Track 1).bin", "Game (Track 2).bin", "Game.cue"])
    #expect(try names(set).isEmpty)
}
@Test func cueWithChdBesideItIsNotConvertible() throws {
    let dir = try discFolder()
    _ = try twoTrackSet(dir, "Game")
    _ = try twoTrackSet(dir, "Other")
    try Data("MComprHD".utf8).write(to: dir.appending(path: "Game.chd"))
    #expect(ChdTool.convertible(in: dir.deletingLastPathComponent()).map(\.lastPathComponent) == ["Other.cue"])
}

@Test func trackSharedWithAnotherCueIsKept() throws {
    let dir = try discFolder()
    try Data(count: 2352 * 2).write(to: dir.appending(path: "Game.bin"))
    let sheet = "FILE \"Game.bin\" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n"
    try sheet.write(to: dir.appending(path: "Game.cue"), atomically: true, encoding: .utf8)
    try sheet.write(to: dir.appending(path: "Game (Alt).cue"), atomically: true, encoding: .utf8)
    _ = try ChdTool(runner: FakeChdman(), chdman: URL(filePath: "/opt/homebrew/bin/chdman")).convert(cue: dir.appending(path: "Game.cue"))
    #expect(try names(dir) == ["Game (Alt).cue", "Game.bin", "Game.chd"])
}

@Test func trackNotNamedAfterTheCueIsKept() throws {
    let dir = try discFolder()
    try Data(count: 2352 * 2).write(to: dir.appending(path: "Other Game.bin"))
    try "FILE \"Other Game.bin\" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n"
        .write(to: dir.appending(path: "Game.cue"), atomically: true, encoding: .utf8)
    _ = try ChdTool(runner: FakeChdman(), chdman: URL(filePath: "/opt/homebrew/bin/chdman")).convert(cue: dir.appending(path: "Game.cue"))
    #expect(try names(dir) == ["Game.chd", "Other Game.bin"])
}

private func ps2Folder() throws -> URL {
    let dir = try makeTempDir().appending(path: "Library/ps2")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Test func ps2IsoConvertsWithCreatedvd() throws {
    let dir = try ps2Folder()
    let iso = dir.appending(path: "Game.iso")
    try Data(count: 2048 * 4).write(to: iso)
    let runner = FakeChdman()
    let chd = try ChdTool(runner: runner, chdman: URL(filePath: "/opt/homebrew/bin/chdman")).convert(iso: iso)
    #expect(chd == dir.appending(path: "Game.chd"))
    #expect(try names(dir) == ["Game.chd"])
    let tmp = try #require(runner.calls.first?.last)
    #expect(runner.calls == [["chdman", "createdvd", "-i", iso.path, "-o", tmp], ["chdman", "verify", "-i", tmp]])
}
@Test func failedPs2ConversionKeepsTheIso() throws {
    let dir = try ps2Folder()
    let iso = dir.appending(path: "Game.iso")
    try Data(count: 2048).write(to: iso)
    #expect(throws: InstallError.self) {
        try ChdTool(runner: FakeChdman(failing: "verify"), chdman: URL(filePath: "/opt/homebrew/bin/chdman")).convert(iso: iso)
    }
    #expect(try names(dir) == ["Game.iso"])
}
@Test func convertibleListsPs2Isos() throws {
    let dir = try ps2Folder(), root = dir.deletingLastPathComponent()
    try Data(count: 2048).write(to: dir.appending(path: "A.iso"))
    try Data(count: 2048).write(to: dir.appending(path: "B.iso"))
    try Data(count: 16).write(to: dir.appending(path: "B.chd"))
    #expect(ChdTool.convertible(in: root).map(\.lastPathComponent) == ["A.iso"])
    try Data(count: 16).write(to: dir.appending(path: ".retromac-x.chd"))
    ChdTool.removeLeftovers(in: root)
    #expect(!FileManager.default.fileExists(atPath: dir.appending(path: ".retromac-x.chd").path))
}
@Test(.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/chdman")))
func realChdmanDvdRoundTrip() throws {
    let dir = try ps2Folder()
    let iso = dir.appending(path: "Tiny.iso")
    try Data((0..<(2048 * 1024)).map { UInt8(truncatingIfNeeded: $0 &* 13) }).write(to: iso)
    _ = try ChdTool(runner: ProcessRunner()).convert(iso: iso)
    #expect(try names(dir) == ["Tiny.chd"])
}
