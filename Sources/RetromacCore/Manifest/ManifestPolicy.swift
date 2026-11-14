// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum LicensePolicy {
    /// Components downloaded at runtime and never linked: any FOSS license.
    public static let runtimeAllowed: Set<String> = [
        "GPL-2.0-only", "GPL-2.0-or-later", "GPL-3.0-only", "GPL-3.0-or-later",
        "LGPL-2.1-or-later", "LGPL-3.0-or-later", "AGPL-3.0-only", "AGPL-3.0-or-later",
        "MPL-2.0", "MIT", "BSD-2-Clause", "BSD-3-Clause", "Zlib", "Apache-2.0",
        // Unversioned "GPL" means any version (GPL §14), so it can be taken as GPLv3.
        "GPL-1.0-or-later", "LicenseRef-PublicDomain",
    ]
    /// Code vendored into or linked by retromac: must be GPLv3-compatible.
    public static let vendoredAllowed: Set<String> = runtimeAllowed.subtracting(["GPL-2.0-only"])
}

public enum ManifestPolicy {
    public static let allowedHosts: Set<String> = ["buildbot.libretro.com", "gitlab.com", "github.com"]
    /// libretro publishes macOS cores only at mutable `latest/` URLs, so these may be unpinned.
    static let unpinnedCoreHost = "buildbot.libretro.com"
    /// retromac only ever updates itself from its own repository's releases.
    static let selfReleasePath = "/MikeP1723/retromac/releases/download/"

    public static func violations(_ m: Manifest) -> [String] {
        var out: [String] = []
        for app in m.apps {
            out += common(app.id, app.license, app.arch, app.rosetta, app.url)
            if !isSHA256(app.sha256) { out.append("\(app.id): sha256 must be 64 lowercase hex chars") }
            out += transport(app.id, app.url)
            out += unsafe(app.id, ["id": app.id, "appName": app.appName])
        }
        for core in m.cores {
            out += common(core.id, core.license, core.arch, core.rosetta, core.url)
            if let sha = core.sha256 {
                if !isSHA256(sha) { out.append("\(core.id): sha256 must be 64 lowercase hex chars") }
            } else if core.url.host() != unpinnedCoreHost {
                out.append("\(core.id): sha256 may be omitted only for cores on \(unpinnedCoreHost)")
            }
            out += transport(core.id, core.url)
            out += unsafe(core.id, ["id": core.id, "file": core.file, "libraryName": core.libraryName])
        }
        if let app = m.retromac {
            if !isSHA256(app.sha256) { out.append("retromac: sha256 must be 64 lowercase hex chars") }
            out += transport("retromac", app.url)
            if app.url.host() != "github.com" {
                out.append("retromac: url host must be github.com")
            } else if !app.url.path().hasPrefix(selfReleasePath) {
                out.append("retromac: url must be a MikeP1723/retromac release asset")
            }
        }
        return out
    }

    static func common(_ id: String, _ license: String, _ arch: Arch, _ rosetta: Bool, _ url: URL) -> [String] {
        var out: [String] = []
        if !LicensePolicy.runtimeAllowed.contains(license) {
            out.append("\(id): license \(license) not in runtime allowlist")
        }
        if arch == .x86_64 && !rosetta {
            out.append("\(id): x86_64 requires rosetta: true")
        }
        return out
    }

    /// https and host allowlist.
    static func transport(_ id: String, _ url: URL) -> [String] {
        var out: [String] = []
        if url.scheme != "https" {
            out.append("\(id): url must be https")
        }
        if let host = url.host(), !allowedHosts.contains(host) {
            out.append("\(id): host \(host) not in allowlist")
        }
        return out
    }

    /// Names joined onto install paths must not escape their directory.
    static func unsafe(_ id: String, _ fields: KeyValuePairs<String, String>) -> [String] {
        fields.compactMap { field, value in
            isSafeComponent(value) ? nil : "\(id): \(field) \(value) is not a single path component"
        }
    }

    static func isSafeComponent(_ s: String) -> Bool {
        !s.isEmpty && !s.hasPrefix(".") && !s.contains("/") && !s.contains(":")
    }

    static func isSHA256(_ s: String) -> Bool {
        s.count == 64 && s.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
}
