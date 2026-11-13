// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

let gitlab = Upstream(kind: .gitlabRelease, project: "es-de/emulationstation-de", assetPattern: #"^ES-DE_.*-arm64\.dmg$"#)
let libretro = Upstream(kind: .libretroStable, project: "RetroArch",
                        assetPattern: "https://buildbot.libretro.com/stable/{version}/apple/osx/universal/RetroArch_Metal.dmg")
let github = Upstream(kind: .githubRelease, project: "dolphin-emu/dolphin", assetPattern: #"^dolphin-.*-universal\.dmg$"#)

// Trimmed from the live APIs on 2026-11-13.
let gitlabBody = #"""
[{"tag_name":"v3.5.0","assets":{"links":[
 {"name":"ES-DE_3.5.0-x64.dmg","url":"https://gitlab.com/es-de/emulationstation-de/-/package_files/357717755/download"},
 {"name":"ES-DE_3.5.0-arm64.dmg","url":"https://gitlab.com/es-de/emulationstation-de/-/package_files/357717468/download"}]}},
 {"tag_name":"v3.4.0","assets":{"links":[]}}]
"""#
let libretroBody = #"""
<a href=".."><a href="/stable/1.21.0/"><a href="/stable/1.22.2/"><a href="/stable/1.9.0/"><a href="/stable/1.22.1/">
"""#
let githubBody = #"""
{"tag_name":"v2512","assets":[
 {"name":"dolphin-2512-x64.dmg","browser_download_url":"https://github.com/dolphin-emu/dolphin/releases/download/2512/dolphin-2512-x64.dmg"},
 {"name":"dolphin-2512-universal.dmg","browser_download_url":"https://github.com/dolphin-emu/dolphin/releases/download/2512/dolphin-2512-universal.dmg"}]}
"""#

@Test func resolvesGitLabRelease() {
    #expect(UpstreamResolver.resolve(gitlab, body: Data(gitlabBody.utf8)) == Candidate(
        version: "3.5.0", url: URL(string: "https://gitlab.com/es-de/emulationstation-de/-/package_files/357717468/download")!))
}
@Test func resolvesLibretroStableIgnoringNonVersionLinks() {
    #expect(UpstreamResolver.resolve(libretro, body: Data(libretroBody.utf8)) == Candidate(
        version: "1.22.2", url: URL(string: "https://buildbot.libretro.com/stable/1.22.2/apple/osx/universal/RetroArch_Metal.dmg")!))
}
@Test func resolvesGitHubRelease() {
    #expect(UpstreamResolver.resolve(github, body: Data(githubBody.utf8)) == Candidate(
        version: "2512", url: URL(string: "https://github.com/dolphin-emu/dolphin/releases/download/2512/dolphin-2512-universal.dmg")!))
}
@Test func unmatchedAssetResolvesNil() {
    let none = Upstream(kind: .gitlabRelease, project: "x/y", assetPattern: "^nope$")
    #expect(UpstreamResolver.resolve(none, body: Data(gitlabBody.utf8)) == nil)
}
@Test func endpoints() {
    #expect(UpstreamResolver.endpoint(gitlab).absoluteString == "https://gitlab.com/api/v4/projects/es-de%2Femulationstation-de/releases")
    #expect(UpstreamResolver.endpoint(libretro).absoluteString == "https://buildbot.libretro.com/stable/")
    #expect(UpstreamResolver.endpoint(github).absoluteString == "https://api.github.com/repos/dolphin-emu/dolphin/releases/latest")
}
