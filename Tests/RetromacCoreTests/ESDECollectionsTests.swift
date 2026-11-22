// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func romPathEntriesPointAtTheLibrary() {
    // Saved while ROMDirectory was the library; ES-DE's ROMDirectory is now an empty folder.
    let saved = "%ROMPATH%/snes/Chrono Trigger.sfc\n/Volumes/roms/n64/Mario.z64\n%ROMPATH%/psx/FF7/FF7.m3u\n"
    #expect(ESDECollections.merge(existing: saved, library: "/Volumes/roms") ==
            "/Volumes/roms/snes/Chrono Trigger.sfc\n/Volumes/roms/n64/Mario.z64\n/Volumes/roms/psx/FF7/FF7.m3u\n")
}

@Test func collectionWithoutRomPathIsUntouched() {
    let saved = "/Volumes/roms/snes/Zelda.sfc\n"
    #expect(ESDECollections.merge(existing: saved, library: "/Volumes/roms") == saved)
    #expect(ESDECollections.merge(existing: "", library: "/Volumes/roms") == "")
}

@Test func customCollectionsAreRendered() throws {
    let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: home) }
    let paths = Paths(home: home)
    let dir = paths.esdeRoot.appending(path: "collections")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for name in ["custom-Favs.cfg", "custom-Party Games.cfg", "notes.txt"] {
        try "".write(to: dir.appending(path: name), atomically: true, encoding: .utf8)
    }
    let p = profile(library: URL(filePath: "/Volumes/roms"))
    let files = ProfileRenderer.render(p, manifest: .fixture(), rules: try DisplayRules.bundled(), paths: paths, chip: "Apple M4 Pro")
    let collections = files.filter { if case .esdeCollection = $0.kind { true } else { false } }
    #expect(collections.map(\.url.lastPathComponent) == ["custom-Favs.cfg", "custom-Party Games.cfg"])
    #expect(collections.allSatisfy { $0.kind == .esdeCollection(library: "/Volumes/roms") })
}
