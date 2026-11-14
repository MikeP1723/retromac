// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Ranged reads from disc images. Detects raw 2352-byte sectors (MODE1/MODE2) by their sync pattern;
/// otherwise treats the file as 2048-byte ISO sectors.
final class SectorReader {
    private let handle: FileHandle
    private let sectorSize: UInt64
    private let userOffset: UInt64

    static let sync: [UInt8] = [0x00] + [UInt8](repeating: 0xFF, count: 10) + [0x00]

    init?(url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        self.handle = handle
        let head = [UInt8](Self.read(handle, at: 0, count: 16) ?? Data())
        if head.count == 16, Array(head[0..<12]) == Self.sync {
            sectorSize = 2352
            userOffset = head[15] == 2 ? 24 : 16
        } else {
            sectorSize = 2048
            userOffset = 0
        }
    }

    deinit {
        try? handle.close()
    }

    /// The 2048 user-data bytes of `sector`, or nil past the end of the file.
    func user(sector: Int) -> [UInt8]? {
        guard let data = Self.read(handle, at: UInt64(sector) * sectorSize + userOffset, count: 2048), data.count == 2048 else {
            return nil
        }
        return [UInt8](data)
    }

    /// `count` user bytes starting at `sector`, spanning sectors as needed.
    func user(sector: Int, bytes count: Int) -> [UInt8]? {
        var out: [UInt8] = []
        var s = sector
        while out.count < count {
            guard let chunk = user(sector: s) else { return nil }
            out += chunk
            s += 1
        }
        return Array(out.prefix(count))
    }

    static func read(_ handle: FileHandle, at offset: UInt64, count: Int) -> Data? {
        do {
            try handle.seek(toOffset: offset)
            return try handle.read(upToCount: count)
        } catch {
            return nil
        }
    }

    static func read(_ url: URL, at offset: UInt64, count: Int) -> [UInt8] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        return [UInt8](read(handle, at: offset, count: count) ?? Data())
    }
}
