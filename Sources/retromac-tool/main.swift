// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation
import RetromacCore

let usage = """
    usage: retromac-tool verify-manifest
           retromac-tool install --systems nes,snes,genesis,n64 [--home DIR] [--applications DIR]
           retromac-tool apply --profile FILE [--home DIR]
    """

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func paths(_ args: [String]) -> Paths {
    let home = option("--home", in: args).map { URL(filePath: $0) } ?? FileManager.default.homeDirectoryForCurrentUser
    let apps = option("--applications", in: args).map { URL(filePath: $0) } ?? URL(filePath: "/Applications")
    return Paths(home: home, applications: apps)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// Downloads every entry, checks pinned shas, and confirms each core archive holds its dylib.
func verifyManifest() async throws {
    let manifest = try Manifest.bundled()
    var ok = true
    for violation in ManifestPolicy.violations(manifest) {
        print("POLICY \(violation)")
        ok = false
    }
    let tmp = FileManager.default.temporaryDirectory.appending(path: "retromac-verify-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    let entries = manifest.apps.map { ($0.id, $0.url, Optional($0.sha256), nil as String?) }
        + manifest.cores.map { ($0.id, $0.url, $0.sha256, Optional($0.file)) }
    for (id, url, sha, file) in entries {
        let dest = tmp.appending(path: id)
        try await URLSessionDownloader().download(url, to: dest)
        let actual = try SHA256File.hex(of: dest)
        if let sha, sha != actual {
            print("MISMATCH \(id) expected=\(sha) actual=\(actual)")
            ok = false
            continue
        }
        if let file {
            let listing = try ProcessRunner().run("/usr/bin/tar", ["-tf", dest.path])
            guard listing.split(separator: "\n").contains(where: { $0.hasSuffix(file) }) else {
                print("MISSING \(id) archive lacks \(file)")
                ok = false
                continue
            }
        }
        print(sha == nil ? "ok \(id) (unpinned, sha=\(actual))" : "ok \(id)")
    }
    if !ok { exit(1) }
}

func isRunning(_ appName: String) -> Bool {
    NSWorkspace.shared.runningApplications.contains { $0.bundleURL?.lastPathComponent == appName }
}

let args = Array(CommandLine.arguments.dropFirst())
do {
    switch args.first {
    case "verify-manifest":
        try await verifyManifest()
    case "install":
        guard let list = option("--systems", in: args) else { fail(usage) }
        let systems = Set(list.split(separator: ",").map { name in
            guard let s = SystemID(rawValue: String(name)) else { fail("unknown system \(name)") }
            return s
        })
        let installer = Installer(manifest: try Manifest.bundled(), paths: paths(args),
                                  downloader: URLSessionDownloader(), runner: ProcessRunner())
        let report = try await installer.install(systems: systems)
        print("installed: \(report.installed.joined(separator: ", "))")
        print("skipped: \(report.skipped.joined(separator: ", "))")
        report.warnings.forEach { print("warning: \($0)") }
    case "apply":
        guard let file = option("--profile", in: args) else { fail(usage) }
        let manifest = try Manifest.bundled()
        let p = paths(args)
        let files = ProfileRenderer.render(try Profile.load(from: URL(filePath: file)), manifest: manifest,
                                           rules: try DisplayRules.bundled(), paths: p)
        let report = try Applier(paths: p, apps: manifest.apps.map(\.appName), isRunning: isRunning).apply(files)
        report.written.forEach { print("wrote \($0.path)") }
        print("unchanged: \(report.unchanged.count)")
        if let backup = report.backup { print("backup: \(backup.path)") }
    default:
        fail(usage)
    }
} catch {
    fail("error: \(error)")
}
