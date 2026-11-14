// SPDX-License-Identifier: GPL-3.0-or-later

/// Dolphin's INI files: `[Section]` headers and `Key = Value` lines, values unquoted to end of line.
/// Dolphin rewrites them on exit, so retromac only ever merges its own keys in.
public enum IniConfig {
    /// Replaces owned keys in place, adds missing ones to the end of their section and missing sections
    /// to the end of the file (sorted), and keeps every other line as it was.
    public static func merge(existing: String, owned: [String: [String: String]]) -> String {
        var lines = existing.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if lines.last == "" { lines.removeLast() }
        var pending = owned
        var out: [String] = []
        var section: String?

        func flush() {
            guard let name = section, let keys = pending[name] else { return }
            // Before the section's trailing blank lines.
            var blanks = 0
            while out.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { out.removeLast(); blanks += 1 }
            for key in keys.keys.sorted() { out.append("\(key) = \(keys[key]!)") }
            out += Array(repeating: "", count: blanks)
            pending[name] = nil
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                flush()
                section = String(trimmed.dropFirst().dropLast())
                out.append(line)
                continue
            }
            if let name = section, let eq = line.firstIndex(of: "="),
               let value = pending[name]?[line[..<eq].trimmingCharacters(in: .whitespaces)] {
                let key = line[..<eq].trimmingCharacters(in: .whitespaces)
                out.append("\(key) = \(value)")
                pending[name]?[key] = nil
                continue
            }
            out.append(line)
        }
        flush()
        for name in pending.keys.sorted() {
            guard let keys = pending[name] else { continue }
            if !out.isEmpty { out.append("") }
            out.append("[\(name)]")
            for key in keys.keys.sorted() { out.append("\(key) = \(keys[key]!)") }
        }
        return out.joined(separator: "\n") + "\n"
    }
}
