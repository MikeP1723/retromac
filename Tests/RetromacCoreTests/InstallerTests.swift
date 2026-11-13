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

func makeAppDmg(in dir: URL, appName: String = "Fake.app", version: String = "1.0") throws -> URL {
    let src = dir.appending(path: "dmgsrc-\(UUID().uuidString)")
    try writePlist(version: version, to: src.appending(path: appName))
    let dmg = dir.appending(path: "app-\(UUID().uuidString).dmg")
    try ProcessRunner().run("/usr/bin/hdiutil", ["create", "-quiet", "-srcfolder", src.path, "-format", "UDZO", "-volname", "Fake", dmg.path])
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
             license: "MIT", arch: .arm64, rosetta: false, appName: "Fake.app", bundleID: "test.fake")
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
    #expect(state.cores["mesen"] == .init(version: "1.0", sha256: entry.sha256!, file: "fake_libretro.dylib"))
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
