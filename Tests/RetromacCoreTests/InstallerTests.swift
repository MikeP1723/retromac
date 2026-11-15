// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

/// Serves local fixture files for https URLs, so tests run under the real ManifestPolicy.
final class FixtureDownloader: Downloader, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [URL: URL] = [:]

    func serve(_ local: URL, host: String = "buildbot.libretro.com") -> URL {
        let url = URL(string: "https://\(host)/fixture/\(UUID().uuidString)/\(local.lastPathComponent)")!
        lock.withLock { files[url] = local }
        return url
    }

    func serve(_ local: URL, at url: URL) {
        lock.withLock { files[url] = local }
    }

    func download(_ url: URL, to dest: URL) async throws {
        guard let local = lock.withLock({ files[url] }) else { throw URLError(.fileDoesNotExist) }
        try FileManager.default.copyItem(at: local, to: dest)
    }
}

/// Zip containing `name` with `bytes`, built with the same bsdtar the installer extracts with.
func makeCoreZip(in dir: URL, name: String = "fake_libretro.dylib", bytes: String = "core") throws -> URL {
    let staging = dir.appending(path: "staging-\(UUID().uuidString)")
    try write(bytes, to: staging.appending(path: name))
    let zip = dir.appending(path: "core-\(UUID().uuidString).zip")
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", zip.path, "-C", staging.path, name])
    return zip
}

/// Concurrent `hdiutil create -srcfolder` runs intermittently leave images attached,
/// so fixture creation is serialized.
let dmgCreateLock = NSLock()

func makeAppDmg(in dir: URL, appName: String = "Fake.app", version: String = "1.0") throws -> URL {
    let src = dir.appending(path: "dmgsrc-\(UUID().uuidString)")
    try writePlist(version: version, to: src.appending(path: appName))
    let dmg = dir.appending(path: "app-\(UUID().uuidString).dmg")
    try dmgCreateLock.withLock {
        _ = try ProcessRunner().run("/usr/bin/hdiutil", ["create", "-quiet", "-srcfolder", src.path, "-format", "UDZO", "-volname", "Fake", dmg.path])
    }
    return dmg
}

func writePlist(version: String, to app: URL) throws {
    let plist: NSDictionary = ["CFBundleShortVersionString": version, "CFBundleIdentifier": "test.fake"]
    let url = app.appending(path: "Contents/Info.plist")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try plist.write(to: url)
}

let host = FixtureDownloader()

func coreEntry(_ local: URL, id: String = "mesen", system: SystemID = .nes, file: String = "fake_libretro.dylib") throws -> CoreEntry {
    CoreEntry(id: id, version: "1.0", system: system, libraryName: "Mesen", file: file, url: host.serve(local),
              sha256: try SHA256File.hex(of: local), license: "GPL-3.0-or-later", arch: .arm64, rosetta: false)
}

func appEntry(_ local: URL, version: String = "1.0") throws -> AppEntry {
    AppEntry(id: "fake", version: version, url: host.serve(local, host: "github.com"), sha256: try SHA256File.hex(of: local),
             license: "MIT", arch: .arm64, rosetta: false, appName: "Fake.app")
}

func installer(_ m: Manifest, _ paths: Paths) -> Installer {
    Installer(manifest: m, paths: paths, downloader: host, runner: ProcessRunner())
}

func manifest(apps: [AppEntry] = [], cores: [CoreEntry] = []) -> Manifest {
    Manifest(schemaVersion: 1, manifestVersion: 3, minAppVersion: "0.1.0", apps: apps, cores: cores)
}

@Test func installsCoreAfterVerifyingSha() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    let entry = try coreEntry(makeCoreZip(in: dir))
    let report = try await installer(manifest(cores: [entry]), paths).install(systems: [.nes])
    #expect(report.installed == ["mesen"])
    #expect(try read(paths.retroarchCores.appending(path: "fake_libretro.dylib")) == "core")
    let state = try InstallState.load(from: paths.state)
    #expect(state.cores["mesen"] == .init(version: "1.0", sha256: entry.sha256!, file: "fake_libretro.dylib",
                                          crc32: "6b8d854f", libraryName: "Mesen"))
    #expect(state.manifestVersion == 3)
}
@Test func shaMismatchInstallsNothing() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    var entry = try coreEntry(makeCoreZip(in: dir))
    let actual = entry.sha256!
    entry.sha256 = String(repeating: "0", count: 64)
    await #expect(throws: InstallError.checksumMismatch(id: "mesen", expected: String(repeating: "0", count: 64), actual: actual)) {
        try await installer(manifest(cores: [entry]), paths).install(systems: [.nes])
    }
    #expect(!FileManager.default.fileExists(atPath: paths.retroarchCores.appending(path: "fake_libretro.dylib").path))
    #expect(!FileManager.default.fileExists(atPath: paths.state.path))
}
@Test func secondRunSkipsInstalledCore() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    let m = manifest(cores: [try coreEntry(makeCoreZip(in: dir))])
    _ = try await installer(m, paths).install(systems: [.nes])
    #expect(try await installer(m, paths).install(systems: [.nes]).skipped == ["mesen"])
}
@Test func missingFileInArchiveThrows() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    let entry = try coreEntry(makeCoreZip(in: dir), file: "other.dylib")
    await #expect(throws: InstallError.fileNotFoundInArchive("other.dylib")) {
        try await installer(manifest(cores: [entry]), paths).install(systems: [.nes])
    }
}
@Test func installsAppFromDmg() async throws {
    let dir = try makeTempDir(), apps = dir.appending(path: "Apps")
    let paths = Paths(home: dir.appending(path: "home"), applications: apps)
    try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
    let entry = try appEntry(makeAppDmg(in: dir))
    let report = try await installer(manifest(apps: [entry]), paths).install(systems: [])
    #expect(report.installed == ["fake"])
    #expect(FileManager.default.fileExists(atPath: apps.appending(path: "Fake.app/Contents/Info.plist").path))
    #expect(try !ProcessRunner().run("/usr/bin/hdiutil", ["info"]).contains(dir.path))
    #expect(try InstallState.load(from: paths.state).apps["fake"] == .init(version: "1.0", sha256: entry.sha256, managed: true))
}
@Test func existingAppIsNeverReplaced() async throws {
    let dir = try makeTempDir(), apps = dir.appending(path: "Apps")
    let paths = Paths(home: dir.appending(path: "home"), applications: apps)
    try writePlist(version: "0.9", to: apps.appending(path: "Fake.app"))
    let before = try Data(contentsOf: apps.appending(path: "Fake.app/Contents/Info.plist"))
    let entry = try appEntry(makeAppDmg(in: dir))
    let report = try await installer(manifest(apps: [entry]), paths).install(systems: [])
    #expect(report.skipped == ["fake"])
    #expect(report.warnings == ["fake: installed 0.9, manifest pins 1.0; leaving installed copy"])
    #expect(try Data(contentsOf: apps.appending(path: "Fake.app/Contents/Info.plist")) == before)
    #expect(try InstallState.load(from: paths.state).apps["fake"] == .init(version: "0.9", sha256: nil, managed: false))
}
@Test func onlySelectedSystemsInstalled() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    let nes = try coreEntry(makeCoreZip(in: dir))
    let snes = try coreEntry(makeCoreZip(in: dir, name: "snes_libretro.dylib"), id: "bsnes", system: .snes, file: "snes_libretro.dylib")
    let report = try await installer(manifest(cores: [nes, snes]), paths).install(systems: [.nes])
    #expect(report.installed == ["mesen"])
}
@Test func stateSavedPerComponentSoLaterFailureKeepsManagedApp() async throws {
    let dir = try makeTempDir(), apps = dir.appending(path: "Apps")
    let paths = Paths(home: dir.appending(path: "home"), applications: apps)
    let app = try appEntry(makeAppDmg(in: dir))
    var core = try coreEntry(makeCoreZip(in: dir))
    core.sha256 = String(repeating: "0", count: 64)
    await #expect(throws: InstallError.self) {
        try await installer(manifest(apps: [app], cores: [core]), paths).install(systems: [.nes])
    }
    #expect(try InstallState.load(from: paths.state).apps["fake"]?.managed == true)
}
@Test func installRejectsPolicyViolationBeforeDownloading() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    let entry = try coreEntry(makeCoreZip(in: dir), file: "../evil.dylib")
    await #expect(throws: InstallError.policy(["mesen: file ../evil.dylib is not a single path component"])) {
        try await installer(manifest(cores: [entry]), paths).install(systems: [.nes])
    }
    #expect(!FileManager.default.fileExists(atPath: paths.retroarchSupport.path))
}
@Test func unpinnedCoreInstallsAndRecordsActualSha() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    let zip = try makeCoreZip(in: dir)
    var entry = try coreEntry(zip)
    entry.sha256 = nil
    _ = try await installer(manifest(cores: [entry]), paths).install(systems: [.nes])
    #expect(try InstallState.load(from: paths.state).cores["mesen"]?.sha256 == SHA256File.hex(of: zip))
    #expect(try await installer(manifest(cores: [entry]), paths).install(systems: [.nes]).skipped == ["mesen"])
}
@Test func symlinkInArchiveIsRejected() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    let staging = dir.appending(path: "s")
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(atPath: staging.appending(path: "fake_libretro.dylib").path, withDestinationPath: "/etc/hosts")
    let zip = dir.appending(path: "link.zip")
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", zip.path, "-C", staging.path, "fake_libretro.dylib"])
    await #expect(throws: InstallError.fileNotFoundInArchive("fake_libretro.dylib")) {
        try await installer(manifest(cores: [try coreEntry(zip)]), paths).install(systems: [.nes])
    }
}
@Test func urlSessionDownloaderRefusesNonHTTPS() async throws {
    let dir = try makeTempDir()
    try write("x", to: dir.appending(path: "a"))
    await #expect(throws: URLError.self) {
        try await URLSessionDownloader().download(dir.appending(path: "a"), to: dir.appending(path: "b"))
    }
}
@Test func processRunnerFeedsInput() throws {
    #expect(try ProcessRunner().run("/bin/cat", [], input: "Y\n") == "Y\n")
}
@Test func processRunnerDoesNotDeadlockOnLargeStderr() throws {
    let done = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        _ = try? ProcessRunner().run("/bin/sh", ["-c", "head -c 200000 /dev/zero | tr '\\\\0' x >&2; echo out"])
        done.signal()
    }
    #expect(done.wait(timeout: .now() + 10) == .success)
}
/// Runs real commands, but simulates ditto dying halfway: partial output, then failure.
struct DittoDiesRunner: CommandRunner {
    func run(_ executable: String, _ args: [String], input: String?) throws -> String {
        if executable == "/usr/bin/ditto", let dest = args.last {
            try FileManager.default.createDirectory(atPath: dest + "/Contents", withIntermediateDirectories: true)
            throw InstallError.commandFailed(executable, 1, "No space left on device")
        }
        return try ProcessRunner().run(executable, args, input: input)
    }
}
@Test func interruptedAppCopyLeavesNoPartialApp() async throws {
    let dir = try makeTempDir(), apps = dir.appending(path: "Apps")
    let paths = Paths(home: dir.appending(path: "home"), applications: apps)
    let entry = try appEntry(makeAppDmg(in: dir))
    let failing = Installer(manifest: manifest(apps: [entry]), paths: paths, downloader: host, runner: DittoDiesRunner())
    await #expect(throws: InstallError.self) { try await failing.install(systems: []) }
    #expect(!FileManager.default.fileExists(atPath: apps.appending(path: "Fake.app").path))
    #expect(try await installer(manifest(apps: [entry]), paths).install(systems: []).installed == ["fake"])
    #expect(try FileManager.default.contentsOfDirectory(atPath: apps.path) == ["Fake.app"])
}
@Test func extractsRetroArchAssetsBeforeFirstLaunch() async throws {
    let dir = try makeTempDir(), apps = dir.appending(path: "Apps")
    let paths = Paths(home: dir.appending(path: "home"), applications: apps)
    let staging = dir.appending(path: "assets")
    try write("preset", to: staging.appending(path: "shaders/shaders_slang/crt/crt-easymode.slangp"))
    try write("mfi", to: staging.appending(path: "autoconfig/mfi/MFi_Controller.cfg"))
    let resources = apps.appending(path: "RetroArch.app/Contents/Resources")
    try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
    try ProcessRunner().run("/usr/bin/tar", ["-a", "-cf", resources.appending(path: "assets.zip").path, "-C", staging.path, "shaders", "autoconfig"])
    _ = try await installer(manifest(), paths).install(systems: [])
    #expect(try read(paths.retroarchShadersSlang.appending(path: "crt/crt-easymode.slangp")) == "preset")
    #expect(try read(paths.retroarchSupport.appending(path: "autoconfig/mfi/MFi_Controller.cfg")) == "mfi")
}

@Test func replacedCoreIsRemovedWithItsRemap() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    let old = try coreEntry(makeCoreZip(in: dir, name: "old_libretro.dylib"), id: "old", file: "old_libretro.dylib")
    _ = try await installer(manifest(cores: [old]), paths).install(systems: [.nes])
    let remap = paths.coreRemap(libraryName: "Mesen")
    try FileManager.default.createDirectory(at: remap.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("input_libretro_device_p1 = \"517\"\n".utf8).write(to: remap)

    let newDir = dir.appending(path: "new"); try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
    var new = try coreEntry(makeCoreZip(in: newDir, name: "new_libretro.dylib"), id: "new", file: "new_libretro.dylib")
    new.libraryName = "New"
    let report = try await installer(manifest(cores: [new]), paths).install(systems: [.nes])

    #expect(report.removed == ["old"])
    #expect(!FileManager.default.fileExists(atPath: paths.retroarchCores.appending(path: "old_libretro.dylib").path))
    #expect(!FileManager.default.fileExists(atPath: remap.path))
    #expect(!FileManager.default.fileExists(atPath: remap.deletingLastPathComponent().path))
    #expect(try InstallState.load(from: paths.state).cores["old"] == nil)
    #expect(FileManager.default.fileExists(atPath: paths.retroarchCores.appending(path: "new_libretro.dylib").path))
}

@Test func coreOfADisabledSystemIsKept() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    let m = manifest(cores: [try coreEntry(makeCoreZip(in: dir))])
    _ = try await installer(m, paths).install(systems: [.nes])
    let report = try await installer(m, paths).install(systems: [])
    #expect(report.removed.isEmpty)
    #expect(FileManager.default.fileExists(atPath: paths.retroarchCores.appending(path: "fake_libretro.dylib").path))
}

@Test func dylibStillInTheManifestIsKept() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    let zip = try makeCoreZip(in: dir)
    _ = try await installer(manifest(cores: [try coreEntry(zip, id: "renamed")]), paths).install(systems: [.nes])
    let report = try await installer(manifest(cores: [try coreEntry(zip)]), paths).install(systems: [.nes])
    #expect(report.removed == ["renamed"])
    #expect(FileManager.default.fileExists(atPath: paths.retroarchCores.appending(path: "fake_libretro.dylib").path))
    #expect(try InstallState.load(from: paths.state).cores.keys.sorted() == ["mesen"])
}

@Test func replacedCoreKeepsUserRemapsAndASharedLibraryName() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    let old = try coreEntry(makeCoreZip(in: dir, name: "old_libretro.dylib"), id: "old", file: "old_libretro.dylib")
    _ = try await installer(manifest(cores: [old]), paths).install(systems: [.nes])
    let remap = paths.coreRemap(libraryName: "Mesen"), folder = remap.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("a".utf8).write(to: remap)
    let perGame = folder.appending(path: "Some Game.rmp")
    try Data("b".utf8).write(to: perGame)

    // Same library name under a new id: retromac's remap still belongs to the current core.
    let newDir = dir.appending(path: "new"); try FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
    let renamed = try coreEntry(makeCoreZip(in: newDir, name: "new_libretro.dylib"), id: "new", file: "new_libretro.dylib")
    _ = try await installer(manifest(cores: [renamed]), paths).install(systems: [.nes])
    #expect(FileManager.default.fileExists(atPath: remap.path))

    // Library name gone too: only retromac's own .rmp goes; the user's per-game remap and its folder stay.
    let otherDir = dir.appending(path: "other"); try FileManager.default.createDirectory(at: otherDir, withIntermediateDirectories: true)
    var other = try coreEntry(makeCoreZip(in: otherDir, name: "other_libretro.dylib"), id: "other", file: "other_libretro.dylib")
    other.libraryName = "Other"
    _ = try await installer(manifest(cores: [other]), paths).install(systems: [.nes])
    #expect(!FileManager.default.fileExists(atPath: remap.path))
    #expect(try read(perGame) == "b")
}

func makeAppZip(in dir: URL, appName: String = "Fake.app", version: String = "1.0") throws -> URL {
    let src = dir.appending(path: "zipsrc-\(UUID().uuidString)")
    try writePlist(version: version, to: src.appending(path: appName))
    try write("license", to: src.appending(path: "LICENSE.txt"))
    let zip = dir.appending(path: "app-\(UUID().uuidString).zip")
    // Like xemu's release zip: the app and a LICENSE.txt at the top level.
    try ProcessRunner().run("/usr/bin/ditto", ["-c", "-k", src.path, zip.path])
    return zip
}

private func assetZip(in dir: URL, fileName: String = "xbox_hdd.qcow2", bytes: String = "blank disk") throws -> URL {
    let staging = dir.appending(path: "asset-\(UUID().uuidString)")
    try write(bytes, to: staging.appending(path: fileName))
    let zip = dir.appending(path: "asset-\(UUID().uuidString).zip")
    try ProcessRunner().run("/usr/bin/ditto", ["-c", "-k", staging.appending(path: fileName).path, zip.path])
    return zip
}

private func hddAsset(_ zip: URL, sha256: String? = nil) throws -> AssetEntry {
    AssetEntry(id: "xemu-hdd", version: "1.0", url: host.serve(zip, host: "github.com"), sha256: try sha256 ?? SHA256File.hex(of: zip),
               license: "MIT", system: .xbox, fileName: "xbox_hdd.qcow2")
}

@Test func installsAppFromZip() async throws {
    let dir = try makeTempDir(), apps = dir.appending(path: "Apps")
    let paths = Paths(home: dir.appending(path: "home"), applications: apps)
    try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
    let report = try await installer(manifest(apps: [try appEntry(makeAppZip(in: dir, version: "0.8"), version: "0.8")]), paths).install(systems: [])
    #expect(report.installed == ["fake"])
    #expect(Installer.bundleVersion(of: apps.appending(path: "Fake.app")) == "0.8")
}

@Test func standaloneInstalledOnlyForItsSystems() async throws {
    let dir = try makeTempDir(), apps = dir.appending(path: "Apps")
    let paths = Paths(home: dir.appending(path: "home"), applications: apps)
    try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
    var entry = try appEntry(makeAppZip(in: dir))
    entry.systems = [.xbox]
    #expect(try await installer(manifest(apps: [entry]), paths).install(systems: [.nes]).installed.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: apps.appending(path: "Fake.app").path))
    #expect(try await installer(manifest(apps: [entry]), paths).install(systems: [.xbox]).installed == ["fake"])
}

@Test func assetInstalledUnzippedOnce() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    var m = manifest(); m.assets = [try hddAsset(assetZip(in: dir))]
    #expect(try await installer(m, paths).install(systems: [.nes]).installed.isEmpty)
    #expect(try await installer(m, paths).install(systems: [.xbox]).installed == ["xemu-hdd"])
    #expect(paths.assetTarget(m.assets[0]) == paths.xemuHDD)
    #expect(try read(paths.xemuHDD) == "blank disk")
}

@Test func existingHardDiskIsNeverReplaced() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    try write("saves", to: paths.xemuHDD)
    var m = manifest(); m.assets = [try hddAsset(assetZip(in: dir))]
    #expect(try await installer(m, paths).install(systems: [.xbox]).installed.isEmpty)
    _ = try await installer(m, paths).install(systems: [.xbox])
    #expect(try read(paths.xemuHDD) == "saves")
}

@Test func assetShaMismatchWritesNothing() async throws {
    let dir = try makeTempDir(), paths = Paths(home: dir.appending(path: "home"), applications: dir.appending(path: "Apps"))
    let zip = try assetZip(in: dir)
    var m = manifest(); m.assets = [try hddAsset(zip, sha256: String(repeating: "0", count: 64))]
    await #expect(throws: InstallError.checksumMismatch(id: "xemu-hdd", expected: String(repeating: "0", count: 64), actual: try SHA256File.hex(of: zip))) {
        try await installer(m, paths).install(systems: [.xbox])
    }
    #expect(!FileManager.default.fileExists(atPath: paths.xemuHDD.path))
}

func makeAppTarXz(in dir: URL, archiveName: String = "Fake-v1.app", version: String = "1.0") throws -> URL {
    let src = dir.appending(path: "tarsrc-\(UUID().uuidString)")
    try writePlist(version: version, to: src.appending(path: archiveName))
    let archive = dir.appending(path: "app-\(UUID().uuidString).tar.xz")
    try ProcessRunner().run("/usr/bin/tar", ["-cJf", archive.path, "-C", src.path, archiveName])
    return archive
}

private func rosettaEntry(_ local: URL) throws -> AppEntry {
    var entry = try appEntry(local)
    entry.arch = .x86_64; entry.rosetta = true; entry.systems = [.ps2]; entry.archiveAppName = "Fake-v1.app"
    return entry
}

@Test func installsAppFromTarXzUnderItsStableName() async throws {
    let dir = try makeTempDir(), apps = dir.appending(path: "Apps")
    let paths = Paths(home: dir.appending(path: "home"), applications: apps)
    try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
    let entry = try rosettaEntry(makeAppTarXz(in: dir, version: "2.8"))
    let report = try await Installer(manifest: manifest(apps: [entry]), paths: paths, downloader: host, runner: ProcessRunner(),
                                     rosettaInstalled: { true }).install(systems: [.ps2])
    #expect(report.installed == ["fake"])
    #expect(Installer.bundleVersion(of: apps.appending(path: "Fake.app")) == "2.8")
    #expect(!FileManager.default.fileExists(atPath: apps.appending(path: "Fake-v1.app").path))
}
@Test func rosettaAppSkippedWithoutRosetta() async throws {
    let dir = try makeTempDir(), apps = dir.appending(path: "Apps")
    let paths = Paths(home: dir.appending(path: "home"), applications: apps)
    try FileManager.default.createDirectory(at: apps, withIntermediateDirectories: true)
    let native = try coreEntry(makeCoreZip(in: dir))
    let report = try await Installer(manifest: manifest(apps: [try rosettaEntry(makeAppTarXz(in: dir))], cores: [native]), paths: paths,
                                     downloader: host, runner: ProcessRunner(), rosettaInstalled: { false }).install(systems: [.ps2, .nes])
    #expect(report.installed == ["mesen"])
    #expect(report.warnings == ["fake: needs Rosetta"])
    #expect(!FileManager.default.fileExists(atPath: apps.appending(path: "Fake.app").path))
}
