// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// The last successful update check, so a relaunch inside the check interval still shows
/// what's available without hitting the network again.
public struct UpdateCache {
    public struct Cached: Codable, Equatable, Sendable {
        public var manifest: Manifest
        public var coreIndex: CoreIndex?
    }

    let url: URL

    public init(paths: Paths) {
        url = paths.retromacRoot.appending(path: "update-cache.json")
    }

    public func save(manifest: Manifest, coreIndex: CoreIndex?) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(Cached(manifest: manifest, coreIndex: coreIndex)).write(to: url, options: .atomic)
    }

    public func load() -> Cached? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(Cached.self, from: $0) }
    }
}
