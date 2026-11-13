// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

/// ES-DE custom_systems/es_systems.xml: overrides the bundled entries so each system
/// launches the retromac-chosen core.
public enum ESDESystems {
    struct Info {
        let fullname: String
        let extensions: [String]
    }

    static let info: [SystemID: Info] = [
        .nes: Info(fullname: "Nintendo Entertainment System", extensions: ["nes", "zip"]),
        .snes: Info(fullname: "Super Nintendo Entertainment System", extensions: ["sfc", "smc", "zip"]),
        .genesis: Info(fullname: "Sega Genesis", extensions: ["md", "gen", "bin", "smd", "zip"]),
        .n64: Info(fullname: "Nintendo 64", extensions: ["z64", "n64", "v64", "zip"]),
    ]

    public static func xml(for systems: Set<SystemID>, manifest: Manifest) -> String {
        var out = "<?xml version=\"1.0\"?>\n<systemList>\n"
        for system in SystemID.allCases where systems.contains(system) {
            guard let core = manifest.core(for: system), let info = info[system] else { continue }
            let exts = info.extensions.flatMap { [".\($0)", ".\($0.uppercased())"] }.joined(separator: " ")
            let name = system.rawValue
            out += """
                <system>
                    <name>\(name)</name>
                    <fullname>\(info.fullname)</fullname>
                    <path>%ROMPATH%/\(name)</path>
                    <extension>\(exts)</extension>
                    <command label="\(core.libraryName)">%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/\(core.file) %ROM%</command>
                    <platform>\(name)</platform>
                    <theme>\(name)</theme>
                </system>

            """
        }
        return out + "</systemList>\n"
    }

    /// Replaces the user's same-named <system> entries with ours and keeps all others.
    public static func merge(existing: String?, ours: String) throws -> String {
        let doc = try XMLDocument(xmlString: existing ?? ours)
        let oursDoc = try XMLDocument(xmlString: ours)
        guard let root = doc.rootElement(), let oursRoot = oursDoc.rootElement() else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let systems = oursRoot.elements(forName: "system")
        let names = Set(systems.compactMap { $0.elements(forName: "name").first?.stringValue })
        for system in root.elements(forName: "system") {
            if let name = system.elements(forName: "name").first?.stringValue, names.contains(name) {
                system.detach()
            }
        }
        for system in systems {
            system.detach()
            root.addChild(system)
        }
        return doc.xmlString(options: [.nodePrettyPrint]) + "\n"
    }
}
