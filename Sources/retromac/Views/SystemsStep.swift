// SPDX-License-Identifier: GPL-3.0-or-later
import RetromacCore
import SwiftUI

struct SystemsStep: View {
    @Bindable var model: WizardModel

    var body: some View {
        Form {
            Section("Set up these systems") {
                ForEach((try? Manifest.bundled())?.installableSystems ?? [], id: \.self) { system in
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle(system.displayName, isOn: Binding(
                            get: { model.profile.systems.contains(system) },
                            set: { on in
                                if on { model.profile.systems.insert(system) } else { model.profile.systems.remove(system) }
                            }))
                        if let caption = biosCaption(system) {
                            Text(caption).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .task { bios = BiosStatus.present(in: model.paths.retroarchSystem) }
    }

    @State private var bios: [SystemID: [BiosFile]] = [:]

    private func biosCaption(_ system: SystemID) -> String? {
        let regions = (bios[system] ?? []).map(\.region).joined(separator: ", ")
        switch system {
        case .psx:
            return regions.isEmpty
                ? "Works without a BIOS. Adding your PlayStation's BIOS file improves compatibility — add it in Games like any game file."
                : "BIOS found for: \(regions)"
        case .saturn:
            return regions.isEmpty ? "Needs your Saturn's BIOS file to play. Add it in Games like any game file." : "BIOS found for: \(regions)"
        case .xbox:
            let missing = BiosStatus.missing(.xbox, in: model.paths.retroarchSystem)
            switch missing.count {
            case 0: return "BIOS found."
            case 1: return "Still needs \(missing[0])."
            default: return "Needs your Xbox's MCPX boot ROM (mcpx_1.0.bin) and BIOS (Complex_4627.bin). Add them in Games like any game file."
            }
        default:
            return nil
        }
    }
}
