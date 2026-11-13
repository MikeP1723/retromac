// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
@testable import RetromacCore

extension Manifest {
    static func fixture() -> Manifest {
        let sha = String(repeating: "a", count: 64)
        func core(_ id: String, _ system: SystemID, _ lib: String) -> CoreEntry {
            CoreEntry(id: id, version: "1.0", system: system, libraryName: lib, file: "\(id)_libretro.dylib",
                      url: URL(string: "https://buildbot.libretro.com/fixture/\(id)_libretro.dylib.zip")!,
                      sha256: sha, license: "GPL-3.0-or-later", arch: .arm64, rosetta: false)
        }
        return Manifest(
            schemaVersion: 1, manifestVersion: 1, minAppVersion: "0.1.0",
            apps: [
                AppEntry(id: "retroarch", version: "1.0", url: URL(string: "https://buildbot.libretro.com/fixture/RetroArch.dmg")!,
                         sha256: sha, license: "GPL-3.0-or-later", arch: .universal, rosetta: false,
                         appName: "RetroArch.app", bundleID: "com.libretro.dist.RetroArch"),
                AppEntry(id: "esde", version: "1.0", url: URL(string: "https://gitlab.com/fixture/ES-DE.dmg")!,
                         sha256: sha, license: "MIT", arch: .arm64, rosetta: false,
                         appName: "ES-DE.app", bundleID: "org.es-de.frontend"),
            ],
            cores: [
                core("mesen", .nes, "Mesen"),
                core("bsnes", .snes, "bsnes"),
                core("blastem", .genesis, "BlastEm"),
                core("mupen64plus_next", .n64, "Mupen64Plus-Next"),
            ])
    }
}
