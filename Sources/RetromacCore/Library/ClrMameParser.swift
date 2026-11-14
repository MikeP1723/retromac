// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Serial numbers in a lookup-friendly form.
public enum SerialKey {
    /// Uppercase A–Z and 0–9 only: "slus_000.67" → "SLUS00067".
    public static func normalize(_ s: String) -> String {
        String(s.uppercased().unicodeScalars.filter { ("A"..."Z").contains($0) || ("0"..."9").contains($0) })
    }

    /// Every key a DAT serial is indexed under. Multi-disc serials are comma-separated; GameCube and
    /// Wii serials ("DL-DOL-GW7P-EUR") also index the 4-character game ID a disc header carries.
    public static func keys(for serial: String, system: SystemID) -> [String] {
        var keys: [String] = []
        for part in serial.split(separator: ",") {
            let key = normalize(String(part))
            if !key.isEmpty { keys.append(key) }
            if system == .gc || system == .wii,
               let match = part.uppercased().firstMatch(of: /(?:DOL|RVL)-([A-Z0-9]{4})/) {
                keys.append(String(match.1))
            }
        }
        return keys
    }
}

/// Reads clrmamepro-format DATs as published in libretro-database.
public enum ClrMameParser {
    enum Token: Equatable {
        case open, close, text(String)
    }

    public static func parse(_ data: Data) throws -> DatFile {
        let tokens = tokenize(String(decoding: data, as: UTF8.self))
        var i = 0
        var header: [String: String] = [:]
        var games: [(fields: [String: String], roms: [[String: String]])] = []

        while i < tokens.count {
            guard case .text(let word) = tokens[i], i + 1 < tokens.count, tokens[i + 1] == .open else { i += 1; continue }
            i += 2
            var fields: [String: String] = [:]
            var roms: [[String: String]] = []
            while i < tokens.count, tokens[i] != .close {
                guard case .text(let key) = tokens[i] else { i += 1; continue }
                if i + 1 < tokens.count, tokens[i + 1] == .open {
                    i += 2
                    var nested: [String: String] = [:]
                    while i + 1 < tokens.count, tokens[i] != .close {
                        if case .text(let k) = tokens[i], case .text(let v) = tokens[i + 1] { nested[k] = v }
                        i += 2
                    }
                    i += 1
                    if key == "rom" || key == "disk" { roms.append(nested) }
                } else if i + 1 < tokens.count, case .text(let value) = tokens[i + 1] {
                    fields[key] = value
                    i += 2
                } else {
                    i += 1
                }
            }
            i += 1
            if word == "clrmamepro" { header = fields } else if word == "game" { games.append((fields, roms)) }
        }

        guard let name = header["name"] else { throw DatError.notADat }
        let system = try DatParser.systemFor(headerName: name)
        var dat = DatFile(system: system, source: name, version: header["version"] ?? "", entries: [:])
        for game in games {
            guard let title = game.fields["name"] else { continue }
            let entry = DatEntry(name: title)
            let serials = [game.fields["serial"]] + game.roms.map { $0["serial"] }
            for serial in serials.compactMap({ $0 }) {
                for key in SerialKey.keys(for: serial, system: system) { dat.serials[key] = entry }
            }
            for rom in game.roms {
                if let sha1 = rom["sha1"], !sha1.isEmpty { dat.entries[sha1.lowercased()] = entry }
            }
        }
        return dat
    }

    /// Parentheses, quoted strings (with \" escapes) and bare words.
    static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var chars = s.makeIterator()
        var word = ""
        func flush() {
            if !word.isEmpty { tokens.append(.text(word)); word = "" }
        }
        while let c = chars.next() {
            switch c {
            case "(": flush(); tokens.append(.open)
            case ")": flush(); tokens.append(.close)
            case "\"":
                flush()
                var quoted = ""
                while let q = chars.next(), q != "\"" {
                    if q == "\\", let escaped = chars.next() { quoted.append(escaped) } else { quoted.append(q) }
                }
                tokens.append(.text(quoted))
            case _ where c.isWhitespace: flush()
            default: word.append(c)
            }
        }
        flush()
        return tokens
    }
}
