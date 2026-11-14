// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// Readable names for games that aren't in a database, from GoodTools-style filenames.
public enum NameCleaner {
    static let regions: [String: String] = [
        "U": "USA", "E": "Europe", "J": "Japan", "W": "World", "UE": "USA, Europe", "EU": "USA, Europe",
        "JU": "USA, Japan", "UJ": "USA, Japan", "JUE": "World", "F": "France", "G": "Germany", "S": "Spain",
        "I": "Italy", "K": "Korea", "CH": "China", "B": "Brazil", "A": "Australia", "PD": "Public Domain",
    ]

    public static func clean(_ stem: String, headerTitle: String?) -> String {
        let text = stem.replacingOccurrences(of: "_", with: " ")
        var base = ""
        var tags: [String] = []
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "(" || c == "[", let close = text[i...].firstIndex(of: c == "(" ? ")" : "]") {
                let inner = String(text[text.index(after: i)..<close]).trimmingCharacters(in: .whitespaces)
                if let tag = c == "(" ? paren(inner) : bracket(inner) { tags.append(tag) }
                i = text.index(after: close)
            } else {
                if tags.isEmpty { base.append(c) }
                i = text.index(after: i)
            }
        }
        base = collapse(base)
        if let headerTitle, uninformative(base) { base = titleCase(headerTitle) }
        return RomSniffer.sanitize(([base] + tags).joined(separator: " "))
    }

    static func paren(_ inner: String) -> String {
        "(\(regions[inner.uppercased()] ?? inner))"
    }

    static func bracket(_ inner: String) -> String? {
        if inner == "!" { return nil }
        if inner.hasPrefix("T+") || inner.hasPrefix("T-") {
            let language = inner.dropFirst(2).prefix { $0.isLetter }.prefix(3)
            return language.isEmpty ? "[Translation]" : "[Translation \(language.prefix(1).uppercased() + language.dropFirst().lowercased())]"
        }
        let flags: [(Character, String)] = [("h", "[Hack]"), ("b", "[Bad Dump]"), ("o", "[Overdump]"), ("a", "[Alt]"),
                                            ("f", "[Fixed]"), ("p", "[Pirate]"), ("t", "[Trainer]")]
        guard let first = inner.first,
              let flag = flags.first(where: { $0.0 == first && inner.dropFirst().allSatisfy { $0.isNumber || $0 == "+" } }) else {
            return nil
        }
        return flag.1
    }

    /// Placeholder names a header title should replace: very short, generic, or a bare serial.
    static func uninformative(_ base: String) -> Bool {
        base.count <= 3
            || base.wholeMatch(of: /(?i)(disc|disk|game|track|image|rom)\s*\d*/) != nil
            || base.wholeMatch(of: /(?i)[a-z]{4}[ -]?\d{3}\.?\d{2}/) != nil
    }

    static func titleCase(_ s: String) -> String {
        collapse(s).lowercased().split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    static func collapse(_ s: String) -> String {
        s.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
