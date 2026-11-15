// SPDX-License-Identifier: GPL-3.0-or-later
import RetromacCore
import SwiftUI

/// Library › Advanced: use a server share as the game library, read-only.
struct NetworkLibrarySection: View {
    @Bindable var app: AppModel
    @State private var expanded = false
    @State private var address = ""
    @State private var checking = false
    @State private var check: AppModel.NetworkCheck?
    @State private var error: String?

    static let readOnlyNote = "retromac only reads from this folder. It never adds, moves, converts or deletes anything there. Multi-disc PS1 and Saturn games need their .m3u playlist, and .bin discs their .cue, already on the share."

    var body: some View {
        DisclosureGroup("Advanced: network library", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let network = app.wizard.profile.networkLibrary {
                    Text("Games come from \(network.url.absoluteString.removingPercentEncoding ?? network.url.absoluteString).")
                    HStack {
                        Button("Turn off network library") { error = app.switchLibrary { $0.useLocalLibrary() } }
                        if case .notConnected = app.networkStatus {
                            Button("Reconnect") { Task { await app.connectNetworkLibrary() } }
                        }
                    }
                } else {
                    HStack {
                        TextField("smb://server/share/folder", text: $address)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(connect)
                        Button("Connect", action: connect).disabled(checking || address.isEmpty)
                        if checking { ProgressView().controlSize(.small) }
                    }
                    if case .found(let url, let folder, let consoles, let other) = check {
                        Text(consoles.isEmpty ? "No console folders found. Name them like snes, psx, gc."
                             : "Found: " + consoles.map(\.displayName).joined(separator: ", "))
                        if !other.isEmpty {
                            Text("Not used: " + other.joined(separator: ", ")).foregroundStyle(.secondary)
                        }
                        Text("Expected folder names: " + SystemID.allCases.map(\.rawValue).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Use this library") { error = app.switchLibrary { $0.useNetworkLibrary(url, at: folder) } }
                            .buttonStyle(.borderedProminent)
                            .disabled(consoles.isEmpty)
                    } else if case .failed(let message) = check {
                        Text(message).foregroundStyle(.red)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Text(Self.readOnlyNote).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private func connect() {
        guard !checking else { return }
        checking = true
        error = nil
        Task {
            check = await app.checkNetworkLibrary(address)
            checking = false
        }
    }
}
