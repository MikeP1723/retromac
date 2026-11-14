// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum InstallError: Error, Equatable {
    case checksumMismatch(id: String, expected: String, actual: String)
    case commandFailed(String, Int32, String)
    case appNotFoundInImage(String)
    case fileNotFoundInArchive(String)
    case policy([String])
}

public struct InstallReport: Equatable, Sendable {
    public var installed: [String] = []
    public var skipped: [String] = []
    public var warnings: [String] = []
}

/// What retromac has installed; `managed == false` marks apps that were already present.
public struct InstallState: Codable, Equatable, Sendable {
    public struct App: Codable, Equatable, Sendable {
        public var version: String
        public var sha256: String?
        public var managed: Bool
    }

    public struct Core: Codable, Equatable, Sendable {
        public var version: String
        public var sha256: String
        public var file: String
        /// CRC32 of the installed dylib, compared against libretro's .index-extended.
        public var crc32: String?
    }

    public var manifestVersion: Int
    public var apps: [String: App]
    public var cores: [String: Core]
    /// One rollback generation, written by the updater.
    public var previousApps: [String: App]?
    public var previousCores: [String: Core]?

    public static func load(from url: URL) throws -> InstallState {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return InstallState(manifestVersion: 0, apps: [:], cores: [:])
        }
        return try JSONDecoder().decode(InstallState.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}

public struct Installer: Sendable {
    let manifest: Manifest
    let paths: Paths
    let downloader: any Downloader
    let runner: any CommandRunner

    public init(manifest: Manifest, paths: Paths, downloader: any Downloader, runner: any CommandRunner) {
        self.manifest = manifest
        self.paths = paths
        self.downloader = downloader
        self.runner = runner
    }

    public func install(systems: Set<SystemID>) async throws -> InstallReport {
        let violations = ManifestPolicy.violations(manifest)
        guard violations.isEmpty else { throw InstallError.policy(violations) }
        var state = try InstallState.load(from: paths.state)
        var report = InstallReport()
        let fm = FileManager.default
        removeStaleStaging()

        for app in manifest.apps {
            let target = paths.applications.appending(path: app.appName)
            if fm.fileExists(atPath: target.path) {
                let installed = Self.bundleVersion(of: target) ?? "unknown"
                report.skipped.append(app.id)
                if installed != app.version {
                    report.warnings.append("\(app.id): installed \(installed), manifest pins \(app.version); leaving installed copy")
                }
                if state.apps[app.id] == nil {
                    state.apps[app.id] = .init(version: installed, sha256: nil, managed: false)
                }
                continue
            }
            let staged = try await stageApp(app)
            defer { try? fm.removeItem(at: staged.deletingLastPathComponent()) }
            try fm.moveItem(at: staged, to: target)
            state.apps[app.id] = .init(version: app.version, sha256: app.sha256, managed: true)
            try state.save(to: paths.state)
            report.installed.append(app.id)
        }

        try extractRetroArchAssets()

        for core in manifest.cores where systems.contains(core.system) {
            let target = paths.retroarchCores.appending(path: core.file)
            if let installed = state.cores[core.id], fm.fileExists(atPath: target.path),
               core.sha256 == nil || core.sha256 == installed.sha256 {
                report.skipped.append(core.id)
                continue
            }
            var staged: (dylib: URL, sha256: String, crc32: String)?
            try await withTempDir { tmp in
                let result = try await stageCore(core, in: tmp)
                try fm.createDirectory(at: paths.retroarchCores, withIntermediateDirectories: true)
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.moveItem(at: result.dylib, to: target)
                staged = result
            }
            guard let staged else { continue }
            state.cores[core.id] = .init(version: core.version, sha256: staged.sha256, file: core.file, crc32: staged.crc32)
            try state.save(to: paths.state)
            report.installed.append(core.id)
        }

        state.manifestVersion = manifest.manifestVersion
        try state.save(to: paths.state)
        return report
    }

    /// Downloads, verifies and copies the app into a staging dir beside its target, so moving it
    /// into place is a same-volume rename. The caller removes the staging dir after the move.
    public func stageApp(_ app: AppEntry) async throws -> URL {
        let fm = FileManager.default
        let staging = paths.applications.appending(path: ".retromac-staging-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try await withTempDir { tmp in
                let dmg = try await fetch(app.url, id: app.id, sha256: app.sha256, into: tmp)
                let mount = tmp.appending(path: "mnt")
                // No -quiet: it silently declines a dmg license agreement (ES-DE ships one).
                // Choosing to install the app is the acceptance; answer the prompt with Y.
                try runner.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, dmg.path],
                               input: String(repeating: "Y\n", count: 64))
                defer { _ = try? runner.run("/usr/bin/hdiutil", ["detach", "-quiet", mount.path]) }
                let source = mount.appending(path: app.appName)
                guard fm.fileExists(atPath: source.path) else { throw InstallError.appNotFoundInImage(app.appName) }
                try runner.run("/usr/bin/ditto", [source.path, staging.appending(path: app.appName).path])
            }
            return staging.appending(path: app.appName)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    /// Downloads (verifying the sha when pinned) and extracts a core under `dir`.
    public func stageCore(_ core: CoreEntry, in dir: URL) async throws -> (dylib: URL, sha256: String, crc32: String) {
        let work = dir.appending(path: core.id)
        let extracted = work.appending(path: "x")
        try FileManager.default.createDirectory(at: extracted, withIntermediateDirectories: true)
        let archive = try await fetch(core.url, id: core.id, sha256: core.sha256, into: work)
        let sha = try SHA256File.hex(of: archive)
        try runner.run("/usr/bin/tar", ["-xf", archive.path, "-C", extracted.path])
        guard let found = Self.find(core.file, under: extracted) else {
            throw InstallError.fileNotFoundInArchive(core.file)
        }
        return (found, sha, try CRC32.hex(of: found))
    }

    /// Downloads into `dir` and verifies the checksum (when pinned) before anything else sees the file.
    func fetch(_ url: URL, id: String, sha256: String?, into dir: URL) async throws -> URL {
        let dest = dir.appending(path: "download")
        try await downloader.download(url, to: dest)
        if let sha256 {
            let actual = try SHA256File.hex(of: dest)
            guard actual == sha256 else {
                throw InstallError.checksumMismatch(id: id, expected: sha256, actual: actual)
            }
        }
        return dest
    }

    func withTempDir(_ body: (URL) async throws -> Void) async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "retromac-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir)
    }

    /// RetroArch unpacks assets.zip (shaders, controller autoconfig) only on its own first launch,
    /// which is usually the user's first game; unpack it now so that game has both.
    func extractRetroArchAssets() throws {
        let fm = FileManager.default
        let zip = paths.applications.appending(path: "RetroArch.app/Contents/Resources/assets.zip")
        guard fm.fileExists(atPath: zip.path), !fm.fileExists(atPath: paths.retroarchShadersSlang.path) else { return }
        try fm.createDirectory(at: paths.retroarchSupport, withIntermediateDirectories: true)
        try runner.run("/usr/bin/ditto", ["-x", "-k", zip.path, paths.retroarchSupport.path])
    }

    /// Leftovers from a run that was killed mid-copy.
    func removeStaleStaging() {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: paths.applications.path)) ?? []
        for name in entries where name.hasPrefix(".retromac-staging-") {
            try? fm.removeItem(at: paths.applications.appending(path: name))
        }
    }

    static func bundleVersion(of app: URL) -> String? {
        let plist = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))
        return plist?["CFBundleShortVersionString"] as? String
    }

    /// Finds a regular file (never a symlink) named `name` anywhere under `dir`.
    static func find(_ name: String, under dir: URL) -> URL? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        let walker = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: keys)
        while let url = walker?.nextObject() as? URL {
            guard url.lastPathComponent == name,
                  let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            return url
        }
        return nil
    }
}
