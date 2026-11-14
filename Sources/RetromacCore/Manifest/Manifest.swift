// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum Arch: String, Codable, Sendable {
    case arm64, universal, x86_64
}

/// Where `retromac-tool check-upstream` looks for newer builds.
public struct Upstream: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case githubRelease, gitlabRelease, libretroStable
    }

    public var kind: Kind
    public var project: String
    /// A regex over asset names (GitHub/GitLab) or a URL template with `{version}` (libretro).
    public var assetPattern: String

    public init(kind: Kind, project: String, assetPattern: String) {
        self.kind = kind; self.project = project; self.assetPattern = assetPattern
    }
}

/// retromac's own build, present only in release manifests.
public struct SelfEntry: Codable, Equatable, Sendable {
    public var version: String
    public var url: URL
    public var sha256: String

    public init(version: String, url: URL, sha256: String) {
        self.version = version; self.url = url; self.sha256 = sha256
    }
}

/// An app installed from a dmg into /Applications.
public struct AppEntry: Codable, Equatable, Sendable {
    public var id: String
    public var version: String
    public var url: URL
    public var sha256: String
    public var license: String
    public var arch: Arch
    public var rosetta: Bool
    public var appName: String
    public var upstream: Upstream?

    public init(id: String, version: String, url: URL, sha256: String, license: String,
                arch: Arch, rosetta: Bool, appName: String, upstream: Upstream? = nil) {
        self.id = id; self.version = version; self.url = url; self.sha256 = sha256
        self.license = license; self.arch = arch; self.rosetta = rosetta
        self.appName = appName; self.upstream = upstream
    }
}

/// A libretro core; `file` is the dylib inside the .zip/.7z at `url`.
/// `sha256` is nil for cores libretro publishes only at a mutable `latest/` URL.
public struct CoreEntry: Codable, Equatable, Sendable {
    public var id: String
    public var version: String
    public var system: SystemID
    public var libraryName: String
    public var file: String
    public var url: URL
    public var sha256: String?
    public var license: String
    public var arch: Arch
    public var rosetta: Bool
    public var upstream: Upstream?

    public init(id: String, version: String, system: SystemID, libraryName: String, file: String,
                url: URL, sha256: String?, license: String, arch: Arch, rosetta: Bool, upstream: Upstream? = nil) {
        self.id = id; self.version = version; self.system = system; self.libraryName = libraryName
        self.file = file; self.url = url; self.sha256 = sha256; self.license = license
        self.arch = arch; self.rosetta = rosetta; self.upstream = upstream
    }
}

public struct Manifest: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var manifestVersion: Int
    public var minAppVersion: String
    public var apps: [AppEntry]
    public var cores: [CoreEntry]
    public var retromac: SelfEntry?

    public init(schemaVersion: Int, manifestVersion: Int, minAppVersion: String,
                apps: [AppEntry], cores: [CoreEntry], retromac: SelfEntry? = nil) {
        self.schemaVersion = schemaVersion; self.manifestVersion = manifestVersion
        self.minAppVersion = minAppVersion; self.apps = apps; self.cores = cores; self.retromac = retromac
    }

    public static func bundled() throws -> Manifest {
        guard let url = Resources.url("manifest", ext: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }

    public func core(for system: SystemID) -> CoreEntry? {
        cores.first { $0.system == system }
    }
}
