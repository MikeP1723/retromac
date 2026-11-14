// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

/// Serves a one-game clrmamepro DAT for each requested system at its libretro URL.
func serveDats(_ systems: [SystemID], from dir: URL, with downloader: FixtureDownloader) throws {
    let headers = Dictionary(uniqueKeysWithValues: DatParser.systems.map { ($1, $0) })
    for system in systems {
        let file = dir.appending(path: "\(system.rawValue)-\(UUID().uuidString).dat")
        try clrmame(headers[system]!, "game ( name \"\(system.rawValue) game\" serial \"AB-123\" rom ( name \"x\" sha1 \(system.rawValue)00 ) )").write(to: file)
        downloader.serve(file, at: DatUpdater.url(for: system)!)
    }
}

@Test func updatesEverySource() async throws {
    let home = try makeTempDir()
    let downloader = FixtureDownloader()
    try serveDats(Array(DatUpdater.sources.keys), from: home, with: downloader)
    let store = DatStore(paths: Paths(home: home))
    let results = await DatUpdater.update(store: store, downloader: downloader, runner: ProcessRunner())
    #expect(results.count == 10)
    #expect(results.allSatisfy { if case .success = $0.1 { true } else { false } })
    #expect(store.load().count == 10)
}
@Test func partialFailureKeepsPreviousIndex() async throws {
    let home = try makeTempDir()
    let store = DatStore(paths: Paths(home: home))
    let old = home.appending(path: "old.dat")
    try clrmame("Sony - PlayStation", "game ( name \"Old\" serial \"SLUS-00001\" rom ( name \"x\" sha1 AA ) )").write(to: old)
    _ = try store.importDats([old], runner: ProcessRunner())
    let before = try Data(contentsOf: Paths(home: home).dats.appending(path: "psx.json"))

    let downloader = FixtureDownloader()
    try serveDats(DatUpdater.sources.keys.filter { $0 != .psx }, from: home, with: downloader)
    let results = await DatUpdater.update(store: store, downloader: downloader, runner: ProcessRunner())
    let psx = try #require(results.first { $0.0 == .psx })
    if case .success = psx.1 { Issue.record("psx should have failed") }
    #expect(try Data(contentsOf: Paths(home: home).dats.appending(path: "psx.json")) == before)
    #expect(store.load()[.ps2]?.entries.isEmpty == false)
}
@Test func urlsAreEncoded() {
    #expect(DatUpdater.url(for: .ps2)?.absoluteString
        == "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/redump/Sony%20-%20PlayStation%202.dat")
    #expect(DatUpdater.url(for: .switch) == nil)
    #expect(DatUpdater.sources[.wiiu] == nil)
}
