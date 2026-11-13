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
