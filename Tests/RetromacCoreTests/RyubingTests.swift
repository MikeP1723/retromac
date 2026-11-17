// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

/// A temp home and system Applications folder, with Ryubing installed when `installed`.
func ryubingPaths(installed: Bool = true, config: String? = nil) throws -> Paths {
    let dir = try makeTempDir()
    let paths = Paths(home: dir.appending(path: "home"), systemApplications: dir.appending(path: "Applications"))
    if installed {
        try FileManager.default.createDirectory(at: paths.ryubingExecutable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: paths.ryubingExecutable)
    }
    if let config {
        try FileManager.default.createDirectory(at: paths.ryubingConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try config.write(to: paths.ryubingConfig, atomically: true, encoding: .utf8)
    }
    return paths
}

@Test func ryubingStatusFollowsAppAndConfig() throws {
    #expect(Paths(home: URL(filePath: "/tmp/h")).ryubingApp.path == "/Applications/Ryujinx.app")
    let p = try ryubingPaths()
    #expect(p.ryubingExecutable.path.hasSuffix("Applications/Ryujinx.app/Contents/MacOS/Ryujinx"))
    #expect(p.ryubingConfig.path.hasSuffix("home/Library/Application Support/Ryujinx/Config.json"))
    #expect(Ryubing.status(paths: try ryubingPaths(installed: false, config: #"{"version": 70}"#)) == .notInstalled)
    #expect(Ryubing.status(paths: p) == .noConfig)
    #expect(Ryubing.status(paths: try ryubingPaths(config: #"{"version": 71}"#)) == .unknownVersion)
    #expect(Ryubing.status(paths: try ryubingPaths(config: "not json")) == .unknownVersion)
    #expect(Ryubing.status(paths: try ryubingPaths(config: #"{"version": 70}"#)) == .ready)
}

@Test func switchIsLiveOnlyWhenChosenInstalledConfirmedAndKnown() throws {
    let ready = try ryubingPaths(config: #"{"version": 70}"#)
    var p = profile(systems: [.nes, .switch])
    p.switchSetup = SwitchSetup(confirmed: true)
    #expect(Ryubing.isLive(p, paths: ready))
    var notChosen = p; notChosen.systems = [.nes]
    #expect(!Ryubing.isLive(notChosen, paths: ready))
    var unconfirmed = p; unconfirmed.switchSetup = nil
    #expect(!Ryubing.isLive(unconfirmed, paths: ready))
    unconfirmed.switchSetup = SwitchSetup(confirmed: false)
    #expect(!Ryubing.isLive(unconfirmed, paths: ready))
    #expect(!Ryubing.isLive(p, paths: try ryubingPaths(installed: false, config: #"{"version": 70}"#)))
    #expect(!Ryubing.isLive(p, paths: try ryubingPaths(config: #"{"version": 71}"#)))
}

@Test func olderProfilesHaveNoSwitchSetup() throws {
    let url = try makeTempDir().appending(path: "profile.json")
    var p = profile()
    try p.save(to: url)
    p = try Profile.load(from: url)
    #expect(p.switchSetup == nil)
    #expect(!(try String(contentsOf: url, encoding: .utf8)).contains("switchSetup"))
}
