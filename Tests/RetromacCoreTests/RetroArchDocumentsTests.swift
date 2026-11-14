// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func savesStatesAndPlaylistsMoveOutOfDocuments() throws {
    let paths = Paths(home: try makeTempDir()), docs = paths.retroarchDocuments
    try write("save", to: docs.appending(path: "saves/Mesen/Game.srm"))
    try write("state", to: docs.appending(path: "states/Mesen/Game.state"))
    try write("lpl", to: docs.appending(path: "playlists/builtin/content_history.lpl"))
    try write("bios", to: docs.appending(path: "system/scph5501.bin"))
    let left = try RetroArchDocuments.moveIntoSupport(paths)
    #expect(left.isEmpty)
    #expect(try read(paths.retroarchSupport.appending(path: "saves/Mesen/Game.srm")) == "save")
    #expect(try read(paths.retroarchSupport.appending(path: "states/Mesen/Game.state")) == "state")
    #expect(try read(paths.retroarchSupport.appending(path: "playlists/builtin/content_history.lpl")) == "lpl")
    #expect(try read(paths.retroarchSystem.appending(path: "scph5501.bin")) == "bios")
    #expect(!FileManager.default.fileExists(atPath: docs.path))
}

@Test func fileAlreadyInSupportKeepsBothCopies() throws {
    let paths = Paths(home: try makeTempDir()), docs = paths.retroarchDocuments
    try write("old", to: docs.appending(path: "saves/Mesen/Game.srm"))
    try write("new", to: paths.retroarchSupport.appending(path: "saves/Mesen/Game.srm"))
    let left = try RetroArchDocuments.moveIntoSupport(paths)
    #expect(left == ["saves/Mesen/Game.srm"])
    #expect(try read(paths.retroarchSupport.appending(path: "saves/Mesen/Game.srm")) == "new")
    #expect(try read(docs.appending(path: "saves/Mesen/Game.srm")) == "old")
}

@Test func unrelatedFilesInDocumentsAreLeftAlone() throws {
    let paths = Paths(home: try makeTempDir()), docs = paths.retroarchDocuments
    try write("mine", to: docs.appending(path: "notes.txt"))
    try write("save", to: docs.appending(path: "saves/Game.srm"))
    _ = try RetroArchDocuments.moveIntoSupport(paths)
    #expect(try read(docs.appending(path: "notes.txt")) == "mine")
    #expect(!FileManager.default.fileExists(atPath: docs.appending(path: "saves").path))
}

@Test func nothingInDocumentsIsANoOp() throws {
    let paths = Paths(home: try makeTempDir())
    #expect(try RetroArchDocuments.moveIntoSupport(paths).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: paths.retroarchSupport.path))
}

@Test func applyMovesSavesBeforePointingRetroArchAtThem() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    try write("save", to: paths.retroarchDocuments.appending(path: "saves/Game.srm"))
    _ = try Applier(paths: paths, apps: appNames, isRunning: { _ in false }).apply(try renderInto(home))
    #expect(try read(paths.retroarchSupport.appending(path: "saves/Game.srm")) == "save")
    #expect(try read(paths.retroarchConfig).contains("savefile_directory = \"\(paths.retroarchSupport.appending(path: "saves").path)\""))
}

@Test func applyWhileRetroArchRunsMovesNothing() throws {
    let home = try makeTempDir(), paths = Paths(home: home)
    try write("save", to: paths.retroarchDocuments.appending(path: "saves/Game.srm"))
    let applier = Applier(paths: paths, apps: appNames, isRunning: { $0 == "RetroArch.app" })
    #expect(throws: ApplyError.appRunning("RetroArch.app")) { try applier.apply(try renderInto(home)) }
    #expect(try read(paths.retroarchDocuments.appending(path: "saves/Game.srm")) == "save")
}

@Test func retroarchUserDataStaysUnderApplicationSupport() throws {
    let keys = retroarchKeys(try render(profile()))
    let support = "/tmp/h/Library/Application Support/RetroArch"
    #expect(keys["savefile_directory"] == "\(support)/saves")
    #expect(keys["savestate_directory"] == "\(support)/states")
    #expect(keys["playlist_directory"] == "\(support)/playlists")
    #expect(keys["content_history_path"] == "\(support)/playlists/builtin/content_history.lpl")
    #expect(keys["content_favorites_path"] == "\(support)/playlists/builtin/content_favorites.lpl")
    #expect(keys["log_dir"] == "\(support)/logs")
    #expect(keys["recording_output_directory"] == "\(support)/records")
}
