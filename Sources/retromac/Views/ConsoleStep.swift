// SPDX-License-Identifier: GPL-3.0-or-later
import RetromacCore
import SwiftUI

struct ConsoleStep: View {
    @Bindable var model: WizardModel
    @Bindable var console: ConsoleModel
    /// Set when the user turns Console Mode off here, to suggest undoing the settings it needed.
    @State private var turnedOff = false

    private var enabled: Binding<Bool> {
        Binding {
            model.profile.console?.enabled ?? false
        } set: { on in
            var settings = model.profile.console ?? .default
            if settings.enabled && !on { turnedOff = true }
            if on { turnedOff = false }
            settings.enabled = on
            model.profile.console = settings
        }
    }

    private var sleep: Binding<SleepBehavior> {
        Binding {
            model.profile.console?.sleep ?? .standby
        } set: { behavior in
            var settings = model.profile.console ?? .default
            settings.sleep = behavior
            model.profile.console = settings
        }
    }

    var body: some View {
        Form {
            Section {
                Text("Turn this Mac into a game console for your TV. When it's on, starting or waking the Mac takes you straight to your games. Only use this on a Mac that's dedicated to gaming.")
                Toggle("Start in my games when this Mac turns on or wakes", isOn: enabled)
            }
            if enabled.wrappedValue {
                onRows
            } else if turnedOff && !relaxedSettings.isEmpty {
                Section("You may want to turn these back on:") {
                    ForEach(relaxedSettings, id: \.title) { row in
                        LabeledContent(row.title) {
                            Button(row.button) { console.open(row.pane) }
                        }
                    }
                }
            }
            Section {
                Button("Check again") { console.refresh() }
                    .disabled(console.checking)
            }
        }
        .formStyle(.grouped)
        .task { console.refresh() }
    }

    @ViewBuilder private var onRows: some View {
        Section {
            LabeledContent("Log in automatically", value: autoLoginStatus)
            Text("Without this, you'll see the login screen when the Mac starts. Turning off FileVault lets anyone who has this Mac read what's on its disk. retromac doesn't change these settings — you choose in System Settings.")
                .foregroundStyle(.secondary)
            if console.status.fileVaultOn == true {
                Button("Open FileVault Settings") { console.open(.fileVault) }
            } else {
                Button("Open Users & Groups") { console.open(.usersAndGroups) }
            }
        }
        Section {
            LabeledContent("Skip the password when waking", value: passwordStatus)
            Text("Without this, waking the Mac shows a password prompt. With it, anyone at the TV can get into this Mac account.")
                .foregroundStyle(.secondary)
            Button("Open Lock Screen Settings") { console.open(.lockScreen) }
        }
        Section {
            Picker("When you put the console to sleep", selection: sleep) {
                Text("Console standby").tag(SleepBehavior.standby)
                Text("Sleep").tag(SleepBehavior.trueSleep)
            }
            .pickerStyle(.segmented)
            Text(sleep.wrappedValue == .standby
                 ? "The screen turns off but the Mac stays awake. Press any button on your controller to come back. Uses a little power while resting."
                 : "The Mac fully sleeps and uses almost no power. Wake it with the power button or a keyboard — macOS can't wake from a game controller.")
                .foregroundStyle(.secondary)
        }
        Section("Controller shortcuts") {
            Text("Hold L + R + Start for 2 seconds to put the console to sleep. Hold L + R + Select for 2 seconds to go back to the desktop.")
        }
    }

    private var autoLoginStatus: String {
        if console.status.fileVaultOn == true {
            return "Off — FileVault disk encryption is on. macOS doesn't allow automatic login while FileVault is on."
        }
        if let user = console.status.autoLoginUser { return "On for \(user)" }
        return "Off"
    }

    private var passwordStatus: String {
        switch console.status.passwordAfterWake {
        case .immediately, .after: "Password required after sleep"
        case .off: "No password after sleep"
        case .unknown: "Couldn't check"
        }
    }

    private struct Relaxed {
        let title: String
        let button: String
        let pane: SettingsPane
    }

    /// Settings that are looser than a normal Mac's, offered back after Console Mode is turned off.
    private var relaxedSettings: [Relaxed] {
        var rows: [Relaxed] = []
        if console.status.autoLoginUser != nil {
            rows.append(Relaxed(title: "Automatic login is on", button: "Open Users & Groups", pane: .usersAndGroups))
        }
        if console.status.passwordAfterWake == .off {
            rows.append(Relaxed(title: "No password after sleep", button: "Open Lock Screen Settings", pane: .lockScreen))
        }
        if console.status.fileVaultOn == false {
            rows.append(Relaxed(title: "FileVault is off", button: "Open FileVault Settings", pane: .fileVault))
        }
        return rows
    }
}
