// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// ES-DE saves a custom collection's games relative to ROMDirectory (`%ROMPATH%/snes/…`). ROMDirectory was the
/// library until it became an empty folder (see ProfileRenderer), so those entries point at the library instead,
/// or ES-DE drops them the next time the collection is saved.
public enum ESDECollections {
    static let romPath = "%ROMPATH%/"

    public static func merge(existing: String, library: String) -> String {
        existing.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix(romPath) ? library + "/" + $0.dropFirst(romPath.count) : String($0) }
            .joined(separator: "\n")
    }

    /// The user's custom collections, named `custom-<name>.cfg` by ES-DE.
    static func files(paths: Paths) -> [URL] {
        let dir = paths.esdeRoot.appending(path: "collections")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.filter { $0.hasPrefix("custom-") && $0.hasSuffix(".cfg") }.sorted().map { dir.appending(path: $0) }
    }
}
