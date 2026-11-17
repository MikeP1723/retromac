// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import RetromacCore
import SwiftUI

/// The guided Switch setup: the user installs Ryubing and adds their keys and firmware in it; retromac
/// only checks for the app and, after Done, sets Ryubing's few settings and adds Switch to ES-DE.
struct SwitchSetupCard: View {
    @Bindable var model: WizardModel
    @State private var status: Ryubing.Status = .notInstalled
    @State private var message: String?
    @State private var applied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            step(1, "Install Ryubing", done: status != .notInstalled) {
                if status == .notInstalled {
                    Link("Get Ryubing", destination: URL(string: "https://ryubing.org")!)
                    Text(Ryubing.installStep).font(.caption).foregroundStyle(.secondary)
                }
            }
            step(2, "Set up Ryubing", done: confirmed) {
                Text(Ryubing.setupStep).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Open Ryubing") { NSWorkspace.shared.open(model.paths.ryubingApp) }
                    Button("Done") {
                        message = model.confirmSwitchSetup()
                        refresh()
                    }
                }
                .disabled(status == .notInstalled)
                if let message {
                    Text(message).font(.caption).foregroundStyle(.orange)
                }
            }
            if confirmed, message == nil, let ready = readyText {
                step(3, "Ready", done: applied) {
                    Text(ready).font(.caption).foregroundStyle(status == .ready ? Color.secondary : Color.orange)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private var confirmed: Bool { model.profile.switchSetup?.confirmed == true }

    private var readyText: String? {
        switch status {
        // Only once an apply wrote Ryubing's settings: a Done refused while Ryubing was open wrote nothing.
        case .ready: applied ? Ryubing.ready : nil
        case .noConfig: Ryubing.noConfig
        case .unknownVersion: Ryubing.unknownVersion
        case .notInstalled: nil
        }
    }

    private func refresh() {
        status = Ryubing.status(paths: model.paths)
        applied = RyubingRenderer.isApplied(model.profile, paths: model.paths)
    }

    private func step(_ n: Int, _ title: String, done: Bool, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("\(n). \(title)", systemImage: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? Color.green : Color.primary)
            content()
        }
    }
}
