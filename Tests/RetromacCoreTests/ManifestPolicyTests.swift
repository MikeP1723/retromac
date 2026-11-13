// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func compliantManifestHasNoViolations() {
    #expect(ManifestPolicy.violations(.fixture()).isEmpty)
}
@Test func rejectsNonFreeLicense() {
    var m = Manifest.fixture(); m.cores[0].license = "LicenseRef-NonCommercial"
    #expect(ManifestPolicy.violations(m) == ["mesen: license LicenseRef-NonCommercial not in runtime allowlist"])
}
@Test func rejectsUnmarkedX86() {
    var m = Manifest.fixture(); m.apps[0].arch = .x86_64
    #expect(ManifestPolicy.violations(m) == ["retroarch: x86_64 requires rosetta: true"])
}
@Test func allowsMarkedX86() {
    var m = Manifest.fixture(); m.apps[0].arch = .x86_64; m.apps[0].rosetta = true
    #expect(ManifestPolicy.violations(m).isEmpty)
}
@Test func rejectsBadSha() {
    var m = Manifest.fixture(); m.cores[0].sha256 = "UNPINNED"
    #expect(ManifestPolicy.violations(m) == ["mesen: sha256 must be 64 lowercase hex chars"])
}
@Test func rejectsNonHTTPS() {
    var m = Manifest.fixture(); m.apps[0].url = URL(string: "http://buildbot.libretro.com/a.dmg")!
    #expect(ManifestPolicy.violations(m) == ["retroarch: url must be https"])
}
@Test func rejectsUnlistedHost() {
    var m = Manifest.fixture(); m.cores[0].url = URL(string: "https://evil.example/mesen.zip")!
    #expect(ManifestPolicy.violations(m) == ["mesen: host evil.example not in allowlist"])
}
@Test func vendoredAllowlistExcludesGPL2Only() {
    #expect(!LicensePolicy.vendoredAllowed.contains("GPL-2.0-only"))
    #expect(LicensePolicy.runtimeAllowed.contains("GPL-2.0-only"))
}
