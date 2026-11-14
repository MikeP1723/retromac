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

    /// Why this copy can't replace itself, or nil. Checked before quitting, because the swap
    /// script runs after the app is gone and can't tell the user anything.
    public static func cannotReplace(bundle: URL) -> String? {
        if bundle.path.contains("/AppTranslocation/") {
            return "macOS is running retromac from a temporary location. Move retromac to the Applications folder, then try again."
        }
        let parent = bundle.deletingLastPathComponent().path
        if !FileManager.default.isWritableFile(atPath: parent) {
            return "retromac can't replace itself in \(parent). Move it to the Applications folder, then try again."
        }
        return nil
    }

    /// POSIX sh. Whatever happens, it relaunches the copy that ends up at `target`: the new one,
    /// or the old one restored after a failed move.
    public static func swapScript(pid: Int32, staged: URL, target: URL, previous: URL) -> String {
        let s = quote(staged.path), t = quote(target.path), p = quote(previous.path)
        return """
            while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
            rm -rf \(p)
            if ! mv \(t) \(p); then open \(t); exit 1; fi
            if ! mv \(s) \(t); then mv \(p) \(t); fi
            open \(t)

            """
    }

    static func quote(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
