// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore
import NetFS

final class FakeMounter: ShareMounter, @unchecked Sendable {
    private let lock = NSLock()
    private var _mounts: [(remount: URL, mountPoint: URL)]
    private var _calls: [URL] = []
    var calls: [URL] { lock.withLock { _calls } }
    let error: NetworkShareError?
    let mountPoint: URL

    init(mounts: [(URL, URL)] = [], mountPoint: URL, error: NetworkShareError? = nil) {
        _mounts = mounts.map { (remount: $0.0, mountPoint: $0.1) }
        self.mountPoint = mountPoint
        self.error = error
    }

    func mount(_ share: URL) throws -> URL {
        lock.withLock { _calls.append(share) }
        if let error { throw error }
        lock.withLock { _mounts.append((remount: share, mountPoint: mountPoint)) }
        return mountPoint
    }

    func mounted() -> [(remount: URL, mountPoint: URL)] { lock.withLock { _mounts } }
}

private func library(_ text: String) -> NetworkLibrary {
    NetworkLibrary(url: NetworkLibrary.parse(text)!, localLibrary: URL(filePath: "/x"))
}

@Test func alreadyMountedUnderAnotherNameIsReused() throws {
    let tmp = try makeTempDir(), point = tmp.appending(path: "media-1")
    try FileManager.default.createDirectory(at: point.appending(path: "roms"), withIntermediateDirectories: true)
    let mounter = FakeMounter(mounts: [(URL(string: "smb://MIKE@NAS/Media")!, point)], mountPoint: tmp.appending(path: "unused"))
    #expect(try NetworkShare(mounter: mounter).libraryFolder(for: library("smb://nas/media/roms")).path == point.appending(path: "roms").path)
    #expect(mounter.calls.isEmpty)
}
@Test func mountsWhenNotMounted() throws {
    let point = try makeTempDir().appending(path: "media")
    try FileManager.default.createDirectory(at: point.appending(path: "retro/roms"), withIntermediateDirectories: true)
    let mounter = FakeMounter(mountPoint: point)
    #expect(try NetworkShare(mounter: mounter).libraryFolder(for: library("smb://nas/media/retro/roms")).path == point.appending(path: "retro/roms").path)
    #expect(mounter.calls.map(\.absoluteString) == ["smb://nas/media"])
}
@Test func missingSubfolderIsReported() throws {
    let point = try makeTempDir()
    #expect(throws: NetworkShareError.folderMissing("roms")) {
        try NetworkShare(mounter: FakeMounter(mountPoint: point)).libraryFolder(for: library("smb://nas/media/roms"))
    }
}
@Test func cancelledLoginIsReported() throws {
    let mounter = FakeMounter(mountPoint: try makeTempDir(), error: .cancelled)
    #expect(throws: NetworkShareError.cancelled) { try NetworkShare(mounter: mounter).libraryFolder(for: library("smb://nas/media")) }
}

@Test func finderBonjourMountMatchesAPlainHostName() throws {
    // Finder mounts a browsed server as smb://GUEST:@petersoft._smb._tcp.local/roms (seen on Mike's Mac).
    let point = try makeTempDir().appending(path: "roms")
    try FileManager.default.createDirectory(at: point, withIntermediateDirectories: true)
    for typed in ["smb://petersoft.local/roms", "smb://petersoft/roms", "smb://PeterSoft._smb._tcp.local/ROMS"] {
        let mounter = FakeMounter(mounts: [(URL(string: "smb://GUEST:@petersoft._smb._tcp.local/roms")!, point)], mountPoint: point)
        #expect(try NetworkShare(mounter: mounter).libraryFolder(for: library(typed)).path == point.path, "\(typed)")
        #expect(mounter.calls.isEmpty, "\(typed)")
    }
}

@Test func onlyTheAppMayShowTheServerLogin() {
    // The console agent mounts with no UI: its play notification is unauthenticated, so any local process
    // could otherwise pop a server login prompt (over ES-DE at login). retromac.app's Reconnect shows it.
    #expect(NetFSMounter.openOptions(allowUI: true)[kNAUIOptionKey as String] as? String == kNAUIOptionAllowUI as String)
    #expect(NetFSMounter.openOptions(allowUI: false)[kNAUIOptionKey as String] as? String == kNAUIOptionNoUI as String)
}
