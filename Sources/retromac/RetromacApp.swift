// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

@main
struct RetromacApp: App {
    @State private var model: WizardModel
    @State private var updates: UpdateModel
    @State private var games: GamesModel

    init() {
        // Lets `swift run retromac` show a normal window and Dock icon outside an .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        let wizard = WizardModel()
        _model = State(initialValue: wizard)
        _updates = State(initialValue: UpdateModel(paths: wizard.paths, profile: { wizard.profile }))
        _games = State(initialValue: GamesModel(paths: wizard.paths, libraryRoot: { wizard.profile.libraryRoot }))
    }

    var body: some Scene {
        WindowGroup("retromac") {
            WizardView(model: model, updates: updates, games: games)
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
    @Bindable var games: GamesModel

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
                Spacer()
                Button {
                    updates.showSheet = true
                    Task { await updates.check(force: true) }
                } label: {
                    Label("Check for Updates", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(model.busy || updates.busy)
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
                case .games: GamesStep(games: games, enabledSystems: model.profile.systems)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding()

            Divider()
            HStack {
                Button("Back") { model.step = WizardModel.Step(rawValue: model.step.rawValue - 1) ?? .display }
                    .disabled(model.step == .display || model.busy || games.busy)
                Spacer()
                if model.step != .games {
                    Button("Next") { model.step = WizardModel.Step(rawValue: model.step.rawValue + 1) ?? .games }
                        .keyboardShortcut(model.step == .apply ? nil : .defaultAction)
                        .disabled(model.busy)
                } else {
                    if FileManager.default.fileExists(atPath: model.paths.applications.appending(path: "ES-DE.app").path) {
                        Button("Open ES-DE") { model.openESDE() }
                    }
                    Button("Done") { NSApplication.shared.terminate(nil) }
                        .disabled(games.busy)
                }
            }
            .padding()
        }
    }
}
