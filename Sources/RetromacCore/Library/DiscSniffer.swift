// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public struct DiscID: Equatable, Sendable {
    public var system: SystemID
    public var serial: String?
    public var title: String?
    /// 1-based disc number when the header carries one (GameCube/Wii, Saturn).
    public var disc: Int? = nil
    /// Release region as DATs name it ("USA", "Japan", "Europe"), when the image says (Xbox).
    public var region: String? = nil
}

/// Identifies disc and modern-console images from a few header reads; never reads a whole image.
public enum DiscSniffer {
    public struct Unsupported: Error, Equatable {
        public var reason: String
    }

    public static let extensions: Set<String> = [
        "iso", "gcm", "bin", "cue", "img", "chd", "rvz", "wia", "wbfs", "gcz", "xiso",
        "wud", "wux", "wua", "rpx", "wuhb", "nsp", "nsz", "xci", "xcz", "pbp",
    ]

    /// nil when nothing matches; `.failure` for recognized containers retromac can't identify inside.
    public static func sniff(_ url: URL) -> Result<DiscID, Unsupported>? {
        let ext = url.pathExtension.lowercased()
        if ext == "cue" {
            guard let bin = firstDataFile(ofCue: url) else { return nil }
            return sniff(bin)
        }
        let head = SectorReader.read(url, at: 0, count: 0x400)
        if head.starts(with: Array("MComprHD".utf8)) {
            return .failure(Unsupported(reason: "CHD images can't be identified yet — drop the .cue/.bin or .iso instead"))
        }
        if head.starts(with: [0x01, 0xC0, 0x0B, 0xB1]) {
            return .failure(Unsupported(reason: "GCZ images aren't supported — convert to RVZ with Dolphin"))
        }
        if let id = nintendoDisc(head) ?? xbox(url) ?? sectorBased(url) { return .success(id) }
        if head.starts(with: [0x00, 0x50, 0x42, 0x50]) { return .success(DiscID(system: .psx)) }
        if head.starts(with: Array("WUX0".utf8)) || head.starts(with: Array("WUHB".utf8))
            || (head.starts(with: [0x7F, 0x45, 0x4C, 0x46]) && head.count > 7 && head[7] == 0xCA)
            || ["wud", "wua"].contains(ext) {
            return .success(DiscID(system: .wiiu))
        }
        if head.starts(with: Array("PFS0".utf8)) || (head.count >= 0x104 && Array(head[0x100..<0x104]) == Array("HEAD".utf8)) {
            return .success(DiscID(system: .switch))
        }
        return nil
    }

    /// The first FILE in a cue sheet whose first TRACK is a data track, resolved next to the cue.
    public static func firstDataFile(ofCue cue: URL) -> URL? {
        cueFiles(cue).first { $0.dataTrack }?.url
    }

    /// FILE entries of a cue sheet, in order, with whether their first track is data.
    public static func cueFiles(_ cue: URL) -> [(url: URL, name: String, dataTrack: Bool)] {
        guard let text = (try? String(contentsOf: cue, encoding: .utf8)) ?? (try? String(contentsOf: cue, encoding: .isoLatin1)) else {
            return []
        }
        let folder = cue.deletingLastPathComponent()
        let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var files: [(url: URL, name: String, dataTrack: Bool)] = []
        var pending: String?
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.uppercased().hasPrefix("FILE ") {
                pending = fileName(inFileLine: line)
            } else if line.uppercased().hasPrefix("TRACK "), let name = pending {
                // Cue sheets made on Windows often differ from the real file name only in case.
                let actual = onDisk.first { $0.caseInsensitiveCompare(name) == .orderedSame } ?? name
                files.append((folder.appending(path: actual), name, line.uppercased().contains("MODE")))
                pending = nil
            }
        }
        return files
    }

    /// `FILE "name with spaces.bin" BINARY` or the unquoted `FILE name.bin BINARY`.
    static func fileName(inFileLine line: String) -> String? {
        if let match = line.firstMatch(of: /"([^"]+)"/) { return String(match.1) }
        let words = line.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count >= 3 else { return nil }
        return words.dropFirst().dropLast().joined(separator: " ")
    }

    /// GameCube/Wii disc header, plain or inside RVZ/WIA (at 0x58) or WBFS (at 0x200).
    static func nintendoDisc(_ head: [UInt8]) -> DiscID? {
        var offset = 0
        if head.starts(with: [0x52, 0x56, 0x5A, 0x01]) || head.starts(with: [0x57, 0x49, 0x41, 0x01]) { offset = 0x58 }
        if head.starts(with: Array("WBFS".utf8)) { offset = 0x200 }
        guard head.count >= offset + 0x60 else { return nil }
        let h = Array(head[offset..<offset + 0x60])
        let system: SystemID
        if Array(h[0x18..<0x1C]) == [0x5D, 0x1C, 0x9E, 0xA3] {
            system = .wii
        } else if Array(h[0x1C..<0x20]) == [0xC2, 0x33, 0x9F, 0x3D] {
            system = .gc
        } else {
            return nil
        }
        return DiscID(system: system, serial: ascii(h, 0, 4), title: ascii(Array(head[offset + 0x20..<min(head.count, offset + 0x60)]), 0, 0x40),
                      disc: Int(h[6]) + 1)
    }

    /// Xbox XISO (at 0, or after the video partition in full Redump images): title from default.xbe.
    static func xbox(_ url: URL) -> DiscID? {
        for base: UInt64 in [0, 0x1830_0000] {
            let vd = SectorReader.read(url, at: base + 0x10000, count: 0x20)
            guard vd.count == 0x20, vd.starts(with: Array("MICROSOFT*XBOX*MEDIA".utf8)) else { continue }
            let rootSector = UInt64(u32(vd, 0x14)), rootSize = Int(u32(vd, 0x18))
            guard rootSize > 0, rootSize <= 1 << 20 else { return DiscID(system: .xbox) }
            let dir = SectorReader.read(url, at: base + rootSector * 2048, count: rootSize)
            guard let xbeSector = findEntry(dir, named: "default.xbe") else { return DiscID(system: .xbox) }
            let xbeAt = base + UInt64(xbeSector) * 2048
            let header = SectorReader.read(url, at: xbeAt, count: 0x120)
            guard header.count == 0x120, header.starts(with: Array("XBEH".utf8)) else { return DiscID(system: .xbox) }
            let certOffset = UInt64(u32(header, 0x118) &- u32(header, 0x104))
            let cert = SectorReader.read(url, at: xbeAt + certOffset, count: 0xA4)
            guard cert.count == 0xA4 else { return DiscID(system: .xbox) }
            let titleID = u32(cert, 0x08)
            let a = UInt8(titleID >> 24), b = UInt8(titleID >> 16 & 0xFF)
            let serial = (0x20...0x7E).contains(a) && (0x20...0x7E).contains(b)
                ? "\(Character(UnicodeScalar(a)))\(Character(UnicodeScalar(b)))-\(String(format: "%03d", titleID & 0xFFFF))" : nil
            let units = stride(from: 0x0C, to: 0x0C + 80, by: 2).map { UInt16(cert[$0]) | UInt16(cert[$0 + 1]) << 8 }
            let title = String(decoding: units.prefix { $0 != 0 }, as: UTF16.self).trimmingCharacters(in: .whitespaces)
            // Certificate game-region flags; a disc for exactly one region names it.
            let region: String? = switch u32(cert, 0xA0) & 0x7 {
            case 0x1: "USA"
            case 0x2: "Japan"
            case 0x4: "Europe"
            default: nil
            }
            return DiscID(system: .xbox, serial: serial, title: title.isEmpty ? nil : title, region: region)
        }
        return nil
    }

    /// Walks an XDVDFS directory (a binary tree of entries) for a case-insensitive name.
    static func findEntry(_ dir: [UInt8], named name: String) -> UInt32? {
        var stack = [0], seen = Set<Int>()
        while let offset = stack.popLast() {
            guard offset + 14 <= dir.count, seen.insert(offset).inserted else { continue }
            let left = Int(UInt16(dir[offset]) | UInt16(dir[offset + 1]) << 8) * 4
            let right = Int(UInt16(dir[offset + 2]) | UInt16(dir[offset + 3]) << 8) * 4
            let length = Int(dir[offset + 13])
            if offset + 14 + length <= dir.count,
               String(decoding: dir[offset + 14..<offset + 14 + length], as: UTF8.self).lowercased() == name {
                return u32(dir, offset + 4)
            }
            if left > 0 { stack.append(left) }
            if right > 0 { stack.append(right) }
        }
        return nil
    }

    /// Saturn (header in sector 0) and PlayStation 1/2 (ISO9660 SYSTEM.CNF).
    static func sectorBased(_ url: URL) -> DiscID? {
        guard let reader = SectorReader(url: url) else { return nil }
        if let first = reader.user(sector: 0), first.starts(with: Array("SEGA SEGASATURN ".utf8)) {
            let disc = ascii(first, 0x38, 8)?.firstMatch(of: /CD-(\d+)/).flatMap { Int($0.1) }
            return DiscID(system: .saturn, serial: ascii(first, 0x20, 10), title: ascii(first, 0x60, 112), disc: disc)
        }
        guard let pvd = reader.user(sector: 16), Array(pvd[1..<6]) == Array("CD001".utf8) else { return nil }
        let isPlayStation = ascii(pvd, 8, 32) == "PLAYSTATION"
        let rootSector = Int(u32(pvd, 156 + 2)), rootSize = Int(u32(pvd, 156 + 10))
        if rootSize > 0, rootSize <= 64 * 2048, let root = reader.user(sector: rootSector, bytes: rootSize),
           let (cnfSector, cnfSize) = isoEntry(root, named: "SYSTEM.CNF;1"), cnfSize <= 4096,
           let cnf = reader.user(sector: cnfSector, bytes: cnfSize) {
            for line in String(decoding: cnf, as: UTF8.self).split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                let key = parts.first?.uppercased()
                guard parts.count == 2, key == "BOOT" || key == "BOOT2" else { continue }
                return DiscID(system: key == "BOOT2" ? .ps2 : .psx, serial: bootSerial(parts[1]))
            }
        }
        guard isPlayStation else { return nil }
        // PS2 discs carry "PLAYSTATION" too; anything bigger than a CD can only be a PS2 DVD.
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        return DiscID(system: size > 1 << 30 ? .ps2 : .psx)
    }

    /// "cdrom0:\\SLUS_200.62;1" → "SLUS-20062".
    static func bootSerial(_ path: String) -> String? {
        let file = path.split(whereSeparator: { $0 == "\\" || $0 == ":" || $0 == "/" }).last.map(String.init) ?? path
        let stem = file.split(separator: ";").first.map(String.init) ?? file
        let compact = stem.uppercased().filter { $0.isLetter || $0.isNumber }
        guard compact.count > 4, compact.prefix(4).allSatisfy(\.isLetter) else { return nil }
        return compact.prefix(4) + "-" + compact.dropFirst(4)
    }

    /// Finds a file in an ISO9660 directory: (extent sector, size).
    static func isoEntry(_ dir: [UInt8], named name: String) -> (Int, Int)? {
        var i = 0
        while i < dir.count {
            let length = Int(dir[i])
            if length == 0 {
                i = (i / 2048 + 1) * 2048
                continue
            }
            guard i + 33 <= dir.count, i + length <= dir.count else { return nil }
            let nameLength = Int(dir[i + 32])
            if i + 33 + nameLength <= dir.count,
               String(decoding: dir[i + 33..<i + 33 + nameLength], as: UTF8.self).uppercased() == name {
                return (Int(u32(dir, i + 2)), Int(u32(dir, i + 10)))
            }
            i += length
        }
        return nil
    }

    static func u32(_ b: [UInt8], _ o: Int) -> UInt32 {
        guard o + 4 <= b.count else { return 0 }
        return UInt32(b[o]) | UInt32(b[o + 1]) << 8 | UInt32(b[o + 2]) << 16 | UInt32(b[o + 3]) << 24
    }

    static func ascii(_ b: [UInt8], _ offset: Int, _ length: Int) -> String? {
        guard b.count >= offset + length else { return nil }
        let s = String(b[offset..<offset + length].map { (0x20...0x7E).contains($0) ? Character(UnicodeScalar($0)) : " " })
            .trimmingCharacters(in: .whitespaces)
        return s.isEmpty ? nil : s
    }
}

extension DiscID {
    public init(system: SystemID) {
        self.init(system: system, serial: nil, title: nil)
    }
}
