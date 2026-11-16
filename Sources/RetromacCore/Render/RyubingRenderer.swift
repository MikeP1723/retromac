// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Ryubing's settings: only once Switch is live, and only the keys RyubingConfig owns.
public enum RyubingRenderer {
    public static func files(_ p: Profile, paths: Paths) -> [RenderedFile] {
        guard Ryubing.isLive(p, paths: paths) else { return [] }
        return [RenderedFile(url: paths.ryubingConfig,
                             kind: .ryubingConfig(gameDir: gameDir(p), replacing: p.switchSetup?.gameDir))]
    }

    /// After a successful apply: remembers the games folder retromac added, for `replacing` next time.
    public static func applied(_ p: Profile, paths: Paths) -> Profile {
        guard Ryubing.isLive(p, paths: paths) else { return p }
        var recorded = p
        recorded.switchSetup?.gameDir = gameDir(p)
        return recorded
    }

    static func gameDir(_ p: Profile) -> String { p.libraryRoot.appending(path: SystemID.switch.rawValue).path }
}
