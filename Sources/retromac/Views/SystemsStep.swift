// SPDX-License-Identifier: GPL-3.0-or-later
import RetromacCore
import SwiftUI

struct SystemsStep: View {
    @Bindable var model: WizardModel

    var body: some View {
        Form {
            Section("Set up these systems") {
                ForEach((try? Manifest.bundled())?.installableSystems ?? [], id: \.self) { system in
                    Toggle(system.displayName, isOn: Binding(
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
