// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation

public struct Sniffed: Equatable, Sendable {
    public var system: SystemID
    /// The bytes written to the library (N64 as big-endian, SNES without a copier header).
    public var normalized: Data
    /// SHA-1 of the DAT-comparable bytes, then of the original file; deduplicated.
    public var hashes: [String]
    public var headerTitle: String?
    public var ext: String
}

/// Identifies cartridge images from their header bytes.
public enum RomSniffer {
    public static let romExtensions: Set<String> = ["nes", "sfc", "smc", "md", "gen", "bin", "smd", "z64", "n64", "v64"]
    /// The SNES header test is a checksum heuristic that structured non-ROM files can pass, so it
    /// only runs on files named like SNES images.
    static let snesExtensions: Set<String> = ["sfc", "smc", "swc", "fig", "bin"]

    /// True when the first bytes carry an NES, N64 or Genesis signature (cheap pre-check on a prefix).
    public static func hasMagic(_ prefix: Data) -> Bool {
        let b = [UInt8](prefix.prefix(0x104))
        let n64: [[UInt8]] = [[0x80, 0x37, 0x12, 0x40], [0x37, 0x80, 0x40, 0x12], [0x40, 0x12, 0x37, 0x80]]
        return b.starts(with: [0x4E, 0x45, 0x53, 0x1A])
            || n64.contains { b.starts(with: $0) }
            || (b.count >= 0x104 && Array(b[0x100..<0x104]) == Array("SEGA".utf8))
    }

    public static func sniff(_ data: Data, ext: String) -> Sniffed? {
        let bytes = [UInt8](data)
        if bytes.starts(with: [0x4E, 0x45, 0x53, 0x1A]) {
            // No-Intro hashes NES images without the 16-byte iNES header; emulators need it kept.
            return result(.nes, normalized: data, matchBytes: data.dropFirst(16), original: data, title: nil, ext: "nes")
        }
        if let z64 = n64BigEndian(bytes) {
            let normalized = Data(z64)
            return result(.n64, normalized: normalized, matchBytes: normalized, original: data,
                          title: text(z64, 0x20, 20), ext: "z64")
        }
        if bytes.count >= 0x180, Array(bytes[0x100..<0x104]) == Array("SEGA".utf8) {
            let title = text(bytes, 0x150, 48) ?? text(bytes, 0x120, 48)
            return result(.genesis, normalized: data, matchBytes: data, original: data, title: title, ext: "md")
        }
        guard snesExtensions.contains(ext.lowercased()) else { return nil }
        let rom = bytes.count % 1024 == 512 ? Array(bytes.dropFirst(512)) : bytes
        for base in [0x7FC0, 0xFFC0] where rom.count >= base + 0x20 {
            let complement = UInt16(rom[base + 0x1C]) | UInt16(rom[base + 0x1D]) << 8
            let checksum = UInt16(rom[base + 0x1E]) | UInt16(rom[base + 0x1F]) << 8
            // Map mode byte: 0b001x_xxxx for every licensed LoROM/HiROM/ExHiROM layout.
            if checksum ^ complement == 0xFFFF && rom[base + 0x15] & 0xE0 == 0x20 {
                let normalized = Data(rom)
                return result(.snes, normalized: normalized, matchBytes: normalized, original: data,
                              title: text(rom, base, 21), ext: "sfc")
            }
        }
        return nil
    }

    /// Converts .v64 (byte-swapped) and .n64 (little-endian) images to big-endian .z64.
    static func n64BigEndian(_ b: [UInt8]) -> [UInt8]? {
        guard b.count >= 0x40, b.count % 4 == 0 else { return nil }
        switch Array(b[0..<4]) {
        case [0x80, 0x37, 0x12, 0x40]:
            return b
        case [0x37, 0x80, 0x40, 0x12]:
            return stride(from: 0, to: b.count, by: 2).flatMap { [b[$0 + 1], b[$0]] }
        case [0x40, 0x12, 0x37, 0x80]:
            return stride(from: 0, to: b.count, by: 4).flatMap { b[$0..<$0 + 4].reversed() }
        default:
            return nil
        }
    }

    static func result(_ system: SystemID, normalized: Data, matchBytes: Data, original: Data,
                       title: String?, ext: String) -> Sniffed {
        var hashes = [sha1(matchBytes)]
        let full = sha1(original)
        if full != hashes[0] { hashes.append(full) }
        return Sniffed(system: system, normalized: normalized, hashes: hashes, headerTitle: title, ext: ext)
    }

    static func sha1(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Printable ASCII from a fixed-width header field; nil when blank.
    static func text(_ b: [UInt8], _ offset: Int, _ length: Int) -> String? {
        guard b.count >= offset + length else { return nil }
        let chars = b[offset..<offset + length].map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : " " }
        let s = String(chars).trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }

    /// A single safe filename component, at most 200 UTF-8 bytes.
    public static func sanitize(_ name: String) -> String {
        var s = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix(".") { s.removeFirst() }
        s = s.trimmingCharacters(in: .whitespaces)
        while s.utf8.count > 200 { s.removeLast() }
        return s.isEmpty ? "Untitled" : s
    }
}
