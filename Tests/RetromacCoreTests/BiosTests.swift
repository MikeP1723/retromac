// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation
import Testing
@testable import RetromacCore

/// 512 KiB of deterministic bytes standing in for a BIOS dump; never a real one.
private func fakeBios(seed: UInt8) -> Data {
    Data((0..<524_288).map { UInt8(truncatingIfNeeded: $0 &* 31 &+ Int(seed)) })
}

private func md5(_ data: Data) -> String {
    Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private let saturnUS = BiosFile(system: .saturn, fileName: "mpr-17933.bin", region: "USA/Europe", md5: md5(fakeBios(seed: 1)))

extension ImportRig {
    var biosDir: URL { paths.retroarchSystem }

    func biosImporter(_ dir: URL?) -> Importer {
        Importer(libraryRoot: library, dats: DatStore(paths: paths), runner: ProcessRunner(), biosDirectory: dir, bios: [saturnUS])
    }
}

@Test func biosIsRecognizedAndFiled() throws {
    let rig = try ImportRig()
    let file = try rig.drop("whatever.bin", fakeBios(seed: 1))
    let importer = rig.biosImporter(rig.biosDir)
    let (session, candidates) = try importer.analyze([file])
    #expect(candidates.map(\.status) == [.bios(.saturn, region: "USA/Europe")])
    #expect(Importer.summarize(candidates).bios == 1)
    _ = try importer.commit(session, candidates)
    #expect(try Data(contentsOf: rig.biosDir.appending(path: "mpr-17933.bin")) == fakeBios(seed: 1))
    #expect(!FileManager.default.fileExists(atPath: rig.library.path))
}
@Test func biosInsideZipIsRecognized() throws {
    let rig = try ImportRig()
    let src = rig.dir.appending(path: "zipsrc")
    try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
    try fakeBios(seed: 1).write(to: src.appending(path: "saturn bios.bin"))
    let zip = rig.drops.appending(path: "bios.zip")
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", zip.path, "-C", src.path, "saturn bios.bin"])
    let (_, candidates) = try rig.biosImporter(rig.biosDir).analyze([zip])
    #expect(candidates.map(\.status) == [.bios(.saturn, region: "USA/Europe")])
}
@Test func wrongHashIsNotBios() throws {
    let rig = try ImportRig()
    let file = try rig.drop("mpr-17933.bin", fakeBios(seed: 2))
    let importer = rig.biosImporter(rig.biosDir)
    let (session, candidates) = try importer.analyze([file])
    #expect(!candidates.contains { if case .bios = $0.status { true } else { false } })
    _ = try importer.commit(session, candidates)
    #expect(!FileManager.default.fileExists(atPath: rig.biosDir.path))
}
@Test func biosAlreadyPresentIsDuplicate() throws {
    let rig = try ImportRig()
    try FileManager.default.createDirectory(at: rig.biosDir, withIntermediateDirectories: true)
    try fakeBios(seed: 1).write(to: rig.biosDir.appending(path: "mpr-17933.bin"))
    let (_, candidates) = try rig.biosImporter(rig.biosDir).analyze([try rig.drop("copy.bin", fakeBios(seed: 1))])
    #expect(candidates.map(\.status) == [.duplicate(nil)])
}
@Test func noBiosDirectoryMeansNoDetection() throws {
    let rig = try ImportRig()
    let (_, candidates) = try rig.biosImporter(nil).analyze([try rig.drop("whatever.bin", fakeBios(seed: 1))])
    #expect(!candidates.contains { if case .bios = $0.status { true } else { false } })
}
@Test func statusRequiresMatchingHash() throws {
    let dir = try makeTempDir()
    #expect(BiosStatus.present(in: dir, known: [saturnUS]).isEmpty)
    try fakeBios(seed: 2).write(to: dir.appending(path: "mpr-17933.bin"))
    #expect(BiosStatus.present(in: dir, known: [saturnUS]).isEmpty)
    try fakeBios(seed: 1).write(to: dir.appending(path: "mpr-17933.bin"))
    #expect(BiosStatus.present(in: dir, known: [saturnUS]) == [.saturn: [saturnUS]])
}
@Test func knownTableMatchesLibretro() {
    #expect(BiosFile.known.map(\.fileName) == ["scph5500.bin", "scph5501.bin", "scph5502.bin", "sega_101.bin", "mpr-17933.bin"])
    #expect(BiosFile.known.first { $0.fileName == "scph5501.bin" }?.md5 == "490f666e1afb15b7362b406ed1cea246")
    #expect(BiosFile.known.first { $0.fileName == "sega_101.bin" }?.md5 == "85ec9ca47d8f6807718151cbcca8b964")
}
