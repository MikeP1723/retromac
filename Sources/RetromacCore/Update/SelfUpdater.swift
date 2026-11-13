// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Replaces the running retromac.app: stage and verify the new build, then hand the swap to a
/// detached script that waits for this process to exit.
public enum SelfUpdater {
    public static let bundleID = "petersoft.retromac"

    public static func stage(_ entry: SelfEntry, in dir: URL, downloader: any Downloader,
                             runner: any CommandRunner) async throws -> URL {
        let zip = dir.appending(path: "retromac.zip")
        try await downloader.download(entry.url, to: zip)
        let actual = try SHA256File.hex(of: zip)
        guard actual == entry.sha256 else {
            throw InstallError.checksumMismatch(id: "retromac", expected: entry.sha256, actual: actual)
        }
        let extracted = dir.appending(path: "x")
        try runner.run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path])
        let app = extracted.appending(path: "retromac.app")
        let plist = NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist"))
        let id = plist?["CFBundleIdentifier"] as? String ?? "missing"
        guard id == bundleID else { throw UpdateError.badSelfBundle("bundle identifier \(id)") }
        let version = plist?["CFBundleShortVersionString"] as? String ?? "missing"
        guard version == entry.version else { throw UpdateError.badSelfBundle("version \(version), expected \(entry.version)") }
        return app
    }

    /// POSIX sh; restores the old app if the new one can't be moved into place.
    public static func swapScript(pid: Int32, staged: URL, target: URL, previous: URL) -> String {
        let s = quote(staged.path), t = quote(target.path), p = quote(previous.path)
        return """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            rm -rf \(p)
            mv \(t) \(p) || exit 1
            if ! mv \(s) \(t); then mv \(p) \(t); exit 1; fi
            open \(t)

            """
    }

    static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
