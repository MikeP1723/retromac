// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// A PlayStation 2 BIOS, recognized the way PCSX2 does (BiosTools.cpp LoadBiosVersion): 4–8 MiB with a
/// 16-byte ROM directory entry named RESET. Every region's dump passes, so there's no hash table.
public enum Ps2Bios {
    static let sizes = 4_194_304...8_388_608

    public static func isBios(_ url: URL) -> Bool {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, sizes.contains(size),
              let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        // Real ROM directories sit near the start (around 0x2700).
        guard let head = try? handle.read(upToCount: 1 << 20) else { return false }
        let reset = Array("RESET".utf8) + [0]
        return head.withUnsafeBytes { bytes in
            stride(from: 0, to: bytes.count - 16, by: 16).contains { i in reset.indices.allSatisfy { bytes[i + $0] == reset[$0] } }
        }
    }

    /// The BIOS PCSX2 should boot: the first (by name) in `folder`.
    public static func first(in folder: URL) -> String? {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { !$0.lastPathComponent.contains(where: \.isNewline) && isBios($0) }.map(\.lastPathComponent).sorted().first
    }
}
