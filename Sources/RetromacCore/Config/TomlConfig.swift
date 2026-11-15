// SPDX-License-Identifier: GPL-3.0-or-later

public enum TomlValue: Equatable, Sendable {
    case bool(Bool), int(Int), string(String)

    /// Strings as TOML basic strings.
    public var rendered: String {
        switch self {
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .string(let s):
            var out = "\""
            for scalar in s.unicodeScalars {
                switch scalar {
                case "\"": out += "\\\""
                case "\\": out += "\\\\"
                default:
                    if scalar.value < 0x20 || scalar.value == 0x7F {
                        let hex = String(scalar.value, radix: 16, uppercase: true)
                        out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                    } else {
                        out.unicodeScalars.append(scalar)
                    }
                }
            }
            return out + "\""
        }
    }
}

/// xemu's xemu.toml. It only writes `[a.b]` tables and `key = value` lines, the same shape as Dolphin's
/// INI files, so the merge is IniConfig's with TOML-rendered values. xemu rewrites the file on exit.
public enum TomlConfig {
    public static func merge(existing: String, owned: [String: [String: TomlValue]]) -> String {
        IniConfig.merge(existing: existing, owned: owned.mapValues { $0.mapValues(\.rendered) })
    }
}
