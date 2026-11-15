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
        // Never .bin/.iso: track files and bare images are reached through their .cue (see DiscSets).
        .psx: Info(fullname: "Sony PlayStation", extensions: ["cue", "chd", "m3u", "pbp"]),
        .saturn: Info(fullname: "Sega Saturn", extensions: ["cue", "chd", "m3u"]),
        // What the importer files for these; .gcz is refused at import.
        .gc: Info(fullname: "Nintendo GameCube", extensions: ["iso", "gcm", "rvz", "wia", "ciso"]),
        .wii: Info(fullname: "Nintendo Wii", extensions: ["iso", "rvz", "wia", "wbfs", "ciso"]),
        .xbox: Info(fullname: "Microsoft Xbox", extensions: ["iso", "xiso"]),
        .ps2: Info(fullname: "Sony PlayStation 2", extensions: ["iso", "chd"]),
    ]

    /// Standalone emulators: ES-DE find-rule name, executable inside the app, launch command.
    static let standalones: [String: (rule: String, executable: String, label: String, command: String)] = [
        "dolphin": ("DOLPHIN", "Dolphin.app/Contents/MacOS/Dolphin", "Dolphin", "%EMULATOR_DOLPHIN% -b -e %ROM%"),
        // Full screen comes from xemu.toml.
        "xemu": ("XEMU", "xemu.app/Contents/MacOS/xemu", "xemu", "%EMULATOR_XEMU% -dvd_path %ROM%"),
        // -batch: PCSX2 exits when the game shuts down, so Select+Start returns to ES-DE.
        "pcsx2": ("PCSX2", "PCSX2.app/Contents/MacOS/PCSX2", "PCSX2", "%EMULATOR_PCSX2% -batch -nogui -fullscreen %ROM%"),
    ]

    public static func xml(for systems: Set<SystemID>, manifest: Manifest, library: URL) -> String {
        var out = "<?xml version=\"1.0\"?>\n<systemList>\n"
        for system in SystemID.allCases where systems.contains(system) {
            guard let info = info[system] else { continue }
            let label: String, command: String
            if let core = manifest.core(for: system) {
                label = core.libraryName
                command = "%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/\(core.file) %ROM%"
            } else if let app = manifest.app(for: system), let standalone = standalones[app.id] {
                label = standalone.label
                command = standalone.command
            } else {
                continue
            }
            let exts = info.extensions.flatMap { [".\($0)", ".\($0.uppercased())"] }.joined(separator: " ")
            let name = system.rawValue
            out += """
                <system>
                    <name>\(name)</name>
                    <fullname>\(info.fullname)</fullname>
                    <path>\(ESDESettings.xmlEscape(library.appending(path: name).path))</path>
                    <extension>\(exts)</extension>
                    <command label="\(label)">\(command)</command>
                    <platform>\(name)</platform>
                    <theme>\(name)</theme>
                </system>

            """
        }
        return out + "</systemList>\n"
    }

    /// RetroArch, then the standalones in a fixed order: what Console Mode's exit combo quits.
    public static let emulatorApps = ["RetroArch.app"]
        + standalones.values.sorted { $0.rule < $1.rule }.map { String($0.executable.prefix { $0 != "/" }) }

    /// ES-DE's own find rules expect emulators in /Applications; these point at retromac's copies.
    public static func findRules(paths: Paths) -> String {
        let emulators = [("RETROARCH", paths.retroarchExecutable)]
            + standalones.values.sorted { $0.rule < $1.rule }.map { ($0.rule, paths.applications.appending(path: $0.executable)) }
        var out = """
            <?xml version="1.0"?>
            <!-- Managed by retromac — edits will be overwritten -->
            <ruleList>

            """
        for (name, executable) in emulators {
            out += """
                    <emulator name="\(name)">
                        <rule type="staticpath">
                            <entry>\(ESDESettings.xmlEscape(executable.path))</entry>
                        </rule>
                    </emulator>

                """
        }
        return out + """
                <core name="RETROARCH">
                    <rule type="corepath">
                        <entry>\(ESDESettings.xmlEscape(paths.retroarchCores.path))</entry>
                    </rule>
                </core>
            </ruleList>

            """
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
