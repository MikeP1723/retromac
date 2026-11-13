// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

/// Serves a GitHub "latest release" response whose only asset is `manifest` (if given).
func serveRelease(tag: String = "v0.2.0", manifest: Manifest?) throws -> URL {
    let dir = try makeTempDir()
    let base = URL(string: "https://api.github.com/repos/test-\(UUID().uuidString)/retromac")!
    var assets: [[String: String]] = []
    if let manifest {
        let file = dir.appending(path: "manifest.json")
        try JSONEncoder().encode(manifest).write(to: file)
        let url = URL(string: "https://github.com/test/retromac/releases/download/\(tag)/manifest.json?\(UUID().uuidString)")!
        host.serve(file, at: url)
        assets.append(["name": "manifest.json", "browser_download_url": url.absoluteString])
    }
    let release = dir.appending(path: "latest.json")
    try JSONSerialization.data(withJSONObject: ["tag_name": tag, "assets": assets]).write(to: release)
    host.serve(release, at: base.appending(path: "releases/latest"))
    return base
}

@Test func returnsValidatedManifest() async throws {
    let base = try serveRelease(manifest: .fixture())
    let latest = try await ReleaseClient(apiBase: base, downloader: host).latest()
    #expect(latest == LatestRelease(tag: "v0.2.0", manifest: .fixture()))
}
@Test func rejectsPolicyViolations() async throws {
    var m = Manifest.fixture(); m.cores[0].url = URL(string: "https://evil.example/mesen.zip")!
    let base = try serveRelease(manifest: m)
    await #expect(throws: UpdateError.policy(["mesen: host evil.example not in allowlist"])) {
        try await ReleaseClient(apiBase: base, downloader: host).latest()
    }
}
@Test func missingManifestAsset() async throws {
    let base = try serveRelease(manifest: nil)
    await #expect(throws: UpdateError.noManifestAsset) {
        try await ReleaseClient(apiBase: base, downloader: host).latest()
    }
}
@Test func coreIndexIsDownloadedAndParsed() async throws {
    let file = try makeTempDir().appending(path: "index")
    try Data("2026-11-13 4a3d52b1 mesen_libretro.dylib.zip\n".utf8).write(to: file)
    let downloader = FixtureDownloader()
    downloader.serve(file, at: CoreIndex.url)
    #expect(try await ReleaseClient(downloader: downloader).coreIndex().entries["mesen_libretro.dylib.zip"]?.crc32 == "4a3d52b1")
}
