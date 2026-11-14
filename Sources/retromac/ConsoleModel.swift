// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import Observation
import RetromacCore

/// The macOS settings Console Mode depends on. retromac only reads them and links to System Settings.
@Observable @MainActor
final class ConsoleModel {
    var status = SystemStatus(fileVaultOn: nil, autoLoginUser: nil, passwordAfterWake: .unknown)
    var checking = false

    func refresh() {
        checking = true
        Task {
            status = await Task.detached { SystemStatusProbe.read(runner: ProcessRunner()) }.value
            checking = false
        }
    }

    func open(_ pane: SettingsPane) {
        NSWorkspace.shared.open(pane.url)
    }
}
