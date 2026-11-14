// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Foundation
import RetromacCore

let usage = """
    usage: retromac-tool verify-manifest
           retromac-tool install --systems nes,snes,genesis,n64 [--home DIR] [--applications DIR]
           retromac-tool apply --profile FILE [--home DIR]
           retromac-tool check-upstream [--write] [--manifest FILE]
           retromac-tool release-manifest --version X --zip-url URL --sha SHA
           retromac-tool import-dat FILE... [--home DIR]
           retromac-tool import-games PATH... [--home DIR] [--library DIR] [--dry-run]
    """

/// Positional arguments after the subcommand, skipping options and their values.
func positional(_ args: [String], valued: Set<String>) -> [String] {
    var out: [String] = [], skip = false
    for arg in args.dropFirst() {
        if skip { skip = false; continue }
        if valued.contains(arg) { skip = true; continue }
        if arg.hasPrefix("--") { continue }
        out.append(arg)
    }
    return out
}

func importDats(_ args: [String]) {
    let store = DatStore(paths: paths(args))
    var failed = false
    for file in positional(args, valued: ["--home"]) {
        do {
            for dat in try store.importDats([URL(filePath: file)], runner: ProcessRunner()) {
                print("\(dat.system.rawValue) \(dat.source) \(dat.version) \(dat.entries.count) games")
            }
        } catch {
            print("FAIL \(file) \(error)")
            failed = true
        }
    }
    if failed { exit(1) }
}

func importGames(_ args: [String]) throws {
    let p = paths(args)
    let library = option("--library", in: args).map { URL(filePath: $0) }
        ?? (try? Profile.load(from: p.profile))?.libraryRoot ?? p.defaultLibraryRoot
    let importer = Importer(libraryRoot: library, dats: DatStore(paths: p), runner: ProcessRunner())
    let (session, candidates) = try importer.analyze(positional(args, valued: ["--home", "--library"]).map { URL(filePath: $0) })
    let results = args.contains("--dry-run") ? candidates : try importer.commit(session, candidates)
    for item in results {
        let file = item.destination?.lastPathComponent ?? ""
        switch item.status {
        case .identified(let system, let name): print("identified \(system.rawValue) \(name)")
        case .unverified(let system): print("unverified \(system.rawValue) \(file)")
        case .duplicate(let system): print("duplicate \(system.rawValue) \(file)")
        case .unidentified(let reason): print("unidentified \(reason) \(item.source)")
        case .notAGame: print("skip \(item.source)")
        case .failed(let reason): print("FAIL \(item.source) \(reason)")
        }
    }
}

let defaultManifestPath = "Sources/RetromacCore/Resources/manifest.json"

func encode(_ manifest: Manifest) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return try encoder.encode(manifest) + Data("\n".utf8)
}

/// Compares each app's upstream source against the manifest; with --write, pins newer builds.
func checkUpstream(_ args: [String]) async throws {
    let file = URL(filePath: option("--manifest", in: args) ?? defaultManifestPath)
    var manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: file))
    let downloader = URLSessionDownloader()
    let tmp = FileManager.default.temporaryDirectory.appending(path: "retromac-upstream-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmp) }

    var failed = false, changed = false
    for i in manifest.apps.indices {
        let app = manifest.apps[i]
        guard let upstream = app.upstream else { continue }
        do {
            let body = tmp.appending(path: "\(app.id).body")
            try await downloader.download(UpstreamResolver.endpoint(upstream), to: body)
            guard let candidate = UpstreamResolver.resolve(upstream, body: try Data(contentsOf: body)) else {
                print("FAIL \(app.id) no matching release asset"); failed = true; continue
            }
            guard candidate.version != app.version else { print("same \(app.id) \(app.version)"); continue }
            let asset = tmp.appending(path: "\(app.id).asset")
            try await downloader.download(candidate.url, to: asset)
            manifest.apps[i].version = candidate.version
            manifest.apps[i].url = candidate.url
            manifest.apps[i].sha256 = try SHA256File.hex(of: asset)
            changed = true
            print("bump \(app.id) \(app.version) -> \(candidate.version)")
        } catch {
            print("FAIL \(app.id) \(error)"); failed = true
        }
    }
    if changed && args.contains("--write") {
        manifest.manifestVersion += 1
        let violations = ManifestPolicy.violations(manifest)
        violations.forEach { print("POLICY \($0)") }
        if !violations.isEmpty { exit(1) }
        try encode(manifest).write(to: file)
    }
    if failed { exit(1) }
}

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
    case "import-dat":
        importDats(args)
    case "import-games":
        try importGames(args)
    case "check-upstream":
        try await checkUpstream(args)
    case "release-manifest":
        guard let version = option("--version", in: args), let zip = option("--zip-url", in: args).flatMap(URL.init(string:)),
              let sha = option("--sha", in: args) else { fail(usage) }
        var manifest = try JSONDecoder().decode(Manifest.self,
                                                from: Data(contentsOf: URL(filePath: option("--manifest", in: args) ?? defaultManifestPath)))
        manifest.retromac = SelfEntry(version: version, url: zip, sha256: sha)
        let violations = ManifestPolicy.violations(manifest)
        guard violations.isEmpty else { fail(violations.joined(separator: "\n")) }
        FileHandle.standardOutput.write(try encode(manifest))
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
