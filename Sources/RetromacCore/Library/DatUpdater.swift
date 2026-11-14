// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

public enum DatUpdateError: Error, Equatable {
    case skipped(String)
}

/// Downloads game databases from libretro-database (clrmamepro DATs), one system at a time.
public enum DatUpdater {
    public static let base = URL(string: "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/")!

    /// Paths under `metadat/`. Wii U and Switch have no usable DAT; they're named from filenames.
    public static let sources: [SystemID: String] = [
        .nes: "no-intro/Nintendo - Nintendo Entertainment System.dat",
        .snes: "no-intro/Nintendo - Super Nintendo Entertainment System.dat",
        .genesis: "no-intro/Sega - Mega Drive - Genesis.dat",
        .n64: "no-intro/Nintendo - Nintendo 64.dat",
        .psx: "redump/Sony - PlayStation.dat",
        .ps2: "redump/Sony - PlayStation 2.dat",
        .saturn: "redump/Sega - Saturn.dat",
        .gc: "redump/Nintendo - GameCube.dat",
        .wii: "redump/Nintendo - Wii.dat",
        .xbox: "redump/Microsoft - Xbox.dat",
    ]

    public static func url(for system: SystemID) -> URL? {
        sources[system].map { base.appending(path: $0) }
    }

    /// Each system is fetched and imported on its own: a failure leaves that system's previous index.
    public static func update(store: DatStore, downloader: any Downloader, runner: any CommandRunner,
                              progress: (@Sendable (_ done: Int, _ total: Int) -> Void)? = nil) async -> [(SystemID, Result<DatFile, Error>)] {
        let tmp = FileManager.default.temporaryDirectory.appending(path: "retromac-datupdate-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        var results: [(SystemID, Result<DatFile, Error>)] = []
        let systems = SystemID.allCases.filter { sources[$0] != nil }
        for (index, system) in systems.enumerated() {
            progress?(index, systems.count)
            guard let url = url(for: system) else { continue }
            do {
                try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
                let file = tmp.appending(path: "\(system.rawValue).dat")
                try await downloader.download(url, to: file)
                switch try store.importDats([file], runner: runner).first {
                case .imported(let dat): results.append((system, .success(dat)))
                case .skipped(_, let reason): results.append((system, .failure(DatUpdateError.skipped(reason))))
                case nil: results.append((system, .failure(DatUpdateError.skipped("empty download"))))
                }
            } catch {
                results.append((system, .failure(error)))
            }
        }
        return results
    }
}
