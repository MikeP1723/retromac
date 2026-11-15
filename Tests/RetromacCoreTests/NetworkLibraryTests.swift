// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

private func lib(_ text: String) throws -> NetworkLibrary {
    NetworkLibrary(url: try #require(NetworkLibrary.parse(text)), localLibrary: URL(filePath: "/x"))
}

@Test func addressesParseToShareAndSubfolder() throws {
    let a = try lib("  SMB://nas/media/roms/  ")
    #expect(a.share.absoluteString == "smb://nas/media" && a.subpath == "roms")
    let b = try lib("smb://mike@nas/My Games")
    #expect(b.share.absoluteString == "smb://mike@nas/My%20Games" && b.subpath == "")
    let c = try lib("smb://nas/media/retro/roms")
    #expect(c.share.absoluteString == "smb://nas/media" && c.subpath == "retro/roms")
    #expect(NetworkLibrary.parse("smb://nas") == nil && NetworkLibrary.parse("smb://nas/") == nil)
    #expect(NetworkLibrary.parse("afp://nas/media") == nil && NetworkLibrary.parse("/Volumes/media") == nil && NetworkLibrary.parse("") == nil)
}
@Test func olderProfilesHaveNoNetworkLibrary() throws {
    let url = try makeTempDir().appending(path: "profile.json")
    var p = profile()
    try p.save(to: url)
    p = try Profile.load(from: url)
    #expect(p.networkLibrary == nil && !p.isLibraryReadOnly)
    #expect(!(try String(contentsOf: url, encoding: .utf8)).contains("networkLibrary"))
}
@Test func turningItOffRestoresTheExactLocalLibrary() {
    var p = profile(library: URL(filePath: "/Volumes/External/Games"))
    p.useNetworkLibrary(URL(string: "smb://nas/media/roms")!, at: URL(filePath: "/Volumes/media/roms"))
    #expect(p.isLibraryReadOnly && p.libraryRoot.path == "/Volumes/media/roms")
    #expect(p.networkLibrary?.localLibrary.path == "/Volumes/External/Games")
    p.useNetworkLibrary(URL(string: "smb://nas/other")!, at: URL(filePath: "/Volumes/other"))  // switching shares keeps the original
    p.useLocalLibrary()
    #expect(!p.isLibraryReadOnly && p.libraryRoot.path == "/Volumes/External/Games")
}
@Test func aPasswordInTheAddressIsNeverKept() throws {
    // retromac stores no server passwords: macOS's login prompt and the Keychain handle them.
    let url = try #require(NetworkLibrary.parse("smb://mike:secret@nas/media/roms"))
    #expect(!url.absoluteString.contains("secret"))
    #expect(url.absoluteString == "smb://mike@nas/media/roms")
    #expect(try #require(NetworkLibrary.parse("smb://:secret@nas/media")).absoluteString == "smb://nas/media")
}
@Test func noConsoleFoldersAreCreatedOnTheShare() throws {
    var p = profile(systems: [.nes, .snes])
    p.useNetworkLibrary(URL(string: "smb://nas/roms")!, at: URL(filePath: "/Volumes/roms"))
    #expect(!(try render(p)).contains { $0.kind == .directory && $0.url.path.hasPrefix("/Volumes/roms") })
    #expect((try render(profile(systems: [.nes]))).contains { $0.kind == .directory && $0.url.lastPathComponent == "nes" })
}
@Test func networkLibraryIsNeverResetWhenOffline() throws {
    let paths = Paths(home: try makeTempDir())
    var p = profile()
    p.useNetworkLibrary(URL(string: "smb://nas/roms")!, at: URL(filePath: "/Volumes/not-mounted/roms"))
    #expect(p.resolvingLibrary(paths: paths) == p)
}
@Test func missingLocalLibraryStillResets() throws {
    let paths = Paths(home: try makeTempDir())
    let p = profile(library: URL(filePath: "/nowhere/Library"))
    #expect(p.resolvingLibrary(paths: paths).libraryRoot == paths.defaultLibraryRoot)
    let legacy = profile(library: LegacyPaths(home: paths.home).root.appending(path: "Library"))
    #expect(legacy.resolvingLibrary(paths: paths).libraryRoot == paths.defaultLibraryRoot)
}
@Test func aPasswordWithSlashesOrAtSignsIsNeverKept() throws {
    #expect(try #require(NetworkLibrary.parse("smb://mike:pa/ss@nas/media/roms")).absoluteString == "smb://mike@nas/media/roms")
    #expect(try #require(NetworkLibrary.parse("smb://mike:p@ss@nas/media")).absoluteString == "smb://mike@nas/media")
}
@Test func consoleFoldersAreMatchedByESDEName() throws {
    let dir = try makeTempDir()
    for name in ["SNES", "psx", "Nintendo 64", ".Trashes"] {
        try FileManager.default.createDirectory(at: dir.appending(path: name), withIntermediateDirectories: true)
    }
    try write("hi", to: dir.appending(path: "readme.txt"))
    let result = NetworkLibrary.consoleFolders(in: dir)
    #expect(result.found == [.snes, .psx])
    #expect(result.other == ["Nintendo 64"])
}
@Test func anAddressThatHidesItsHostIsRejected() {
    // What retromac reads as the host must be what Foundation's URL reads as the host.
    #expect(NetworkLibrary.parse("smb://nas?x@evil/share") == nil)
    #expect(NetworkLibrary.parse("smb://nas#x@evil/share") == nil)
    #expect(NetworkLibrary.parse("smb://mike@nas?x/share") == nil)
    let url = NetworkLibrary.parse("smb://mike@nas/media")
    #expect(url?.host() == "nas" && url?.user() == "mike")
}
@Test func anAddressWithoutAHostIsRejected() {
    #expect(NetworkLibrary.parse("smb://:445/share") == nil)
    #expect(NetworkLibrary.parse("smb://mike@:445/share") == nil)
}
@Test func aReadOnlyLibraryNeverTakesAnImport() throws {
    // A queued "Import All" after switching to the share must copy nothing there.
    let rig = try ImportRig()
    let file = try rig.drop("game.nes", Data("NES\u{1A}".utf8) + Data(count: 16 + 16384))
    let importer = Importer(libraryRoot: rig.library, dats: DatStore(paths: rig.paths), runner: ProcessRunner(), readOnly: true)
    let (session, candidates) = try importer.analyze([file])
    #expect(throws: ImportError.readOnlyLibrary) { try importer.commit(session, candidates) }
    #expect(!FileManager.default.fileExists(atPath: rig.library.path))
}
@Test func nothingOnAReadOnlyLibraryIsOfferedForShrinking() throws {
    // Shrink re-reads its list after installing chdman; by then the library may be the share.
    let root = try makeTempDir()
    try write("FILE \"G.bin\" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n", to: root.appending(path: "psx/G.cue"))
    #expect(ChdTool.convertible(in: root).count == 1)
    #expect(ChdTool.convertible(in: root, readOnly: true).isEmpty)
}
@Test func mountPointComparisonIgnoresATrailingSlash() {
    var p = profile(library: URL(filePath: "/Volumes/roms/", directoryHint: .isDirectory))
    p.useNetworkLibrary(URL(string: "smb://nas/roms")!, at: URL(filePath: "/Volumes/roms/", directoryHint: .isDirectory))
    #expect(p.libraryIs(URL(filePath: "/Volumes/roms")))
    #expect(!p.libraryIs(URL(filePath: "/Volumes/roms-1")))
}
@Test func aBrowsedFolderBecomesItsShareAddress() {
    // Picked in the folder panel: /Volumes/roms/retro on Finder's guest mount of petersoft's roms share.
    let address = NetworkLibrary.address(for: URL(filePath: "/Volumes/roms/retro/snes", directoryHint: .isDirectory),
                                         volume: URL(filePath: "/Volumes/roms", directoryHint: .isDirectory),
                                         remount: URL(string: "smb://GUEST:@petersoft._smb._tcp.local/roms")!)
    #expect(address?.absoluteString == "smb://GUEST@petersoft._smb._tcp.local/roms/retro/snes")
    let root = NetworkLibrary.address(for: URL(filePath: "/Volumes/My Games", directoryHint: .isDirectory),
                                      volume: URL(filePath: "/Volumes/My Games", directoryHint: .isDirectory),
                                      remount: URL(string: "smb://nas/My%20Games")!)
    #expect(root?.absoluteString == "smb://nas/My%20Games")
    #expect(NetworkLibrary.address(for: URL(filePath: "/Volumes/x/a"), volume: URL(filePath: "/Volumes/x"),
                                   remount: URL(string: "afp://nas/x")!) == nil)
}
