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
    #expect(BiosFile.known.filter { $0.system != .xbox }.map(\.fileName) == ["scph5500.bin", "scph5501.bin", "scph5502.bin", "sega_101.bin", "mpr-17933.bin"])
    #expect(BiosFile.known.first { $0.fileName == "scph5501.bin" }?.md5 == "490f666e1afb15b7362b406ed1cea246")
    #expect(BiosFile.known.first { $0.fileName == "sega_101.bin" }?.md5 == "85ec9ca47d8f6807718151cbcca8b964")
}
@Test func differentFileWithBiosNameIsReportedNotSuffixed() throws {
    let rig = try ImportRig()
    try FileManager.default.createDirectory(at: rig.biosDir, withIntermediateDirectories: true)
    let existing = rig.biosDir.appending(path: "mpr-17933.bin")
    try fakeBios(seed: 3).write(to: existing)
    let importer = rig.biosImporter(rig.biosDir)
    let (session, candidates) = try importer.analyze([try rig.drop("good.bin", fakeBios(seed: 1))])
    guard case .failed(let reason) = candidates.first?.status else {
        Issue.record("expected failure, got \(candidates.map(\.status))")
        return
    }
    #expect(reason.contains("mpr-17933.bin"))
    _ = try importer.commit(session, candidates)
    #expect(try FileManager.default.contentsOfDirectory(atPath: rig.biosDir.path) == ["mpr-17933.bin"])
    #expect(try Data(contentsOf: existing) == fakeBios(seed: 3))
}

private func fakeData(_ count: Int, seed: UInt8) -> Data {
    Data((0..<count).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ Int(seed)) })
}

@Test func xboxBiosOfDifferentSizesAreRecognized() throws {
    let dir = try makeTempDir()
    let mcpx = fakeData(512, seed: 3), flash = fakeData(262_144, seed: 4)
    let table = [BiosFile(system: .xbox, fileName: "mcpx_1.0.bin", region: "All", md5: md5(mcpx), size: 512),
                 BiosFile(system: .xbox, fileName: "Complex_4627.bin", region: "All", md5: md5(flash), size: 262_144)]
    try mcpx.write(to: dir.appending(path: "a.bin")); try flash.write(to: dir.appending(path: "b.bin"))
    #expect(BiosFile.match(dir.appending(path: "a.bin"), in: table)?.0.fileName == "mcpx_1.0.bin")
    #expect(BiosFile.match(dir.appending(path: "b.bin"), in: table)?.0.fileName == "Complex_4627.bin")
}
@Test func fileOfAnUnknownSizeIsNeverHashed() throws {
    let dir = try makeTempDir()
    let data = fakeData(1000, seed: 5)
    try data.write(to: dir.appending(path: "c.bin"))
    let table = [BiosFile(system: .xbox, fileName: "x.bin", region: "All", md5: md5(data), size: 512)]
    #expect(BiosFile.match(dir.appending(path: "c.bin"), in: table) == nil)
}
@Test func xboxBiosStatusNamesWhatIsMissing() throws {
    let dir = try makeTempDir()
    let mcpx = fakeData(512, seed: 3), flash = fakeData(262_144, seed: 4)
    let table = [BiosFile(system: .xbox, fileName: "mcpx_1.0.bin", region: "All", md5: md5(mcpx), size: 512),
                 BiosFile(system: .xbox, fileName: "Complex_4627.bin", region: "All", md5: md5(flash), size: 262_144)]
    try mcpx.write(to: dir.appending(path: "mcpx_1.0.bin"))
    #expect(BiosStatus.present(in: dir, known: table)[.xbox]?.map(\.fileName) == ["mcpx_1.0.bin"])
    #expect(BiosStatus.missing(.xbox, in: dir, known: table) == ["Complex_4627.bin"])
    #expect(BiosFile.known.filter { $0.system == .xbox }.map(\.fileName) == ["mcpx_1.0.bin", "Complex_4627.bin"])
}
