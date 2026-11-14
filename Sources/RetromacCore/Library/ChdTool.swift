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

    /// Every PS1 and Saturn cue in the library, including inside multi-disc folders, by path.
    public static func convertible(in libraryRoot: URL) -> [URL] {
        var cues: [URL] = []
        for system in SystemID.allCases where DiscSets.systems.contains(system) {
            let folder = libraryRoot.appending(path: system.rawValue)
            let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            while let url = walker?.nextObject() as? URL {
                if url.pathExtension.lowercased() == "cue" { cues.append(url) }
            }
        }
        return cues.sorted { $0.path < $1.path }
    }
}
