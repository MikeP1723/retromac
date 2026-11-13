// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

@Test func replacesOwnedKeyPreservingEverythingElse() {
    let input = "# user comment\nvideo_fullscreen = \"false\"\n\nmenu_driver = \"ozone\"\n"
    #expect(RetroArchConfig.merge(existing: input, owned: ["video_fullscreen": "true"])
        == "# user comment\nvideo_fullscreen = \"true\"\n\nmenu_driver = \"ozone\"\n")
}
@Test func appendsMissingKeysSorted() {
    #expect(RetroArchConfig.merge(existing: "a = \"1\"\n", owned: ["z": "2", "m": "3"])
        == "a = \"1\"\nm = \"3\"\nz = \"2\"\n")
}
@Test func handlesUnquotedAndCRLFAndDuplicates() {
    let input = "video_fullscreen = false\r\nx = \"1\"\r\nvideo_fullscreen = \"false\"\r\n"
    #expect(RetroArchConfig.merge(existing: input, owned: ["video_fullscreen": "true"])
        == "video_fullscreen = \"true\"\r\nx = \"1\"\r\n")
}
@Test func emptyExistingProducesOwnedOnly() {
    #expect(RetroArchConfig.merge(existing: "", owned: ["a": "1"]) == "a = \"1\"\n")
}
@Test func doesNotMatchKeyPrefix() {
    #expect(RetroArchConfig.merge(existing: "video_fullscreen_x = \"1\"\n", owned: ["video_fullscreen": "true"])
        == "video_fullscreen_x = \"1\"\nvideo_fullscreen = \"true\"\n")
}
@Test func addsMissingTrailingNewline() {
    #expect(RetroArchConfig.merge(existing: "a = \"1\"", owned: [:]) == "a = \"1\"\n")
}
