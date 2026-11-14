// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Synthetic cartridge images: real header layouts, filler contents.
func ascii(_ s: String, width: Int) -> [UInt8] {
    Array((s.data(using: .ascii)! + Data(repeating: 0x20, count: width)).prefix(width))
}

func nesROM(prg: Data = Data(repeating: 1, count: 16384)) -> Data {
    Data([0x4E, 0x45, 0x53, 0x1A, 1, 1, 0, 0] + [UInt8](repeating: 0, count: 8)) + prg
}

func snesROM(copier: Bool = false, hiROM: Bool = false, title: String = "SUPER GAME", validChecksum: Bool = true,
             mapMode: UInt8? = nil, size: Int = 0x20000) -> Data {
    var rom = [UInt8](repeating: 0x55, count: size)
    for i in stride(from: 0x7FC0, to: 0x8000, by: 1) { rom[i] = 0 }
    for i in stride(from: 0xFFC0, to: 0x10000, by: 1) { rom[i] = 0 }
    let base = hiROM ? 0xFFC0 : 0x7FC0
    rom.replaceSubrange(base..<base + 21, with: ascii(title, width: 21))
    rom[base + 0x15] = mapMode ?? (hiROM ? 0x21 : 0x20)
    let checksum: UInt16 = 0x1234
    let complement: UInt16 = validChecksum ? ~checksum : 0x0000
    rom[base + 0x1C] = UInt8(complement & 0xFF); rom[base + 0x1D] = UInt8(complement >> 8)
    rom[base + 0x1E] = UInt8(checksum & 0xFF); rom[base + 0x1F] = UInt8(checksum >> 8)
    return (copier ? Data(repeating: 0, count: 512) : Data()) + Data(rom)
}

func genesisROM(overseas: String = "SONIC THE HEDGEHOG", domestic: String = "SONIC JP") -> Data {
    var rom = [UInt8](repeating: 0x11, count: 0x400)
    rom.replaceSubrange(0x100..<0x110, with: ascii("SEGA MEGA DRIVE", width: 16))
    rom.replaceSubrange(0x120..<0x150, with: ascii(domestic, width: 48))
    rom.replaceSubrange(0x150..<0x180, with: ascii(overseas, width: 48))
    return Data(rom)
}

enum N64Order { case z64, v64, n64 }

func n64ROM(order: N64Order, title: String = "MARIO") -> Data {
    var z = [UInt8](repeating: 0x22, count: 0x1000)
    z.replaceSubrange(0..<4, with: [0x80, 0x37, 0x12, 0x40])
    z.replaceSubrange(0x20..<0x34, with: ascii(title, width: 20))
    switch order {
    case .z64: return Data(z)
    case .v64: return Data(stride(from: 0, to: z.count, by: 2).flatMap { [z[$0 + 1], z[$0]] })
    case .n64: return Data(stride(from: 0, to: z.count, by: 4).flatMap { z[$0..<$0 + 4].reversed() })
    }
}
