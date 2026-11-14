// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation

public enum ImportStatus: Equatable, Hashable, Sendable {
    case identified(SystemID, name: String)
    /// Header says which system, but no DAT matched (or none is imported).
    case unverified(SystemID)
    /// Already in the library (or earlier in this drop); nil system for _Unidentified files.
    case duplicate(SystemID?)
    case unidentified(reason: String)
    case notAGame
    case failed(String)

    /// The system a game will be filed under, for identified and unverified games.
    public var system: SystemID? {
        switch self {
        case .identified(let system, _), .unverified(let system): system
        default: nil
        }
    }
}

public struct ImportCandidate: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// Where it came from, e.g. "pack.zip › a/one.nes".
    public var source: String
    public var status: ImportStatus
    public var destination: URL?
    /// The bytes to write (normalized ROM, or the original for _Unidentified), inside the session dir.
    var staged: URL?
    /// SHA-1 of the bytes that would be written, for duplicate checks.
    var sha1: String?
    /// Disc and console games: every file of the set, copied or (from the session dir) moved.
    var files: [FileCopy] = []
}

struct FileCopy: Equatable, Sendable {
    var from: URL
    var to: URL
    /// True for files extracted into the session dir; never true for the user's own files.
    var move: Bool
}

/// Owns the temp files from one analyze → commit round; removed when released.
public final class ImportSession: Sendable {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "retromac-import-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: dir)
    }
}

/// Identifies dropped files and copies games into the library. Never modifies the originals.
public struct Importer: Sendable {
    static let maxCartridgeBytes = 64 << 20
    static let tooLarge = "too large for a cartridge system"
    /// Archives inside archives are opened one level deep.
    static let maxArchiveDepth = 1
    static let unrecognized = "not a recognized NES, SNES, Genesis or N64 image"
    static let unrecognizedImage = "not a recognized game image"
    /// Archives holding disc images may be large; beyond this they aren't unpacked.
    static let maxArchiveBytes = 16 << 30

    let libraryRoot: URL
    let dats: DatStore
    let runner: any CommandRunner

    public init(libraryRoot: URL, dats: DatStore, runner: any CommandRunner) {
        self.libraryRoot = libraryRoot
        self.dats = dats
        self.runner = runner
    }

    public var unidentifiedDir: URL { libraryRoot.appending(path: "_Unidentified") }

    /// Works out what each dropped item would become; writes nothing under the library.
    public func analyze(_ urls: [URL]) throws -> (ImportSession, [ImportCandidate]) {
        let session = try ImportSession()
        var state = Analysis(session: session, index: dats.load())
        var loose: [(URL, String)] = []
        for url in urls {
            if url.hasDirectoryPath || (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                handleGroup(walk(url).map { ($0.0, "\(url.lastPathComponent)/\($0.1)") }, depth: 0, &state)
            } else {
                loose.append((url, url.lastPathComponent))
            }
        }
        handleGroup(loose, depth: 0, &state)
        return (session, state.candidates)
    }

    struct Analysis {
        let session: ImportSession
        let index: [SystemID: DatFile]
        var candidates: [ImportCandidate] = []
        /// SHA-1 → destination of everything staged so far in this analysis.
        var seen: [String: URL] = [:]
        /// SHA-1 → file, per library folder, built on first use.
        var existing: [URL: [String: URL]] = [:]
        /// "system:serial" of disc games already planned in this analysis.
        var seenDiscs: Set<String> = []
    }

    /// Handles files dropped together; a .bin a .cue in the same group refers to belongs to that cue.
    func handleGroup(_ files: [(URL, String)], depth: Int, _ state: inout Analysis) {
        let cues = files.filter { $0.0.pathExtension.lowercased() == "cue" }
        let claimed = Set(cues.flatMap { DiscSniffer.cueFiles($0.0).map { $0.url.standardizedFileURL.path } })
        for (file, source) in files where !claimed.contains(file.standardizedFileURL.path) {
            if Task.isCancelled { return }
            handle(file, source: source, depth: depth, &state)
        }
    }

    func handle(_ file: URL, source: String, depth: Int, _ state: inout Analysis) {
        let real = file.resolvingSymlinksInPath()
        let ext = file.pathExtension.lowercased()
        if ["zip", "7z"].contains(ext) {
            openArchive(real, source: source, depth: depth, &state)
            return
        }

        if DiscSniffer.extensions.contains(ext), let result = DiscSniffer.sniff(real) {
            switch result {
            case .success(let id): planDisc(real, source: source, id: id, &state)
            case .failure(let unsupported): state.candidates.append(candidate(source, .unidentified(reason: unsupported.reason)))
            }
            return
        }

        let looksLikeROM = RomSniffer.romExtensions.contains(ext)
        let size = (try? real.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        if size > Self.maxCartridgeBytes {
            let reason = DiscSniffer.extensions.contains(ext) && !looksLikeROM ? Self.unrecognizedImage : Self.tooLarge
            state.candidates.append(candidate(source, looksLikeROM || DiscSniffer.extensions.contains(ext) ? .unidentified(reason: reason) : .notAGame))
            return
        }
        // Other files (PDFs, photos…) are only read in full when their first bytes carry a ROM signature.
        if !looksLikeROM, !RomSniffer.hasMagic(Self.read(real, upTo: 0x200) ?? Data()) {
            state.candidates.append(candidate(source, .notAGame))
            return
        }
        guard let data = Self.read(real, upTo: Self.maxCartridgeBytes + 1) else {
            state.candidates.append(failed(source, "couldn't read the file"))
            return
        }
        guard data.count <= Self.maxCartridgeBytes else {
            state.candidates.append(candidate(source, looksLikeROM ? .unidentified(reason: Self.tooLarge) : .notAGame))
            return
        }
        guard let sniffed = RomSniffer.sniff(data, ext: ext) else {
            guard looksLikeROM else {
                state.candidates.append(candidate(source, .notAGame))
                return
            }
            stage(source, .unidentified(reason: Self.unrecognized), bytes: data,
                  destination: unidentifiedDir.appending(path: RomSniffer.sanitize(file.lastPathComponent)), &state)
            return
        }

        let system = sniffed.system
        let match = state.index[system].flatMap { dat in sniffed.hashes.lazy.compactMap { dat.entries[$0] }.first }
        let name = RomSniffer.sanitize(match?.name ?? file.deletingPathExtension().lastPathComponent)
        let destination = libraryRoot.appending(path: system.rawValue).appending(path: "\(name).\(sniffed.ext)")
        let status: ImportStatus = match.map { .identified(system, name: $0.name) } ?? .unverified(system)
        stage(source, status, bytes: sniffed.normalized, destination: destination, &state)
    }

    /// Lists the archive first so oversized members are never extracted, then imports each member.
    func openArchive(_ archive: URL, source: String, depth: Int, _ state: inout Analysis) {
        guard depth <= Self.maxArchiveDepth else {
            state.candidates.append(failed(source, "archive nested too deeply"))
            return
        }
        let listing: String
        do {
            listing = try runner.run("/usr/bin/tar", ["-tvf", archive.path])
        } catch {
            state.candidates.append(failed(source, "couldn't open archive: \(Self.firstLine(of: error))"))
            return
        }
        let members: [(size: Int, name: String)] = listing.split(separator: "\n").compactMap { line in
            let columns = line.split(separator: " ", omittingEmptySubsequences: true)
            guard columns.count > 8, let size = Int(columns[4]) else { return nil }
            return (size, columns.dropFirst(8).joined(separator: " "))
        }
        if members.reduce(0, { $0 + $1.size }) > Self.maxArchiveBytes {
            state.candidates.append(candidate(source, .unidentified(reason: "archive too large to unpack")))
            return
        }
        // Big members are only unpacked when they're disc images; anything else that big isn't a cartridge.
        if members.contains(where: { $0.size > Self.maxCartridgeBytes
            && !DiscSniffer.extensions.contains(URL(filePath: $0.name).pathExtension.lowercased()) }) {
            state.candidates.append(candidate(source, .unidentified(reason: Self.tooLarge)))
            return
        }
        let out = state.session.dir.appending(path: UUID().uuidString)
        do {
            try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
            try runner.run("/usr/bin/tar", ["-xf", archive.path, "-C", out.path])
        } catch {
            state.candidates.append(failed(source, "couldn't open archive: \(Self.firstLine(of: error))"))
            return
        }
        handleGroup(walk(out).map { ($0.0, "\(source) › \($0.1)") }, depth: depth + 1, &state)
    }

    /// Names and plans a disc or console game; nothing is read beyond what the sniffer already read.
    func planDisc(_ file: URL, source: String, id: DiscID, _ state: inout Analysis) {
        let system = id.system
        let entry = id.serial.flatMap { serial in
            state.index[system].flatMap { dat in SerialKey.keys(for: serial, system: system).lazy.compactMap { dat.serials[$0] }.first }
        }
        let stem = file.deletingPathExtension().lastPathComponent
        let name = RomSniffer.sanitize(entry?.name ?? NameCleaner.clean(stem, headerTitle: id.title))
        let folder = libraryRoot.appending(path: system.rawValue)
        let ext = file.pathExtension.lowercased()
        let inSession = file.standardizedFileURL.path.hasPrefix(state.session.dir.standardizedFileURL.path)
        var item = candidate(source, entry.map { .identified(system, name: $0.name) } ?? .unverified(system))
        let destination = folder.appending(path: "\(name).\(ext)")
        item.destination = destination

        if ext == "cue" {
            let tracks = DiscSniffer.cueFiles(file)
            if let missing = tracks.first(where: { !FileManager.default.fileExists(atPath: $0.url.path) }) {
                state.candidates.append(failed(source, "the .cue refers to a missing file: \(missing.name)"))
                return
            }
            let names = tracks.count == 1 ? ["\(name).bin"] : tracks.indices.map { "\(name) (Track \($0 + 1)).bin" }
            var sheet = (try? String(contentsOf: file, encoding: .utf8)) ?? (try? String(contentsOf: file, encoding: .isoLatin1)) ?? ""
            for (track, newName) in zip(tracks, names) {
                sheet = sheet.replacingOccurrences(of: "\"\(track.name)\"", with: "\"\(newName)\"")
            }
            let staged = state.session.dir.appending(path: "\(UUID().uuidString).cue")
            guard (try? sheet.write(to: staged, atomically: true, encoding: .utf8)) != nil else {
                state.candidates.append(failed(source, "couldn't stage the file"))
                return
            }
            item.files = [FileCopy(from: staged, to: destination, move: true)]
                + zip(tracks, names).map { FileCopy(from: $0.url, to: folder.appending(path: $1), move: inSession) }
        } else {
            item.files = [FileCopy(from: file, to: destination, move: inSession)]
        }

        let key = id.serial.map { "\(system.rawValue):\(SerialKey.normalize($0))" }
        let payload = item.files.last!
        if (key.map { state.seenDiscs.contains($0) } ?? false) || Self.sameSize(payload.from, payload.to) {
            item.status = .duplicate(system)
            item.files = []
        } else if let key {
            state.seenDiscs.insert(key)
        }
        state.candidates.append(item)
    }

    static func sameSize(_ a: URL, _ b: URL) -> Bool {
        let size = { (url: URL) in try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64 }
        guard let target = size(b) else { return false }
        return size(a) == target
    }

    func stage(_ source: String, _ status: ImportStatus, bytes: Data, destination: URL, _ state: inout Analysis) {
        let sha = Self.sha1(bytes)
        var item = candidate(source, status)
        item.sha1 = sha
        item.destination = destination
        if let earlier = state.seen[sha] ?? libraryFile(sha, in: destination.deletingLastPathComponent(), &state) {
            item.status = .duplicate(status.system)
            item.destination = earlier
            state.candidates.append(item)
            return
        }
        state.seen[sha] = destination
        let staged = state.session.dir.appending(path: "\(UUID().uuidString).\(destination.pathExtension)")
        do {
            try bytes.write(to: staged)
            item.staged = staged
        } catch {
            item = failed(source, "couldn't stage the file")
        }
        state.candidates.append(item)
    }

    /// A file already in `folder` with this SHA-1, from a per-folder index built once per analysis.
    func libraryFile(_ sha: String, in folder: URL, _ state: inout Analysis) -> URL? {
        if state.existing[folder] == nil {
            var index: [String: URL] = [:]
            for (file, relative) in walk(folder) where file.pathExtension != "txt" {
                if let data = Self.read(file, upTo: Self.maxCartridgeBytes + 1), data.count <= Self.maxCartridgeBytes {
                    index[Self.sha1(data)] = folder.appending(path: relative)
                }
            }
            state.existing[folder] = index
        }
        return state.existing[folder]?[sha]
    }

    /// Reads at most `limit` bytes, whatever the file's metadata claims.
    static func read(_ url: URL, upTo limit: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return try? handle.read(upToCount: limit) ?? Data()
    }

    static func firstLine(of error: Error) -> String {
        if case InstallError.commandFailed(_, _, let stderr) = error {
            return stderr.split(separator: "\n").first.map(String.init) ?? "unreadable"
        }
        return error.localizedDescription
    }

    /// Copies identified, unverified and unidentified candidates; returns them with final destinations.
    public func commit(_ session: ImportSession, _ candidates: [ImportCandidate]) throws -> [ImportCandidate] {
        let fm = FileManager.default
        var result: [ImportCandidate] = []
        for var item in candidates {
            defer { result.append(item) }
            if !item.files.isEmpty {
                item = try commitSet(item)
                continue
            }
            guard let staged = item.staged, let wanted = item.destination, let sha = item.sha1 else { continue }
            switch item.status {
            case .identified, .unverified, .unidentified: break
            default: continue
            }
            if existingMatches(wanted, sha) {
                item.status = .duplicate(item.status.system)
                continue
            }
            let destination = Self.freeName(for: wanted)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: staged, to: destination)
            if case .unidentified(let reason) = item.status {
                try (reason + "\n").write(to: destination.appendingPathExtension("txt"), atomically: true, encoding: .utf8)
            }
            item.destination = destination
        }
        return result
    }

    /// Files a disc game's set: a shared " (n)" suffix on collisions, each file written to a temp name
    /// in its folder first and then renamed, so an interrupted copy never sits at the final name.
    func commitSet(_ item: ImportCandidate) throws -> ImportCandidate {
        var item = item
        guard let payload = item.files.last, !Self.sameSize(payload.from, payload.to) else {
            item.status = .duplicate(item.status.system)
            return item
        }
        let fm = FileManager.default
        var suffix = ""
        var n = 2
        while item.files.contains(where: { fm.fileExists(atPath: Self.suffixed($0.to, suffix).path) }) {
            suffix = " (\(n))"
            n += 1
        }
        if !suffix.isEmpty, let cue = item.files.first, cue.to.pathExtension == "cue" {
            var sheet = try String(contentsOf: cue.from, encoding: .utf8)
            for file in item.files.dropFirst() {
                sheet = sheet.replacingOccurrences(of: "\"\(file.to.lastPathComponent)\"",
                                                   with: "\"\(Self.suffixed(file.to, suffix).lastPathComponent)\"")
            }
            try sheet.write(to: cue.from, atomically: true, encoding: .utf8)
        }
        for file in item.files {
            let target = Self.suffixed(file.to, suffix)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let partial = target.deletingLastPathComponent().appending(path: ".retromac-\(UUID().uuidString).part")
            if file.move { try fm.moveItem(at: file.from, to: partial) } else { try fm.copyItem(at: file.from, to: partial) }
            try fm.moveItem(at: partial, to: target)
        }
        item.destination = item.destination.map { Self.suffixed($0, suffix) }
        item.files = []
        return item
    }

    static func suffixed(_ url: URL, _ suffix: String) -> URL {
        guard !suffix.isEmpty else { return url }
        return url.deletingLastPathComponent()
            .appending(path: "\(url.deletingPathExtension().lastPathComponent)\(suffix).\(url.pathExtension)")
    }

    func existingMatches(_ url: URL, _ sha: String) -> Bool {
        guard let data = Self.read(url, upTo: Self.maxCartridgeBytes + 1) else { return false }
        return Self.sha1(data) == sha
    }

    /// `name.ext`, else `name (2).ext`, `name (3).ext`…
    static func freeName(for url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent(), stem = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var n = 2
        while fm.fileExists(atPath: dir.appending(path: "\(stem) (\(n)).\(ext)").path) { n += 1 }
        return dir.appending(path: "\(stem) (\(n)).\(ext)")
    }

    /// Regular, non-hidden files under `root` with their root-relative paths.
    func walk(_ root: URL) -> [(URL, String)] {
        let base = root.standardizedFileURL.path + "/"
        let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
        var files: [(URL, String)] = []
        while let url = walker?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = url.standardizedFileURL.path
            files.append((url, path.hasPrefix(base) ? String(path.dropFirst(base.count)) : url.lastPathComponent))
        }
        return files.sorted { $0.1 < $1.1 }
    }

    func candidate(_ source: String, _ status: ImportStatus) -> ImportCandidate {
        ImportCandidate(id: UUID(), source: source, status: status, destination: nil, staged: nil, sha1: nil, files: [])
    }

    func failed(_ source: String, _ reason: String) -> ImportCandidate {
        candidate(source, .failed(reason))
    }

    static func sha1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
