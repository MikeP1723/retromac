// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

struct Rig {
    let dir: URL
    let paths: Paths

    init() throws {
        dir = try makeTempDir()
        paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
        try FileManager.default.createDirectory(at: paths.applications, withIntermediateDirectories: true)
    }

    func updater(_ m: Manifest, downloader: any Downloader = host, running: String? = nil, fileOps: any FileOps = RealFileOps()) -> Updater {
        Updater(paths: paths,
                installer: Installer(manifest: m, paths: paths, downloader: downloader, runner: ProcessRunner()),
                applier: Applier(paths: paths, apps: ["RetroArch.app", "ES-DE.app", "Fake.app"], isRunning: { _ in false }),
                apps: ["RetroArch.app", "ES-DE.app", "Fake.app"], isRunning: { $0 == running }, fileOps: fileOps)
    }

    var profile: Profile { RetromacCoreTests.profile(controllers: [], library: paths.defaultLibraryRoot) }
    var coreFile: URL { paths.retroarchCores.appending(path: "fake_libretro.dylib") }
    func state() throws -> InstallState { try InstallState.load(from: paths.state) }
}

func coreUpdate(_ id: String = "mesen") -> ComponentUpdate {
    ComponentUpdate(id: id, kind: .core, installed: "1.0", available: "2.0", managed: true,
                    license: "GPL-3.0-or-later", previousLicense: nil, requiresRosetta: false)
}

func appUpdate(managed: Bool) -> ComponentUpdate {
    ComponentUpdate(id: "fake", kind: .app, installed: "0.9", available: "1.0", managed: managed,
                    license: "MIT", previousLicense: nil, requiresRosetta: false)
}

/// Installs core v1 ("old") and returns a manifest whose mesen entry points at v2 ("new").
func installOldCore(_ rig: Rig, pinned: Bool = true) async throws -> Manifest {
    let old = try coreEntry(makeCoreZip(in: rig.dir, bytes: "old"))
    _ = try await installer(manifest(cores: [old]), rig.paths).install(systems: [.nes])
    var new = try coreEntry(makeCoreZip(in: rig.dir, bytes: "new"))
    new.version = "2.0"
    if !pinned { new.sha256 = nil }
    return manifest(cores: [new])
}

final class CountingDownloader: Downloader, @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.withLock { n } }
    func download(_ url: URL, to dest: URL) async throws {
        lock.withLock { n += 1 }
        try await host.download(url, to: dest)
    }
}

/// Fails the move of a staged core into the cores dir; every other move is real.
struct FailingMoveIn: FileOps {
    let paths: Paths
    func move(_ from: URL, to: URL) throws {
        if to.deletingLastPathComponent().standardizedFileURL == paths.retroarchCores.standardizedFileURL,
           !from.path.hasPrefix(paths.previous.path) {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        try RealFileOps().move(from, to: to)
    }
    func removeIfExists(_ url: URL) throws { try RealFileOps().removeIfExists(url) }
}

@Test func updatesManagedCoreAndKeepsPrevious() async throws {
    let rig = try Rig()
    let latest = try await installOldCore(rig)
    let oldSha = try rig.state().cores["mesen"]!.sha256
    let report = try await rig.updater(latest).apply([coreUpdate()], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    #expect(report.updated == ["mesen"])
    #expect(try read(rig.coreFile) == "new")
    #expect(try read(rig.paths.previous.appending(path: "fake_libretro.dylib")) == "old")
    #expect(try rig.state().cores["mesen"]?.sha256 == latest.cores[0].sha256)
    #expect(try rig.state().cores["mesen"]?.version == "2.0")
    #expect(try rig.state().previousCores?["mesen"]?.sha256 == oldSha)
}
@Test func refusesWhileEmulatorRunning() async throws {
    let rig = try Rig()
    let latest = try await installOldCore(rig)
    let counter = CountingDownloader()
    await #expect(throws: UpdateError.appRunning("RetroArch.app")) {
        try await rig.updater(latest, downloader: counter, running: "RetroArch.app")
            .apply([coreUpdate()], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    }
    #expect(counter.count == 0)
}
@Test func unpinnedCoreRebuildRecordsNewCrc() async throws {
    let rig = try Rig()
    let latest = try await installOldCore(rig, pinned: false)
    let oldCrc = try rig.state().cores["mesen"]?.crc32
    _ = try await rig.updater(latest).apply([coreUpdate()], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    #expect(try rig.state().cores["mesen"]?.crc32 == CRC32.hex(of: rig.coreFile))
    #expect(try rig.state().previousCores?["mesen"]?.crc32 == oldCrc)
}
@Test func skipsUnmanagedUnlessAdopted() async throws {
    let rig = try Rig()
    try writePlist(version: "0.9", to: rig.paths.applications.appending(path: "Fake.app"))
    let entry = try appEntry(makeAppDmg(in: rig.dir))
    let m = manifest(apps: [entry])
    _ = try await installer(m, rig.paths).install(systems: [])
    let skipped = try await rig.updater(m).apply([appUpdate(managed: false)], adopt: [], latest: m, profile: rig.profile, rules: .bundled())
    #expect(skipped.skipped == ["fake: not managed by retromac"])
    #expect(Installer.bundleVersion(of: rig.paths.applications.appending(path: "Fake.app")) == "0.9")
    let adopted = try await rig.updater(m).apply([appUpdate(managed: false)], adopt: ["fake"], latest: m, profile: rig.profile, rules: .bundled())
    #expect(adopted.updated == ["fake"])
    #expect(Installer.bundleVersion(of: rig.paths.applications.appending(path: "Fake.app")) == "1.0")
    #expect(Installer.bundleVersion(of: rig.paths.previous.appending(path: "Fake.app")) == "0.9")
    #expect(try rig.state().apps["fake"]?.managed == true)
    #expect(try FileManager.default.contentsOfDirectory(atPath: rig.paths.applications.path) == ["Fake.app"])
}
@Test func stagingFailureSwapsNothing() async throws {
    let rig = try Rig()
    var latest = try await installOldCore(rig)
    var broken = try coreEntry(makeCoreZip(in: rig.dir, name: "snes_libretro.dylib"), id: "bsnes", system: .snes, file: "snes_libretro.dylib")
    _ = try await installer(manifest(cores: [broken]), rig.paths).install(systems: [.snes])
    broken.sha256 = String(repeating: "0", count: 64)
    latest.cores.append(broken)
    let before = try rig.state()
    await #expect(throws: InstallError.self) {
        try await rig.updater(latest).apply([coreUpdate(), coreUpdate("bsnes")], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    }
    #expect(try read(rig.coreFile) == "old")
    #expect(try rig.state() == before)
}
@Test func moveInFailureRestoresCurrent() async throws {
    let rig = try Rig()
    let latest = try await installOldCore(rig)
    let before = try rig.state()
    await #expect(throws: (any Error).self) {
        try await rig.updater(latest, fileOps: FailingMoveIn(paths: rig.paths))
            .apply([coreUpdate()], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    }
    #expect(try read(rig.coreFile) == "old")
    #expect(((try? FileManager.default.contentsOfDirectory(atPath: rig.paths.previous.path)) ?? []).isEmpty)
    #expect(try rig.state() == before)
}
@Test func rollbackSwapsBack() async throws {
    let rig = try Rig()
    let latest = try await installOldCore(rig)
    let oldSha = try rig.state().cores["mesen"]!.sha256
    _ = try await rig.updater(latest).apply([coreUpdate()], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    try rig.updater(latest).rollback("mesen")
    #expect(try read(rig.coreFile) == "old")
    #expect(try read(rig.paths.previous.appending(path: "fake_libretro.dylib")) == "new")
    #expect(try rig.state().cores["mesen"]?.sha256 == oldSha)
    #expect(try rig.state().previousCores?["mesen"]?.sha256 == latest.cores[0].sha256)
}
@Test func rollbackWithoutPreviousThrows() throws {
    let rig = try Rig()
    #expect(throws: UpdateError.nothingToRollBack("bsnes")) { try rig.updater(manifest()).rollback("bsnes") }
}
@Test func reappliesConfigAfterUpdate() async throws {
    let rig = try Rig()
    let latest = try await installOldCore(rig)
    let report = try await rig.updater(latest).apply([coreUpdate()], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    #expect(report.config != nil)
    #expect(try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: rig.paths.appliedManifest)) == latest)
}
