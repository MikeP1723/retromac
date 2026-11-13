// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

struct LibraryStep: View {
    @Bindable var model: WizardModel

    var body: some View {
        Form {
            Section("Game library") {
                LabeledContent("Location", value: model.profile.libraryRoot.path)
                Button("Choose…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.canCreateDirectories = true
                    if panel.runModal() == .OK, let url = panel.url {
                        model.profile.libraryRoot = url
                    }
                }
                Text("Each system gets its own folder here. retromac doesn't provide games.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
