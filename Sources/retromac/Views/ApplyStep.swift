// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

struct ApplyStep: View {
    @Bindable var model: WizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Button("Install & Apply") { Task { await model.installAndApply() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy || model.loadError != nil)
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Menu("Restore previous config") {
                    ForEach(model.backups, id: \.self) { snapshot in
                        Button(snapshot.lastPathComponent) { model.restore(snapshot) }
                    }
                }
                .disabled(model.backups.isEmpty || model.busy)
                .fixedSize()
            }
            ScrollView {
                Text(model.log.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(.quaternary.opacity(0.3))
        }
    }
}
