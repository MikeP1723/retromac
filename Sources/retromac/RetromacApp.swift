// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import SwiftUI

@main
struct RetromacApp: App {
    @State private var app: AppModel

    init() {
        // Lets `swift run retromac` show a normal window and Dock icon outside an .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        _app = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup("retromac") {
            RootView(app: app, updates: app.updates)
                .frame(minWidth: 640, minHeight: 520)
                .task {
                    app.retryPendingApply()
                    await app.updates.check(force: false)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    app.updates.showSheet = true
                    Task { await app.updates.check(force: true) }
                }
                .keyboardShortcut("u")
            }
        }
    }
}

struct RootView: View {
    @Bindable var app: AppModel
    @Bindable var updates: UpdateModel

    var body: some View {
        Group {
            switch app.screen {
            case .migrating: MigrationView(app: app)
            case .wizard: WizardView(app: app, model: app.wizard)
            case .home: HomeView(app: app, updates: updates)
            case .library: LibraryView(app: app, games: app.games)
            }
        }
        .sheet(isPresented: $updates.showSheet) { UpdatesView(model: updates) }
    }
}

struct WizardView: View {
    @Bindable var app: AppModel
    @Bindable var model: WizardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                ForEach(WizardModel.Step.allCases, id: \.self) { step in
                    Text(step.title)
                        .fontWeight(step == model.step ? .semibold : .regular)
                        .foregroundStyle(step == model.step ? .primary : .secondary)
                }
                Spacer()
                if app.isSetUp {
                    Button { app.screen = .home } label: { Label("Home", systemImage: "house") }
                        .disabled(model.busy)
                }
            }
            .padding()
            Divider()

            if let error = model.loadError {
                Text(error).foregroundStyle(.red).padding()
            }
            if let notice = model.notice {
                Label(notice, systemImage: "info.circle").padding(.horizontal).padding(.top, 8)
            }

            Group {
                switch model.step {
                case .display: DisplayStep(model: model)
                case .systems: SystemsStep(model: model)
                case .controllers: ControllersStep(model: model)
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
                        .disabled(model.busy)
                } else {
                    Button("Continue") { app.screen = .home }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.busy || !(model.applied || app.isSetUp))
                }
            }
            .padding()
        }
    }
}
