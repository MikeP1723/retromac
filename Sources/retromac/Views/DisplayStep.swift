// SPDX-License-Identifier: GPL-3.0-or-later
import RetromacCore
import SwiftUI

struct DisplayStep: View {
    @Bindable var model: WizardModel

    var body: some View {
        let d = model.profile.display
        Form {
            Section("Detected") {
                LabeledContent("Resolution", value: "\(d.widthPx) × \(d.heightPx)")
                LabeledContent("Refresh rate", value: "\(Int(d.refreshHz)) Hz")
                LabeledContent("HDR", value: d.hdr ? "Yes" : "No")
                LabeledContent("Variable refresh", value: d.vrr ? "Yes" : "No")
            }
            Section("Your setup") {
                TextField("Screen size (inches, diagonal)", value: $model.profile.display.diagonalInches, format: .number)
                TextField("Seating distance (inches)", value: $model.profile.display.distanceInches, format: .number)
                Picker("Look", selection: $model.profile.look) {
                    Text("Crisp pixels").tag(Look.crisp)
                    Text("CRT look").tag(Look.crt)
                    Text("Smooth").tag(Look.smooth)
                }
                .pickerStyle(.segmented)
                LabeledContent("Shader", value: model.shaderDescription)
                LabeledContent("Pixels per degree", value: model.pixelsPerDegree.formatted(.number.precision(.fractionLength(0))))
            }
        }
        .formStyle(.grouped)
    }
}
