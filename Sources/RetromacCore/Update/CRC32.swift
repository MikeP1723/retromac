// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// IEEE CRC-32, the checksum libretro's .index-extended lists per core.
public enum CRC32 {
    static let table: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func hex(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var crc: UInt32 = 0xFFFF_FFFF
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            for byte in chunk { crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8) }
        }
        return String(format: "%08x", crc ^ 0xFFFF_FFFF)
    }
}
