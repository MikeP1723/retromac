// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// RetroArch's macOS defaults keep saves, states and playlists in ~/Documents/RetroArch. retromac points
/// them under Application Support with everything else; this moves what's already there across.
public enum RetroArchDocuments {
    /// The folders RetroArch creates in ~/Documents/RetroArch, and where each one lives now.
    static func destinations(_ paths: Paths) -> [(name: String, target: URL)] {
        ["saves", "states", "playlists", "logs", "records", "records_config"].map { ($0, paths.retroarchSupport.appending(path: $0)) }
            + [("system", paths.retroarchSystem)]
    }

    /// Moves every file whose destination is free. Returns the files left in Documents (relative to
    /// ~/Documents/RetroArch): the destination already had its own copy, or iCloud had evicted the file.
    public static func moveIntoSupport(_ paths: Paths) throws -> [String] {
        let docs = paths.retroarchDocuments
        var left: [String] = []
        for (name, target) in destinations(paths) where FileManager.default.fileExists(atPath: docs.appending(path: name).path) {
            try merge(docs.appending(path: name), into: target, label: name, &left)
        }
        removeIfEmpty(docs)
        return left
    }

    private static func merge(_ source: URL, into target: URL, label: String, _ left: inout [String]) throws {
        let fm = FileManager.default
        if (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            for child in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) where child.lastPathComponent != ".DS_Store" {
                try merge(child, into: target.appending(path: child.lastPathComponent), label: "\(label)/\(child.lastPathComponent)", &left)
            }
            removeIfEmpty(source)
        } else if fm.fileExists(atPath: target.path) || isEvicted(source) {
            left.append(label)
        } else {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: source, to: target)
        }
    }

    /// removeItem on a folder is recursive, so only a folder holding nothing but Finder's .DS_Store goes.
    private static func removeIfEmpty(_ folder: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              contents.allSatisfy({ $0 == ".DS_Store" }) else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// A placeholder whose contents are only in iCloud (Desktop & Documents sync); moving it out of the
    /// synced folder isn't safe, so it stays.
    private static func isEvicted(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_flags & UInt32(SF_DATALESS) != 0
    }
}
