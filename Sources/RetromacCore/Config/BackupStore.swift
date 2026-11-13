// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Timestamped copies of files under `home`, laid out by their home-relative path.
public struct BackupStore {
    public let root: URL
    public let home: URL
    let now: () -> Date

    public init(root: URL, home: URL, now: @escaping () -> Date = Date.init) {
        self.root = root
        self.home = home
        self.now = now
    }

    /// Copies each existing file into a new snapshot; nil when none of them exist.
    public func snapshot(_ files: [URL]) throws -> URL? {
        let fm = FileManager.default
        let existing = files.filter { fm.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let snapshot = root.appending(path: formatter.string(from: now()))
        for file in existing {
            let dest = snapshot.appending(path: relativePath(of: file))
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: file, to: dest)
        }
        return snapshot
    }

    public func restore(_ snapshot: URL) throws {
        let fm = FileManager.default
        let base = snapshot.standardizedFileURL.path + "/"
        guard let walker = fm.enumerator(at: snapshot, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let file as URL in walker {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let relative = String(file.standardizedFileURL.path.dropFirst(base.count))
            let dest = home.appending(path: relative)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: file, to: dest)
        }
    }

    public func list() throws -> [URL] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.hasDirectoryPath }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    func relativePath(of file: URL) -> String {
        let base = home.standardizedFileURL.path + "/"
        let path = file.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
    }
}
