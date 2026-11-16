// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Sets retromac's few keys in Ryubing's Config.json and keeps every other key as Ryubing wrote it.
public enum RyubingConfig {
    /// nil means leave the file alone: there's no file, it isn't a JSON object, or its version is unknown.
    /// `replacing` is the games folder retromac added before, swapped out when the library moves; any
    /// other folder the user added stays.
    public static func merge(existing: String?, gameDir: String, replacing: String?) -> String? {
        guard let existing,
              var config = (try? JSONSerialization.jsonObject(with: Data(existing.utf8))) as? [String: Any],
              let version = config["version"] as? Int, Ryubing.knownConfigVersions.contains(version)
        else { return nil }
        config["show_confirm_exit"] = false
        config["update_checker_type"] = "Off"
        var dirs = (config["game_dirs"] as? [String] ?? []).filter { $0 != replacing || $0 == gameDir }
        if !dirs.contains(gameDir) { dirs.append(gameDir) }
        config["game_dirs"] = dirs
        guard let data = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
