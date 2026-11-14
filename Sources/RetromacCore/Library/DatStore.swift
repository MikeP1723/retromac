// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Imported DATs, one JSON file per system under `~/retromac/dats`.
public struct DatStore: Sendable {
    let dir: URL

    public init(paths: Paths) {
        dir = paths.dats
    }

    /// Parses each .dat/.xml, or every .dat inside a .zip; each one replaces its system's index.
    public func importDats(_ urls: [URL], runner: any CommandRunner) throws -> [DatFile] {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appending(path: "retromac-dats-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }

        var files: [URL] = []
        for url in urls {
            if url.pathExtension.lowercased() == "zip" {
                let out = tmp.appending(path: UUID().uuidString)
                try fm.createDirectory(at: out, withIntermediateDirectories: true)
                try runner.run("/usr/bin/tar", ["-xf", url.path, "-C", out.path])
                let walker = fm.enumerator(at: out, includingPropertiesForKeys: nil)
                while let file = walker?.nextObject() as? URL {
                    if ["dat", "xml"].contains(file.pathExtension.lowercased()) { files.append(file) }
                }
            } else {
                files.append(url)
            }
        }

        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return try files.map { file in
            let dat = try DatParser.parse(Data(contentsOf: file))
            try JSONEncoder().encode(dat).write(to: dir.appending(path: "\(dat.system.rawValue).json"), options: .atomic)
            return dat
        }
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

    public func lookup(_ system: SystemID, sha1: [String]) -> DatEntry? {
        guard let dat = load()[system] else { return nil }
        return sha1.lazy.compactMap { dat.entries[$0.lowercased()] }.first
    }
}
