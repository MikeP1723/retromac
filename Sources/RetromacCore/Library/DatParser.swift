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
}

public enum DatError: Error, Equatable {
    case unknownSystem(String)
    case unsupportedVariant(String)
    case notADat
}

/// Reads logiqx-format DATs as published by No-Intro.
public enum DatParser {
    static let systems: [(prefix: String, system: SystemID)] = [
        ("Nintendo - Nintendo Entertainment System", .nes),
        ("Nintendo - Super Nintendo Entertainment System", .snes),
        ("Sega - Mega Drive - Genesis", .genesis),
        ("Nintendo - Nintendo 64", .n64),
    ]

    public static func parse(_ data: Data) throws -> DatFile {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), let name = reader.headerName else { throw DatError.notADat }

        guard let system = systems.first(where: { name.hasPrefix($0.prefix) })?.system else {
            throw DatError.unknownSystem(name)
        }
        // retromac normalizes N64 images to big-endian .z64, so only that DAT's hashes can match.
        if system == .n64 && (name.contains("(ByteSwapped)") || name.contains("(LittleEndian)")) {
            throw DatError.unsupportedVariant("use the BigEndian DAT")
        }
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
