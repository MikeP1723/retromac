// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import RetromacCore
import SwiftUI
import UniformTypeIdentifiers

struct GamesStep: View {
    @Bindable var games: GamesModel
    let enabledSystems: Set<SystemID>
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("Game databases") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(SystemID.allCases.filter { DatUpdater.sources[$0] != nil }, id: \.self) { system in
                        HStack {
                            Text(system.displayName)
                            Spacer()
                            if let dat = games.dats[system] {
                                let date = games.updated(system).map { " · updated \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
                                Text("\((dat.entries.count + dat.serials.count).formatted()) entries\(date)").foregroundStyle(.secondary)
                            } else {
                                Text("Not downloaded").foregroundStyle(.secondary)
                            }
                        }
                    }
                    HStack {
                        Button("Update Game Databases") { Task { await games.updateDats() } }
                            .disabled(games.busy)
                        Button("Import DAT Files…") { chooseDats() }.disabled(games.busy)
                        if let progress = games.datProgress { Text(progress).foregroundStyle(.secondary) }
                        if let error = games.datError { Text(error).foregroundStyle(.red) }
                    }
                    Text("Downloaded from libretro-database on GitHub. Games not in a database are still added, with cleaned-up names.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(alignment: .top) {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .foregroundStyle(targeted ? Color.accentColor : .secondary)
                    .background(targeted ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(Text("Drop games, folders or .zip files here").foregroundStyle(.secondary))
                    .frame(height: 140)
                    .dropDestination(for: URL.self) { urls, _ in
                        guard !games.committing else { return false }
                        Task { await games.analyze(urls) }
                        return true
                    } isTargeted: { targeted = $0 }
                Button("Choose Files…") { chooseGames() }
            }

            if !games.candidates.isEmpty {
                List(games.candidates) { item in
                    CandidateRow(item: item, enabledSystems: enabledSystems, installable: games.installable)
                }
                .frame(minHeight: 120)
            }

            HStack {
                if games.busy {
                    ProgressView().controlSize(.small)
                    if games.datProgress == nil { Button("Cancel") { games.cancel() } }
                }
                if let message = games.message { Text(message).foregroundStyle(.secondary) }
                Spacer()
                Button("Clear") { games.clear() }.disabled(games.candidates.isEmpty || games.busy)
                Button("Add \(games.toAdd) Game\(games.toAdd == 1 ? "" : "s")") { Task { await games.commit() } }
                    .disabled(games.toAdd == 0 || games.busy)
            }
        }
    }

    private func chooseDats() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "dat") ?? .data, .xml, .zip]
        if panel.runModal() == .OK { games.importDats(panel.urls) }
    }

    private func chooseGames() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { Task { await games.analyze(panel.urls) } }
    }
}

private struct CandidateRow: View {
    let item: ImportCandidate
    let enabledSystems: Set<SystemID>
    let installable: Set<SystemID>

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: icon.name).foregroundStyle(icon.color)
                Text(item.source).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if let system = item.status.system, !installable.contains(system) {
                Text("\(name(system)) emulator arrives in a later update — this game is filed and waiting.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let system = item.status.system, !enabledSystems.contains(system) {
                Text("\(name(system)) isn't set up — enable it on the Systems step.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func name(_ system: SystemID) -> String { system.displayName }

    private var icon: (name: String, color: Color) {
        switch item.status {
        case .identified: ("checkmark.circle.fill", .green)
        case .unverified: ("circle.fill", .yellow)
        case .duplicate, .notAGame: ("minus.circle", .secondary)
        case .unidentified: ("questionmark.circle.fill", .orange)
        case .failed: ("xmark.octagon.fill", .red)
        }
    }

    private var detail: String {
        let file = item.destination?.deletingPathExtension().lastPathComponent ?? ""
        switch item.status {
        case .identified(let system, let title): return "→ \(name(system)) · \(title)"
        case .unverified(let system): return "→ \(name(system)) · \(file) (not in database)"
        case .duplicate: return "already in library"
        case .unidentified(let reason): return "→ _Unidentified (\(reason))"
        case .notAGame: return "not a game file"
        case .failed(let reason): return reason
        }
    }
}
