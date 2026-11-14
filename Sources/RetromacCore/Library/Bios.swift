// SPDX-License-Identifier: GPL-3.0-or-later
import CryptoKit
import Foundation

/// A console BIOS a core looks for in RetroArch's system folder, identified by MD5 (libretro-core-info).
public struct BiosFile: Equatable, Hashable, Sendable {
    public let system: SystemID
    /// The name the core expects.
    public let fileName: String
    public let region: String
    public let md5: String

    public init(system: SystemID, fileName: String, region: String, md5: String) {
        self.system = system
        self.fileName = fileName
        self.region = region
        self.md5 = md5
    }

    /// Every known BIOS is exactly this size, so nothing else is ever hashed.
    static let size = 524_288

    public static let known: [BiosFile] = [
        BiosFile(system: .psx, fileName: "scph5500.bin", region: "Japan", md5: "8dd7d5296a650fac7319bce665a6a53c"),
        BiosFile(system: .psx, fileName: "scph5501.bin", region: "USA", md5: "490f666e1afb15b7362b406ed1cea246"),
        BiosFile(system: .psx, fileName: "scph5502.bin", region: "Europe", md5: "32736f17079d0b2b7024407c39bd3050"),
        BiosFile(system: .saturn, fileName: "sega_101.bin", region: "Japan", md5: "85ec9ca47d8f6807718151cbcca8b964"),
        BiosFile(system: .saturn, fileName: "mpr-17933.bin", region: "USA/Europe", md5: "3240872c70984b6cbfda1586cab68dbe"),
    ]

    static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The BIOS `file` is, with its bytes, or nil.
    static func match(_ file: URL, in known: [BiosFile]) -> (BiosFile, Data)? {
        guard (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) == size,
              let data = try? Data(contentsOf: file), data.count == size else { return nil }
        let hash = md5(data)
        return known.first { $0.md5 == hash }.map { ($0, data) }
    }
}

public enum BiosStatus {
    /// The BIOS files present in `directory` under the name the core expects and with the right MD5.
    public static func present(in directory: URL, known: [BiosFile] = BiosFile.known) -> [SystemID: [BiosFile]] {
        var found: [SystemID: [BiosFile]] = [:]
        for bios in known {
            guard let (match, _) = BiosFile.match(directory.appending(path: bios.fileName), in: [bios]) else { continue }
            found[match.system, default: []].append(match)
        }
        return found
    }
}
