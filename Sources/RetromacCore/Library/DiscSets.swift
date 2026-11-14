// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Keeps a disc system's folder launchable as one ES-DE entry per game: a `.cue` for every bare image,
/// and each multi-disc game in a `Game.m3u/` folder with its playlist (ES-DE's "directories
/// interpreted as files"). Safe to run any number of times.
public enum DiscSets {
    public static let systems: Set<SystemID> = [.psx, .saturn]

    static let images: Set<String> = ["bin", "img", "iso"]
    static let discFiles: Set<String> = ["cue", "chd"]

    /// Runs `organize` on each disc system's folder; a folder that fails is left as it was.
    public static func organizeLibrary(_ libraryRoot: URL) {
        for system in SystemID.allCases where systems.contains(system) {
            let folder = libraryRoot.appending(path: system.rawValue)
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            _ = try? organize(folder)
        }
    }

    /// Returns old → new for every file moved, and each bare image → the cue written for it.
    @discardableResult
    public static func organize(_ folder: URL) throws -> [URL: URL] {
        var moves: [URL: URL] = [:]
        try writeCues(in: folder, &moves)
        try groupDiscs(in: folder, &moves)
        try writePlaylists(in: folder)
        return moves
    }

    // MARK: Bare images

    private static func writeCues(in folder: URL, _ moves: inout [URL: URL]) throws {
        let files = try topLevelFiles(folder)
        let referenced = Set(files.filter { $0.pathExtension.lowercased() == "cue" }
            .flatMap { DiscSniffer.cueFiles($0).map { $0.url.standardizedFileURL.path.lowercased() } })
        for image in files where images.contains(image.pathExtension.lowercased()) {
            guard !referenced.contains(image.standardizedFileURL.path.lowercased()) else { continue }
            // A quote or line break in the name would write extra lines into the cue (and pull another game's
            // file into it); such a file is filed but gets no cue.
            // Line breaks are what DiscSniffer splits on (Character.isNewline, which includes U+2028/U+2029).
            let name = image.lastPathComponent
            guard !name.contains(where: { $0 == "\"" || $0.isNewline }),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { continue }
            let cue = image.deletingPathExtension().appendingPathExtension("cue")
            guard !FileManager.default.fileExists(atPath: cue.path), let mode = trackMode(image) else { continue }
            try "FILE \"\(image.lastPathComponent)\" BINARY\n  TRACK 01 \(mode)\n    INDEX 01 00:00:00\n"
                .write(to: cue, atomically: true, encoding: .utf8)
            moves[image] = cue
        }
    }

    /// The cue track type for a single-track image: raw sectors carry the CD sync pattern and a mode
    /// byte; anything else sized in 2048-byte sectors is an ISO. nil when it's neither.
    static func trackMode(_ image: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: image) else { return nil }
        defer { try? handle.close() }
        let head = [UInt8]((try? handle.read(upToCount: 16)) ?? Data())
        let sync: [UInt8] = [0x00] + [UInt8](repeating: 0xFF, count: 10) + [0x00]
        if head.count == 16, Array(head[0..<12]) == sync {
            switch head[15] {
            case 1: return "MODE1/2352"
            case 2: return "MODE2/2352"
            default: return nil
            }
        }
        let size = (try? image.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return size > 0 && size % 2048 == 0 ? "MODE1/2048" : nil
    }

    // MARK: Multi-disc sets

    /// "Game (USA) (Disc 2).cue" → ("Game (USA)", 2).
    static func disc(_ file: URL) -> (base: String, number: Int)? {
        guard discFiles.contains(file.pathExtension.lowercased()) else { return nil }
        let stem = file.deletingPathExtension().lastPathComponent
        guard let match = stem.firstMatch(of: /\s*\(Disc (\d+)\)/), let number = Int(match.1) else { return nil }
        let base = stem.replacingCharacters(in: match.range, with: "").trimmingCharacters(in: .whitespaces)
        return base.isEmpty ? nil : (base, number)
    }

    private static func groupDiscs(in folder: URL, _ moves: inout [URL: URL]) throws {
        let fm = FileManager.default
        let discs = try topLevelFiles(folder).compactMap { file in disc(file).map { (file, $0.base) } }
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        for (base, members) in Dictionary(grouping: discs, by: \.1) {
            let set = folder.appending(path: "\(base).m3u")
            var isDirectory: ObjCBool = false
            let exists = fm.fileExists(atPath: set.path, isDirectory: &isDirectory)
            // A real file already named "Game.m3u" is the user's own playlist: leave the discs alone.
            guard exists ? isDirectory.boolValue : members.count >= 2 else { continue }
            try fm.createDirectory(at: set, withIntermediateDirectories: true)
            for (file, _) in members {
                // A cue's tracks go first, so a bare image keeps pointing at its cue.
                let tracks = file.pathExtension.lowercased() == "cue" ? DiscSniffer.cueFiles(file).map(\.url) : []
                // Only files directly in this folder: a cue may name "../" paths or symlinks, and
                // retromac never moves anything from outside the library.
                for track in tracks where fm.fileExists(atPath: track.path)
                    && (try? track.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true
                    && track.resolvingSymlinksInPath().standardizedFileURL.deletingLastPathComponent().path == root {
                    try move(track, into: set, &moves, recordOnlyIfNew: true)
                }
                try move(file, into: set, &moves, recordOnlyIfNew: false)
            }
        }
    }

    private static func move(_ file: URL, into set: URL, _ moves: inout [URL: URL], recordOnlyIfNew: Bool) throws {
        let target = set.appending(path: file.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.moveItem(at: file, to: target)
        for (key, value) in moves where value == file { moves[key] = target }
        if !recordOnlyIfNew || moves[file] == nil { moves[file] = target }
    }

    private static func writePlaylists(in folder: URL) throws {
        let fm = FileManager.default
        let sets = try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "m3u" && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        for set in sets {
            var byNumber: [Int: URL] = [:]
            for file in try topLevelFiles(set) {
                guard let (_, number) = disc(file) else { continue }
                // Prefer the CHD once a disc has been converted.
                if byNumber[number] == nil || file.pathExtension.lowercased() == "chd" { byNumber[number] = file }
            }
            guard !byNumber.isEmpty else { continue }
            let playlist = set.appending(path: set.lastPathComponent)
            let content = byNumber.keys.sorted().map { byNumber[$0]!.lastPathComponent + "\n" }.joined()
            if (try? String(contentsOf: playlist, encoding: .utf8)) != content {
                try content.write(to: playlist, atomically: true, encoding: .utf8)
            }
        }
    }

    private static func topLevelFiles(_ folder: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            // Rebuilt from `folder` so returned URLs match the caller's (/var vs /private/var).
            .map { folder.appending(path: $0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
