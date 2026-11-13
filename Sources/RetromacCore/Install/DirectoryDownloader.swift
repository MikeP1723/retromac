// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Serves `<root>/<host>/<path>` for any URL; the app uses it only in debug builds to rehearse
/// updates against a local fake release without changing any other code path.
public struct DirectoryDownloader: Downloader {
    let root: URL

    public init(root: URL) {
        self.root = root
    }

    public func download(_ url: URL, to dest: URL) async throws {
        let source = root.appending(path: url.host() ?? "").appending(path: url.path())
        let fm = FileManager.default
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: source, to: dest)
    }
}
