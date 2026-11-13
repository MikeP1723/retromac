// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum LicensePolicy {
    /// Components downloaded at runtime and never linked: any FOSS license.
    public static let runtimeAllowed: Set<String> = [
        "GPL-2.0-only", "GPL-2.0-or-later", "GPL-3.0-only", "GPL-3.0-or-later",
        "LGPL-2.1-or-later", "LGPL-3.0-or-later", "AGPL-3.0-only", "AGPL-3.0-or-later",
        "MPL-2.0", "MIT", "BSD-2-Clause", "BSD-3-Clause", "Zlib", "Apache-2.0",
    ]
    /// Code vendored into or linked by retromac: must be GPLv3-compatible.
    public static let vendoredAllowed: Set<String> = runtimeAllowed.subtracting(["GPL-2.0-only"])
}

public enum ManifestPolicy {
    public static let allowedHosts: Set<String> = ["buildbot.libretro.com", "gitlab.com", "github.com"]

    public static func violations(_ m: Manifest) -> [String] {
        let entries = m.apps.map { ($0.id, $0.license, $0.arch, $0.rosetta, $0.sha256, $0.url) }
            + m.cores.map { ($0.id, $0.license, $0.arch, $0.rosetta, $0.sha256, $0.url) }
        var out: [String] = []
        for (id, license, arch, rosetta, sha, url) in entries {
            if !LicensePolicy.runtimeAllowed.contains(license) {
                out.append("\(id): license \(license) not in runtime allowlist")
            }
            if arch == .x86_64 && !rosetta {
                out.append("\(id): x86_64 requires rosetta: true")
            }
            if !isSHA256(sha) {
                out.append("\(id): sha256 must be 64 lowercase hex chars")
            }
            if url.scheme != "https" {
                out.append("\(id): url must be https")
            }
            if let host = url.host(), !allowedHosts.contains(host) {
                out.append("\(id): host \(host) not in allowlist")
            }
        }
        return out
    }

    static func isSHA256(_ s: String) -> Bool {
        s.count == 64 && s.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }
}
