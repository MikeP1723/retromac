// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum ChdError: Error, Equatable {
    case alreadyExists(URL)
}

/// Optional CHD conversion (spec decision 4) with Homebrew's chdman (`rom-tools`, GPL-2.0-or-later).
/// Never vendored: retromac installs it through the user's own Homebrew.
public struct ChdTool: Sendable {
    let runner: any CommandRunner
    let brew: URL
    let chdman: URL

    public init(runner: any CommandRunner, brew: URL = URL(filePath: "/opt/homebrew/bin/brew"),
                chdman: URL = URL(filePath: "/opt/homebrew/bin/chdman")) {
        self.runner = runner
        self.brew = brew
        self.chdman = chdman
    }

    public var hasHomebrew: Bool { FileManager.default.isExecutableFile(atPath: brew.path) }
    public var hasChdman: Bool { FileManager.default.isExecutableFile(atPath: chdman.path) }

    public func installChdman() throws {
        try runner.run(brew.path, ["install", "rom-tools"])
    }

    /// Converts one cue/bin set to `<stem>.chd` beside it. The originals are deleted only after chdman
    /// has verified the new file; any failure leaves them untouched and no `.chd` at the final name.
    public func convert(cue: URL) throws -> URL {
        let fm = FileManager.default
        let folder = cue.deletingLastPathComponent()
        let target = folder.appending(path: cue.deletingPathExtension().lastPathComponent + ".chd")
        guard !fm.fileExists(atPath: target.path) else { throw ChdError.alreadyExists(target) }
        let partial = folder.appending(path: ".retromac-\(UUID().uuidString).chd")
        do {
            try runner.run(chdman.path, ["createcd", "-i", cue.path, "-o", partial.path])
            try runner.run(chdman.path, ["verify", "-i", partial.path])
            try fm.moveItem(at: partial, to: target)
        } catch {
            try? fm.removeItem(at: partial)
            throw error
        }
        // Only the set's own files, directly beside the cue (never a "../" or symlinked track).
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        for track in DiscSniffer.cueFiles(cue).map(\.url)
        where (try? track.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
            && track.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent().path == root {
            try? fm.removeItem(at: track)
        }
        try? fm.removeItem(at: cue)
        return target
    }

    /// Deletes partial `.retromac-*.chd` files left when retromac quit mid-conversion. Never call it
    /// while a conversion is running.
    public static func removeLeftovers(in libraryRoot: URL) {
        for folder in discFolders(libraryRoot) {
            let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
            while let url = walker?.nextObject() as? URL {
                if url.lastPathComponent.hasPrefix(".retromac-"), url.pathExtension.lowercased() == "chd" {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    private static func discFolders(_ libraryRoot: URL) -> [URL] {
        SystemID.allCases.filter { DiscSets.systems.contains($0) }.map { libraryRoot.appending(path: $0.rawValue) }
    }

    /// Every PS1 and Saturn cue in the library, including inside multi-disc folders, by path.
    public static func convertible(in libraryRoot: URL) -> [URL] {
        var cues: [URL] = []
        for folder in discFolders(libraryRoot) {
            let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            while let url = walker?.nextObject() as? URL {
                // A cue with a .chd of its name beside it would only fail with alreadyExists every time.
                guard url.pathExtension.lowercased() == "cue",
                      !FileManager.default.fileExists(atPath: url.deletingPathExtension().appendingPathExtension("chd").path) else { continue }
                cues.append(url)
            }
        }
        return cues.sorted { $0.path < $1.path }
    }
}
