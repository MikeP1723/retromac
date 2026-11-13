// SPDX-License-Identifier: GPL-3.0-or-later

/// Merges retromac-owned keys into a RetroArch .cfg, leaving every other line untouched.
public enum RetroArchConfig {
    public static func merge(existing: String, owned: [String: String]) -> String {
        let terminator = existing.contains("\r\n") ? "\r\n" : "\n"
        var lines = existing.components(separatedBy: terminator)
        if lines.last == "" { lines.removeLast() }

        var written: Set<String> = []
        var out: [String] = []
        for line in lines {
            guard let key = key(of: line), let value = owned[key] else {
                out.append(line)
                continue
            }
            if written.insert(key).inserted {
                out.append(render(key, value))
            }
        }
        for key in owned.keys.sorted() where !written.contains(key) {
            out.append(render(key, owned[key]!))
        }
        return out.map { $0 + terminator }.joined()
    }

    static func key(of line: String) -> String? {
        guard let eq = line.firstIndex(of: "=") else { return nil }
        let key = line[..<eq].trimmingCharacters(in: .whitespaces)
        return key.isEmpty || key.hasPrefix("#") ? nil : key
    }

    static func render(_ key: String, _ value: String) -> String {
        "\(key) = \"\(value)\""
    }
}
