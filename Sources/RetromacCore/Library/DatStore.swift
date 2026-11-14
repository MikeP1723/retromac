// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum DatImportOutcome: Equatable, Sendable {
    case imported(DatFile)
    case skipped(file: String, reason: String)

    public var imported: DatFile? {
        if case .imported(let dat) = self { return dat }
        return nil
    }

    public var skippedReason: String? {
        if case .skipped(_, let reason) = self { return reason }
        return nil
    }
}

/// Imported DATs, one JSON file per system under `~/retromac/dats`.
public struct DatStore: Sendable {
    let dir: URL

    public init(paths: Paths) {
        dir = paths.dats
    }

    /// Parses each .dat/.xml, or every .dat inside a .zip. DATs for the same system in one import are
    /// merged (e.g. headered + headerless NES), then replace that system's index. Unsupported or
    /// empty DATs are skipped with a reason; only I/O and archive errors throw.
    public func importDats(_ urls: [URL], runner: any CommandRunner) throws -> [DatImportOutcome] {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appending(path: "retromac-dats-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }

        var files: [URL] = []
        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                let out = tmp.appending(path: UUID().uuidString)
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
                try runner.run("/usr/bin/tar", ["-xf", url.path, "-C", out.path])
                let walker = fm.enumerator(at: out, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                while let file = walker?.nextObject() as? URL {
                    if file.lastPathComponent == "__MACOSX" { walker?.skipDescendants(); continue }
                    if ["dat", "xml"].contains(file.pathExtension.lowercased()) { files.append(file) }
                }
            } else {
                files.append(url)
            }
        }

        var outcomes: [DatImportOutcome] = []
        var merged: [SystemID: DatFile] = [:]
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = file.lastPathComponent
            do {
                let data = try Data(contentsOf: file)
                let isXML = String(decoding: data.prefix(64), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<")
                let dat = try isXML ? DatParser.parse(data) : ClrMameParser.parse(data)
                guard !dat.entries.isEmpty || !dat.serials.isEmpty else {
                    outcomes.append(.skipped(file: name, reason: "no games in this DAT"))
                    continue
                }
                if var existing = merged[dat.system] {
                    existing.entries.merge(dat.entries) { old, _ in old }
                    for (key, entries) in dat.serials { entries.forEach { existing.addSerial(key, $0) } }
                    existing.source += " + " + dat.source
                    merged[dat.system] = existing
                } else {
                    merged[dat.system] = dat
                }
                outcomes.append(.imported(dat))
            } catch DatError.unknownSystem(let system) {
                outcomes.append(.skipped(file: name, reason: "\(system) isn't a supported system"))
            } catch DatError.unsupportedVariant(let hint) {
                outcomes.append(.skipped(file: name, reason: hint))
            } catch DatError.notADat {
                outcomes.append(.skipped(file: name, reason: "not a DAT file"))
            }
        }

        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for (system, dat) in merged {
            try JSONEncoder().encode(dat).write(to: dir.appending(path: "\(system.rawValue).json"), options: .atomic)
        }
        return outcomes
    }

    public func load() -> [SystemID: DatFile] {
        var dats: [SystemID: DatFile] = [:]
        for system in SystemID.allCases {
            let url = dir.appending(path: "\(system.rawValue).json")
            if let data = try? Data(contentsOf: url), let dat = try? JSONDecoder().decode(DatFile.self, from: data) {
                dats[system] = dat
            }
        }
        return dats
    }

    /// When a system's index was last written.
    public func updated(_ system: SystemID) -> Date? {
        let url = dir.appending(path: "\(system.rawValue).json")
        return (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    public func lookup(_ system: SystemID, serial: String, disc: Int? = nil) -> DatEntry? {
        load()[system]?.lookup(serial: serial, disc: disc)
    }

    public func lookup(_ system: SystemID, sha1: [String]) -> DatEntry? {
        guard let dat = load()[system] else { return nil }
        return sha1.lazy.compactMap { dat.entries[$0.lowercased()] }.first
    }
}
