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

    func updater(_ m: Manifest, downloader: any Downloader = host, running: String? = nil, fileOps: any FileOps = RealFileOps(),
                 isRunning: (@Sendable (String) -> Bool)? = nil, applierRunning: String? = nil) -> Updater {
        Updater(paths: paths,
                installer: Installer(manifest: m, paths: paths, downloader: downloader, runner: ProcessRunner()),
                applier: Applier(paths: paths, apps: ["RetroArch.app", "ES-DE.app", "Fake.app"], isRunning: { $0 == applierRunning }),
                apps: ["RetroArch.app", "ES-DE.app", "Fake.app"], isRunning: isRunning ?? { $0 == running }, fileOps: fileOps)
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
    let report = try await rig.updater(latest, fileOps: FailingMoveIn(paths: rig.paths))
        .apply([coreUpdate()], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    #expect(report.updated.isEmpty)
    #expect(report.failed.count == 1 && report.failed[0].hasPrefix("mesen: "))
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

/// Fails any move whose source and destination match the predicate; every other move is real.
struct FailingMove: FileOps {
    let when: @Sendable (URL, URL) -> Bool
    func move(_ from: URL, to: URL) throws {
        if when(from, to) { throw CocoaError(.fileWriteOutOfSpace) }
        try RealFileOps().move(from, to: to)
    }
    func removeIfExists(_ url: URL) throws { try RealFileOps().removeIfExists(url) }
}

/// Reports "RetroArch.app" as running from the `after`-th check on.
final class LaunchesLater: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    let after: Int
    init(after: Int) { self.after = after }
    func check(_ app: String) -> Bool {
        lock.withLock { calls += 1; return app == "RetroArch.app" && calls > after }
    }
}

@Test func failedUpdateKeepsPreviousGeneration() async throws {
    let rig = try Rig()
    let v2 = try await installOldCore(rig)
    _ = try await rig.updater(v2).apply([coreUpdate()], adopt: [], latest: v2, profile: rig.profile, rules: .bundled())
    var v3 = try coreEntry(makeCoreZip(in: rig.dir, bytes: "newer")); v3.version = "3.0"
    let m3 = manifest(cores: [v3])
    let report = try await rig.updater(m3, fileOps: FailingMoveIn(paths: rig.paths))
        .apply([coreUpdate()], adopt: [], latest: m3, profile: rig.profile, rules: .bundled())
    #expect(report.failed.count == 1)
    #expect(try read(rig.coreFile) == "new")
    #expect(try read(rig.paths.previous.appending(path: "fake_libretro.dylib")) == "old")
    try rig.updater(m3).rollback("mesen")
    #expect(try read(rig.coreFile) == "old")
}
@Test func rollbackWithMissingPreviousFileThrows() async throws {
    let rig = try Rig()
    let latest = try await installOldCore(rig)
    _ = try await rig.updater(latest).apply([coreUpdate()], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    try FileManager.default.removeItem(at: rig.paths.previous.appending(path: "fake_libretro.dylib"))
    #expect(throws: UpdateError.nothingToRollBack("mesen")) { try rig.updater(latest).rollback("mesen") }
    #expect(try read(rig.coreFile) == "new")
}
@Test func rollbackRestoresCurrentWhenSwapFails() async throws {
    let rig = try Rig()
    let latest = try await installOldCore(rig)
    _ = try await rig.updater(latest).apply([coreUpdate()], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    let previousPath = rig.paths.previous.appending(path: "fake_libretro.dylib").path
    let failing = FailingMove { from, _ in from.path == previousPath }
    #expect(throws: (any Error).self) { try rig.updater(latest, fileOps: failing).rollback("mesen") }
    #expect(try read(rig.coreFile) == "new")
    #expect(try rig.state().cores["mesen"]?.version == "2.0")
}
@Test func rollbackRefusesWhileEmulatorRunning() async throws {
    let rig = try Rig()
    let latest = try await installOldCore(rig)
    _ = try await rig.updater(latest).apply([coreUpdate()], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    #expect(throws: UpdateError.appRunning("RetroArch.app")) { try rig.updater(latest, running: "RetroArch.app").rollback("mesen") }
    #expect(try read(rig.coreFile) == "new")
}
@Test func appRollbackSwapsBack() async throws {
    let rig = try Rig()
    try writePlist(version: "0.9", to: rig.paths.applications.appending(path: "Fake.app"))
    let m = manifest(apps: [try appEntry(makeAppDmg(in: rig.dir))])
    _ = try await installer(m, rig.paths).install(systems: [])
    _ = try await rig.updater(m).apply([appUpdate(managed: false)], adopt: ["fake"], latest: m, profile: rig.profile, rules: .bundled())
    try rig.updater(m).rollback("fake")
    #expect(Installer.bundleVersion(of: rig.paths.applications.appending(path: "Fake.app")) == "0.9")
    #expect(try rig.state().apps["fake"]?.managed == false)
}
@Test func runningCheckedAgainBeforeSwap() async throws {
    let rig = try Rig()
    let latest = try await installOldCore(rig)
    let before = try rig.state()
    let launches = LaunchesLater(after: 3)
    await #expect(throws: UpdateError.appRunning("RetroArch.app")) {
        try await rig.updater(latest, isRunning: { launches.check($0) })
            .apply([coreUpdate()], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    }
    #expect(try read(rig.coreFile) == "old")
    #expect(try rig.state() == before)
}
@Test func partialFailureReportsAndRerenders() async throws {
    let rig = try Rig()
    var latest = try await installOldCore(rig)
    let snesOld = try coreEntry(makeCoreZip(in: rig.dir, name: "snes_libretro.dylib", bytes: "old"), id: "bsnes", system: .snes, file: "snes_libretro.dylib")
    _ = try await installer(manifest(cores: [snesOld]), rig.paths).install(systems: [.snes])
    var snesNew = try coreEntry(makeCoreZip(in: rig.dir, name: "snes_libretro.dylib", bytes: "new"), id: "bsnes", system: .snes, file: "snes_libretro.dylib")
    snesNew.version = "2.0"
    latest.cores.append(snesNew)
    let failing = FailingMove { from, to in to.lastPathComponent == "snes_libretro.dylib" && to.path.contains("/cores/") && !from.path.contains("/previous/") }
    let report = try await rig.updater(latest, fileOps: failing)
        .apply([coreUpdate(), coreUpdate("bsnes")], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    #expect(report.updated == ["mesen"])
    #expect(report.failed.count == 1 && report.failed[0].hasPrefix("bsnes: "))
    #expect(report.config != nil)
    #expect(try read(rig.coreFile) == "new")
    #expect(try read(rig.paths.retroarchCores.appending(path: "snes_libretro.dylib")) == "old")
}
@Test func appliedManifestWrittenOnlyAfterConfigApplies() async throws {
    let rig = try Rig()
    let latest = try await installOldCore(rig)
    await #expect(throws: ApplyError.appRunning("ES-DE.app")) {
        try await rig.updater(latest, applierRunning: "ES-DE.app")
            .apply([coreUpdate()], adopt: [], latest: latest, profile: rig.profile, rules: .bundled())
    }
    #expect(!FileManager.default.fileExists(atPath: rig.paths.appliedManifest.path))
}
