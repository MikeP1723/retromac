// SPDX-License-Identifier: GPL-3.0-or-later

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
        var out = "<?xml version=\"1.0\"?>\n<!-- Managed by retromac — edits will be overwritten -->\n<systemList>\n"
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
}
