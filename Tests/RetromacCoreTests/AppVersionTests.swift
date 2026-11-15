// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func appVersionPrefersBundlePlist() {
    #expect(AppVersion.current(infoDictionary: ["CFBundleShortVersionString": "0.4.2"]) == "0.4.2")
}
@Test func appVersionFallsBackOutsideAnAppBundle() {
    #expect(AppVersion.current(infoDictionary: nil) == AppVersion.fallback)
    #expect(SemVer.compare(AppVersion.fallback, "0.1.0") != .orderedAscending)
}
@Test func fallbackMatchesBundledInfoPlist() throws {
    let plist = try #require(NSDictionary(contentsOf: URL(filePath: #filePath)
        .deletingLastPathComponent().appending(path: "../../Support/Info.plist").standardizedFileURL))
    #expect(plist["CFBundleShortVersionString"] as? String == AppVersion.fallback)
}
@Test func onlyAnUnstampedBundleIsADevelopmentBuild() throws {
    #expect(AppVersion.isDevelopmentBuild(infoDictionary: ["CFBundleShortVersionString": "0.1.0", "RetromacDevelopmentBuild": true]))
    #expect(!AppVersion.isDevelopmentBuild(infoDictionary: ["CFBundleShortVersionString": "0.6.0"]))
    #expect(!AppVersion.isDevelopmentBuild(infoDictionary: nil))
    // bundle.sh removes the flag only when RETROMAC_VERSION is set, as the release workflow does.
    let plist = try #require(NSDictionary(contentsOf: URL(filePath: #filePath)
        .deletingLastPathComponent().appending(path: "../../Support/Info.plist").standardizedFileURL))
    #expect(AppVersion.isDevelopmentBuild(infoDictionary: plist as? [String: Any]))
}
