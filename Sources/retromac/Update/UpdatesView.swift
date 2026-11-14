// SPDX-License-Identifier: GPL-3.0-or-later
import RetromacCore
import SwiftUI

struct UpdatesView: View {
    @Bindable var model: UpdateModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Updates").font(.title2).fontWeight(.semibold)

            if let error = model.error {
                Text(error).foregroundStyle(.red).textSelection(.enabled)
            }

            Form {
                if let update = model.plan?.retromacUpdate {
                    Section("retromac") {
                        HStack {
                            Text("retromac \(model.appVersion) → \(update.version)")
                            Spacer()
                            Button("Update & Relaunch") { Task { await model.updateSelf() } }
                                .disabled(model.busy)
                        }
                    }
                }

                if let required = model.plan?.blockedByMinAppVersion {
                    Text("This update needs retromac \(required) or newer. Update retromac first.")
                        .foregroundStyle(.orange)
                } else if let updates = model.plan?.updates, !updates.isEmpty {
                    Section("Emulators and cores") {
                        ForEach(updates) { update in
                            ComponentRow(update: update, model: model)
                        }
                    }
                } else if model.plan != nil && model.plan?.retromacUpdate == nil {
                    Text("Everything is up to date.").foregroundStyle(.secondary)
                }

                if !model.revertible.isEmpty {
                    Section("Installed") {
                        ForEach(model.revertible, id: \.self) { id in
                            HStack {
                                Text(id)
                                Spacer()
                                Button("Revert") { model.revert(id) }.disabled(model.busy)
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            if !model.log.isEmpty {
                ScrollView {
                    Text(model.log.joined(separator: "\n"))
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }

            HStack {
                Button("Check Again") { Task { await model.check(force: true) } }.disabled(model.busy)
                if model.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Close") { dismiss() }
                Button("Update Selected") { Task { await model.applySelected() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy || model.selected.isEmpty || model.plan?.blockedByMinAppVersion != nil)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct ComponentRow: View {
    let update: ComponentUpdate
    @Bindable var model: UpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(
                get: { model.selected.contains(update.id) },
                set: { on in
                    if on { model.selected.insert(update.id) } else { model.selected.remove(update.id) }
                })) {
                Text("\(update.id)  \(update.installed) → \(update.available)")
            }
            .disabled(!update.managed && !model.adopt.contains(update.id))

            if !update.managed {
                Toggle("Adopt", isOn: Binding(
                    get: { model.adopt.contains(update.id) },
                    set: { on in
                        if on {
                            model.adopt.insert(update.id)
                        } else {
                            model.adopt.remove(update.id)
                            model.selected.remove(update.id)
                        }
                    }))
                Text("Replaces your existing copy; the old one is kept and can be reverted.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let previous = update.previousLicense {
                Text("License changed from \(previous) to \(update.license)").font(.caption).foregroundStyle(.red)
            }
            if update.requiresRosetta {
                Text("Needs Rosetta").font(.caption).foregroundStyle(.orange)
            }
        }
    }
}
