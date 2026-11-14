// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func updateCacheRoundTrips() throws {
    let paths = Paths(home: try makeTempDir())
    let index = CoreIndex.parse("2026-11-20 deadbeef mesen_libretro.dylib.zip\n")
    try UpdateCache(paths: paths).save(manifest: .fixture(), coreIndex: index)
    let loaded = try #require(UpdateCache(paths: paths).load())
    #expect(loaded.manifest == .fixture())
    #expect(loaded.coreIndex == index)
}
@Test func updateCacheEmptyWhenNeverSaved() throws {
    #expect(UpdateCache(paths: Paths(home: try makeTempDir())).load() == nil)
}
