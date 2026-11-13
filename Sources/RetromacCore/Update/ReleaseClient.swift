// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum UpdateError: Error, Equatable {
    /// The release manifest failed ManifestPolicy; nothing from it is offered.
    case policy([String])
    case noManifestAsset
    case appRunning(String)
    case notManaged(String)
    case nothingToRollBack(String)
    case badSelfBundle(String)
}

public struct LatestRelease: Equatable, Sendable {
    public var tag: String
    public var manifest: Manifest
}

/// Reads the update channel: the latest GitHub release's manifest.json, and libretro's core index.
public struct ReleaseClient: Sendable {
    public static let defaultAPIBase = URL(string: "https://api.github.com/repos/MikeP1723/retromac")!

    let apiBase: URL
    let downloader: any Downloader

    public init(apiBase: URL = defaultAPIBase,
                downloader: any Downloader = URLSessionDownloader(headers: ["Accept": "application/vnd.github+json"])) {
        self.apiBase = apiBase
        self.downloader = downloader
    }

    struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }

        let tag_name: String
        let assets: [Asset]
    }

    public func latest() async throws -> LatestRelease {
        let release = try JSONDecoder().decode(Release.self, from: await fetch(apiBase.appending(path: "releases/latest")))
        guard let asset = release.assets.first(where: { $0.name == "manifest.json" }) else {
            throw UpdateError.noManifestAsset
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: await fetch(asset.browser_download_url))
        let violations = ManifestPolicy.violations(manifest)
        guard violations.isEmpty else { throw UpdateError.policy(violations) }
        return LatestRelease(tag: release.tag_name, manifest: manifest)
    }

    public func coreIndex() async throws -> CoreIndex {
        CoreIndex.parse(String(decoding: try await fetch(CoreIndex.url), as: UTF8.self))
    }

    func fetch(_ url: URL) async throws -> Data {
        let dest = FileManager.default.temporaryDirectory.appending(path: "retromac-fetch-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dest) }
        try await downloader.download(url, to: dest)
        return try Data(contentsOf: dest)
    }
}
