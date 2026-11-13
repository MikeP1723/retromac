// SPDX-License-Identifier: GPL-3.0-or-later

/// es_settings.xml is a flat list of elements with no root, so XMLDocument rejects it;
/// edit it line by line instead.
public enum ESDESettings {
    static let header = "<?xml version=\"1.0\"?>"

    public static func merge(existing: String?, romDirectory: String) -> String {
        let line = "<string name=\"ROMDirectory\" value=\"\(xmlEscape(romDirectory))\" />"
        var lines = (existing ?? header + "\n").components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        if let i = lines.firstIndex(where: { $0.contains("name=\"ROMDirectory\"") }) {
            lines[i] = line
        } else {
            lines.append(line)
        }
        return lines.map { $0 + "\n" }.joined()
    }

    static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
