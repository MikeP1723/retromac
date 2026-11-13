// SPDX-License-Identifier: GPL-3.0-or-later
import RetromacCore
import SwiftUI

struct SystemsStep: View {
    @Bindable var model: WizardModel

    static let names: [SystemID: String] = [
        .nes: "Nintendo Entertainment System",
        .snes: "Super Nintendo",
        .genesis: "Sega Genesis",
        .n64: "Nintendo 64",
    ]

    var body: some View {
        Form {
            Section("Set up these systems") {
                ForEach(SystemID.allCases, id: \.self) { system in
                    Toggle(Self.names[system] ?? system.rawValue, isOn: Binding(
                        get: { model.profile.systems.contains(system) },
                        set: { on in
                            if on { model.profile.systems.insert(system) } else { model.profile.systems.remove(system) }
                        }))
                }
            }
        }
        .formStyle(.grouped)
    }
}
