// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

func makeTempDir() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "retromac-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func write(_ s: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try s.write(to: url, atomically: true, encoding: .utf8)
}

func read(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }

@Test func snapshotAndRestoreRoundTrip() throws {
    let home = try makeTempDir()
    let file = home.appending(path: "x/a.cfg")
    try write("1", to: file)
    let store = BackupStore(root: home.appending(path: "retromac/backups"), home: home)
    let snap = try #require(try store.snapshot([file]))
    #expect(try read(snap.appending(path: "x/a.cfg")) == "1")
    try write("2", to: file)
    try store.restore(snap)
    #expect(try read(file) == "1")
}
@Test func snapshotOfNoExistingFilesIsNil() throws {
    let home = try makeTempDir()
    let root = home.appending(path: "retromac/backups")
    let store = BackupStore(root: root, home: home)
    #expect(try store.snapshot([home.appending(path: "missing")]) == nil)
    #expect(!FileManager.default.fileExists(atPath: root.path))
}
@Test func listIsNewestFirst() throws {
    let home = try makeTempDir()
    let file = home.appending(path: "a.cfg")
    try write("1", to: file)
    let root = home.appending(path: "retromac/backups")
    let older = try BackupStore(root: root, home: home, now: { Date(timeIntervalSince1970: 1_000_000) }).snapshot([file])
    let newer = try BackupStore(root: root, home: home, now: { Date(timeIntervalSince1970: 2_000_000) }).snapshot([file])
    #expect(try BackupStore(root: root, home: home).list().map(\.lastPathComponent)
        == [newer!.lastPathComponent, older!.lastPathComponent])
}
