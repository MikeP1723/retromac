// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

@main
struct RetromacApp: App {
    @State private var model: WizardModel
    @State private var updates: UpdateModel

    init() {
        // Lets `swift run retromac` show a normal window and Dock icon outside an .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        let wizard = WizardModel()
        _model = State(initialValue: wizard)
        _updates = State(initialValue: UpdateModel(paths: wizard.paths, profile: { wizard.profile }))
    }

    var body: some Scene {
        WindowGroup("retromac") {
            WizardView(model: model, updates: updates)
                .frame(minWidth: 620, minHeight: 460)
                .task { await updates.check(force: false) }
                .sheet(isPresented: $updates.showSheet) { UpdatesView(model: updates) }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updates.showSheet = true
                    Task { await updates.check(force: true) }
                }
                .keyboardShortcut("u")
            }
        }
    }
}

struct WizardView: View {
    @Bindable var model: WizardModel
    @Bindable var updates: UpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if updates.hasUpdates {
                Button {
                    updates.showSheet = true
                } label: {
                    Label("Updates available", systemImage: "arrow.down.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.tint.opacity(0.12))
            }
            HStack(spacing: 16) {
                ForEach(WizardModel.Step.allCases, id: \.self) { step in
                    Text(step.title)
                        .fontWeight(step == model.step ? .semibold : .regular)
                        .foregroundStyle(step == model.step ? .primary : .secondary)
                }
            }
            .padding()
            Divider()

            if let error = model.loadError {
                Text(error).foregroundStyle(.red).padding()
            }

            Group {
                switch model.step {
                case .display: DisplayStep(model: model)
                case .systems: SystemsStep(model: model)
                case .controllers: ControllersStep(model: model)
                case .library: LibraryStep(model: model)
                case .apply: ApplyStep(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()

            Divider()
            HStack {
                Button("Back") { model.step = WizardModel.Step(rawValue: model.step.rawValue - 1) ?? .display }
                    .disabled(model.step == .display || model.busy)
                Spacer()
                if model.step != .apply {
                    Button("Next") { model.step = WizardModel.Step(rawValue: model.step.rawValue + 1) ?? .apply }
                        .keyboardShortcut(.defaultAction)
                } else {
                    if model.applied {
                        Button("Open ES-DE") { model.openESDE() }
                    }
                    Button("Done") { NSApplication.shared.terminate(nil) }
                        .disabled(model.busy)
                }
            }
            .padding()
        }
    }
}
