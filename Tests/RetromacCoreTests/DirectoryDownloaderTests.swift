// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func directoryDownloaderServesHostAndPath() async throws {
    let root = try makeTempDir()
    try write("index", to: root.appending(path: "buildbot.libretro.com/nightly/apple/osx/arm64/latest/.index-extended"))
    let dest = root.appending(path: "out")
    try await DirectoryDownloader(root: root).download(CoreIndex.url, to: dest)
    #expect(try read(dest) == "index")
}
@Test func directoryDownloaderMissingFileThrows() async throws {
    let root = try makeTempDir()
    await #expect(throws: (any Error).self) {
        try await DirectoryDownloader(root: root).download(URL(string: "https://github.com/x")!, to: root.appending(path: "o"))
    }
}
