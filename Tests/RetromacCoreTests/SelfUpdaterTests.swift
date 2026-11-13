// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

/// A zipped fake retromac.app served at a github.com URL.
func selfRelease(bundleID: String = "petersoft.retromac", version: String = "0.2.0") throws -> (SelfEntry, URL) {
    let dir = try makeTempDir()
    let app = dir.appending(path: "src/retromac.app")
    let plist: NSDictionary = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version]
    try FileManager.default.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
    try plist.write(to: app.appending(path: "Contents/Info.plist"))
    let zip = dir.appending(path: "retromac.zip")
    try ProcessRunner().run("/usr/bin/ditto", ["-c", "-k", "--keepParent", app.path, zip.path])
    let entry = SelfEntry(version: version, url: host.serve(zip, host: "github.com"), sha256: try SHA256File.hex(of: zip))
    return (entry, dir)
}

@Test func swapScriptExact() {
    let script = SelfUpdater.swapScript(pid: 42, staged: URL(filePath: "/t/x/retromac.app"),
                                        target: URL(filePath: "/Applications/retromac.app"),
                                        previous: URL(filePath: "/Users/m/retromac/previous/retromac.app"))
    #expect(script == """
        while kill -0 42 2>/dev/null; do sleep 0.2; done
        rm -rf '/Users/m/retromac/previous/retromac.app'
        mv '/Applications/retromac.app' '/Users/m/retromac/previous/retromac.app' || exit 1
        if ! mv '/t/x/retromac.app' '/Applications/retromac.app'; then mv '/Users/m/retromac/previous/retromac.app' '/Applications/retromac.app'; exit 1; fi
        open '/Applications/retromac.app'

        """)
}
@Test func swapScriptQuotesSpaces() {
    let script = SelfUpdater.swapScript(pid: 1, staged: URL(filePath: "/t/retromac.app"),
                                        target: URL(filePath: "/Apps/My 'Stuff'/retromac.app"),
                                        previous: URL(filePath: "/p/retromac.app"))
    #expect(script.contains("'/Apps/My '\\''Stuff'\\''/retromac.app'"))
}
@Test func stageVerifiesBundle() async throws {
    let (entry, _) = try selfRelease()
    let staged = try await SelfUpdater.stage(entry, in: try makeTempDir(), downloader: host, runner: ProcessRunner())
    #expect(staged.lastPathComponent == "retromac.app")
    #expect(Installer.bundleVersion(of: staged) == "0.2.0")

    let (other, _) = try selfRelease(bundleID: "other")
    await #expect(throws: UpdateError.badSelfBundle("bundle identifier other")) {
        try await SelfUpdater.stage(other, in: try makeTempDir(), downloader: host, runner: ProcessRunner())
    }
}
@Test func stageRejectsVersionMismatch() async throws {
    var (entry, _) = try selfRelease(version: "0.2.0")
    entry.version = "0.3.0"
    await #expect(throws: UpdateError.badSelfBundle("version 0.2.0, expected 0.3.0")) {
        try await SelfUpdater.stage(entry, in: try makeTempDir(), downloader: host, runner: ProcessRunner())
    }
}
@Test func stageRejectsBadSha() async throws {
    var (entry, _) = try selfRelease()
    entry.sha256 = String(repeating: "0", count: 64)
    await #expect(throws: InstallError.self) {
        try await SelfUpdater.stage(entry, in: try makeTempDir(), downloader: host, runner: ProcessRunner())
    }
}
@Test func swapScriptMovesAppsWhenRun() throws {
    let dir = try makeTempDir().appending(path: "with space")
    let staged = dir.appending(path: "staged/retromac.app"), target = dir.appending(path: "Apps/retromac.app")
    let previous = dir.appending(path: "previous/retromac.app")
    try write("new", to: staged.appending(path: "v")); try write("old", to: target.appending(path: "v"))
    try FileManager.default.createDirectory(at: previous.deletingLastPathComponent(), withIntermediateDirectories: true)
    let finished = Process(); finished.executableURL = URL(filePath: "/usr/bin/true")
    try finished.run(); finished.waitUntilExit()
    let script = SelfUpdater.swapScript(pid: finished.processIdentifier, staged: staged, target: target, previous: previous)
        .replacingOccurrences(of: "open '\(target.path)'\n", with: "")
    try ProcessRunner().run("/bin/sh", ["-c", script])
    #expect(try read(target.appending(path: "v")) == "new")
    #expect(try read(previous.appending(path: "v")) == "old")
}
