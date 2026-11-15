// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

private func ps2Importer(_ rig: ImportRig) -> Importer {
    Importer(libraryRoot: rig.library, dats: DatStore(paths: rig.paths), runner: ProcessRunner(), biosDirectory: rig.paths.retroarchSystem)
}

@Test func ps2BiosImportedToItsFolder() throws {
    let rig = try ImportRig()
    let file = rig.drops.appending(path: "SCPH-39001.bin")
    try syntheticPs2Bios(file)
    let importer = ps2Importer(rig)
    let (session, candidates) = try importer.analyze([file])
    #expect(candidates.map(\.status) == [.bios(.ps2, region: "")])
    _ = try importer.commit(session, candidates)
    #expect(Ps2Bios.isBios(rig.paths.ps2Bios.appending(path: "SCPH-39001.bin")))
    #expect(!FileManager.default.fileExists(atPath: rig.library.path))
}
@Test func ps2BiosAlreadyThereIsADuplicateAndADifferentOneFails() throws {
    let rig = try ImportRig()
    let file = rig.drops.appending(path: "SCPH-39001.bin")
    try syntheticPs2Bios(file)
    try syntheticPs2Bios(rig.paths.ps2Bios.appending(path: "SCPH-39001.bin"))
    #expect(try ps2Importer(rig).analyze([file]).1.map(\.status) == [.duplicate(nil)])
    var other = try Data(contentsOf: file); other[0] = 1
    try other.write(to: rig.paths.ps2Bios.appending(path: "SCPH-39001.bin"))
    guard case .failed = try ps2Importer(rig).analyze([file]).1.first?.status else { Issue.record("expected failed"); return }
}
