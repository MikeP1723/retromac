// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct DatEntry: Codable, Equatable, Sendable {
    /// The No-Intro game name, e.g. "Super Mario Bros. 3 (USA) (Rev 1)".
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

/// One system's games keyed by lowercase SHA-1.
public struct DatFile: Codable, Equatable, Sendable {
    public var system: SystemID
    public var source: String
    public var version: String
    public var entries: [String: DatEntry]
    /// Normalized serial (and GameCube/Wii game ID) → game; empty for cartridge DATs.
    public var serials: [String: DatEntry] = [:]
}

extension DatFile {
    enum CodingKeys: String, CodingKey { case system, source, version, entries, serials }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        system = try c.decode(SystemID.self, forKey: .system)
        source = try c.decode(String.self, forKey: .source)
        version = try c.decode(String.self, forKey: .version)
        entries = try c.decode([String: DatEntry].self, forKey: .entries)
        serials = try c.decodeIfPresent([String: DatEntry].self, forKey: .serials) ?? [:]
    }
}

public enum DatError: Error, Equatable {
    case unknownSystem(String)
    case unsupportedVariant(String)
    case notADat
}

/// Reads logiqx-format DATs as published by No-Intro.
public enum DatParser {
    /// DAT header names (without trailing "(…)" variants) for each system.
    static let systems: [String: SystemID] = [
        "Nintendo - Nintendo Entertainment System": .nes,
        "Nintendo - Super Nintendo Entertainment System": .snes,
        "Sega - Mega Drive - Genesis": .genesis,
        "Nintendo - Nintendo 64": .n64,
        "Sony - PlayStation": .psx,
        "Sony - PlayStation 2": .ps2,
        "Sega - Saturn": .saturn,
        "Nintendo - GameCube": .gc,
        "Nintendo - Wii": .wii,
        "Microsoft - Xbox": .xbox,
    ]

    public static func systemFor(headerName name: String) throws -> SystemID {
        var base = name.trimmingCharacters(in: .whitespaces)
        while let range = base.range(of: #"\s*\([^()]*\)$"#, options: .regularExpression) {
            base.removeSubrange(range)
        }
        guard let system = systems[base] else { throw DatError.unknownSystem(name) }
        // retromac normalizes N64 images to big-endian .z64, so only that DAT's hashes can match.
        if system == .n64 && (name.contains("(ByteSwapped)") || name.contains("(LittleEndian)")) {
            throw DatError.unsupportedVariant("use the BigEndian DAT")
        }
        return system
    }

    public static func parse(_ data: Data) throws -> DatFile {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), let name = reader.headerName else { throw DatError.notADat }

        let system = try systemFor(headerName: name)
        return DatFile(system: system, source: name, version: reader.headerVersion ?? "", entries: reader.entries)
    }

    final class Reader: NSObject, XMLParserDelegate {
        var headerName: String?
        var headerVersion: String?
        var entries: [String: DatEntry] = [:]
        private var inHeader = false
        private var game: String?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            text = ""
            switch element {
            case "header": inHeader = true
            case "game", "machine": game = attributes["name"]
            case "rom":
                if let game, let sha1 = attributes["sha1"], !sha1.isEmpty {
                    entries[sha1.lowercased()] = DatEntry(name: game)
                }
            default: break
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
            switch element {
            case "header": inHeader = false
            case "name" where inHeader: headerName = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case "version" where inHeader: headerVersion = text.trimmingCharacters(in: .whitespacesAndNewlines)
            case "game", "machine": game = nil
            default: break
            }
        }
    }
}
