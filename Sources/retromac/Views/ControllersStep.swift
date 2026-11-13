// SPDX-License-Identifier: GPL-3.0-or-later
import RetromacCore
import SwiftUI

struct ControllersStep: View {
    @Bindable var model: WizardModel

    var body: some View {
        Form {
            Section("Connected controllers") {
                if model.profile.controllers.isEmpty {
                    Text("No controllers found — pair one in System Settings › Bluetooth, then it appears here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(Array(model.profile.controllers.enumerated()), id: \.offset) { index, pad in
                    LabeledContent("Player \(index + 1)", value: pad.deviceName)
                }
            }
            Section {
                Picker("Face buttons", selection: $model.profile.facePolicy) {
                    Text("Match button position").tag(FacePolicy.position)
                    Text("Match button label (Xbox pads)").tag(FacePolicy.label)
                }
                .pickerStyle(.radioGroup)
            } footer: {
                Text("Label matching applies only when every connected pad is an Xbox controller.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
