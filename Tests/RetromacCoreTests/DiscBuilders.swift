// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Sparse disc images: header bytes at their real offsets, nothing else on disk.
final class SparseImage {
    let url: URL
    private let handle: FileHandle

    init(_ url: URL, size: UInt64) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: size)
    }

    func put(_ bytes: [UInt8], at offset: UInt64) throws {
        try handle.seek(toOffset: offset)
        handle.write(Data(bytes))
    }

    func put(_ text: String, at offset: UInt64) throws { try put(Array(text.utf8), at: offset) }

    func u32le(_ v: UInt32, at offset: UInt64) throws {
        try put([UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)], at: offset)
    }

    func u16le(_ v: UInt16, at offset: UInt64) throws { try put([UInt8(v & 0xFF), UInt8(v >> 8)], at: offset) }

    func close() throws { try handle.close() }
}

/// Writes 2048-byte user sectors either as a plain ISO or as raw 2352-byte MODE2 sectors.
struct SectorWriter {
    let image: SparseImage
    let raw: Bool

    func sector(_ n: Int, _ data: [UInt8]) throws {
        if raw {
            let base = UInt64(n * 2352)
            try image.put([0x00] + [UInt8](repeating: 0xFF, count: 10) + [0x00], at: base)
            try image.put([0, 2, 0, 2], at: base + 12)
            try image.put(data, at: base + 24)
        } else {
            try image.put(data, at: UInt64(n * 2048))
        }
    }
}

/// An ISO9660 disc whose root holds SYSTEM.CNF with `systemCNF` text.
func isoImage(_ url: URL, systemCNF: String?, raw: Bool = false, size: UInt64 = 64 << 20) throws -> URL {
    let image = try SparseImage(url, size: size)
    let w = SectorWriter(image: image, raw: raw)
    try w.sector(0, [UInt8](repeating: 0, count: 2048))
    var pvd = [UInt8](repeating: 0x20, count: 2048)
    pvd.replaceSubrange(0..<6, with: [0x01] + Array("CD001".utf8))
    pvd.replaceSubrange(8..<19, with: Array("PLAYSTATION".utf8))
    var rootRecord = [UInt8](repeating: 0, count: 34)
    rootRecord[0] = 34
    rootRecord.replaceSubrange(2..<6, with: [20, 0, 0, 0])
    rootRecord.replaceSubrange(10..<14, with: [0x00, 0x08, 0, 0])
    pvd.replaceSubrange(156..<190, with: rootRecord)
    try w.sector(16, pvd)
    if let systemCNF {
        let cnf = Array(systemCNF.utf8)
        let name = Array("SYSTEM.CNF;1".utf8)
        var record = [UInt8](repeating: 0, count: 33 + name.count + 1)
        record[0] = UInt8(record.count)
        record.replaceSubrange(2..<6, with: [21, 0, 0, 0])
        record.replaceSubrange(10..<14, with: [UInt8(cnf.count), 0, 0, 0])
        record[32] = UInt8(name.count)
        record.replaceSubrange(33..<33 + name.count, with: name)
        try w.sector(20, record + [UInt8](repeating: 0, count: 2048 - record.count))
        try w.sector(21, cnf + [UInt8](repeating: 0, count: 2048 - cnf.count))
    }
    try image.close()
    return url
}

func saturnImage(_ url: URL, serial: String, title: String) throws -> URL {
    let image = try SparseImage(url, size: 32 << 20)
    try image.put("SEGA SEGASATURN ", at: 0)
    try image.put(serial.padding(toLength: 10, withPad: " ", startingAt: 0), at: 0x20)
    try image.put(title.padding(toLength: 112, withPad: " ", startingAt: 0), at: 0x60)
    try image.close()
    return url
}

enum NintendoWrap { case plain, rvz, wbfs }

func gcmImage(_ url: URL, id: String, wii: Bool, wrap: NintendoWrap = .plain, title: String = "Test Disc",
              size: UInt64 = 64 << 20) throws -> URL {
    let image = try SparseImage(url, size: size)
    let header: UInt64
    switch wrap {
    case .plain: header = 0
    case .rvz: header = 0x58; try image.put([0x52, 0x56, 0x5A, 0x01], at: 0)
    case .wbfs: header = 0x200; try image.put("WBFS", at: 0)
    }
    try image.put(id + "01", at: header)
    try image.put(title, at: header + 0x20)
    if wii { try image.put([0x5D, 0x1C, 0x9E, 0xA3], at: header + 0x18) } else { try image.put([0xC2, 0x33, 0x9F, 0x3D], at: header + 0x1C) }
    try image.close()
    return url
}

func xisoImage(_ url: URL, titleID: UInt32, title: String, redumpOffset: Bool) throws -> URL {
    let base: UInt64 = redumpOffset ? 0x1830_0000 : 0
    let image = try SparseImage(url, size: base + (16 << 20))
    try image.put("MICROSOFT*XBOX*MEDIA", at: base + 0x10000)
    try image.u32le(0x30, at: base + 0x10000 + 0x14)
    try image.u32le(2048, at: base + 0x10000 + 0x18)
    let dir = base + 0x30 * 2048
    try image.u16le(0, at: dir); try image.u16le(0, at: dir + 2)
    try image.u32le(0x40, at: dir + 4); try image.u32le(0x1000, at: dir + 8)
    try image.put([0x20, 11], at: dir + 12)
    try image.put("default.xbe", at: dir + 14)
    let xbe = base + 0x40 * 2048
    try image.put("XBEH", at: xbe)
    try image.u32le(0x10000, at: xbe + 0x104)
    try image.u32le(0x10200, at: xbe + 0x118)
    try image.u32le(titleID, at: xbe + 0x200 + 0x08)
    try image.put(Array(title.utf16).flatMap { [UInt8($0 & 0xFF), UInt8($0 >> 8)] }, at: xbe + 0x200 + 0x0C)
    try image.close()
    return url
}

func magicFile(_ url: URL, _ bytes: [UInt8], at offset: UInt64 = 0, size: UInt64 = 1 << 20) throws -> URL {
    let image = try SparseImage(url, size: size)
    try image.put(bytes, at: offset)
    try image.close()
    return url
}
