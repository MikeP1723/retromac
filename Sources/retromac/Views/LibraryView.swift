// SPDX-License-Identifier: GPL-3.0-or-later
import AppKit
import RetromacCore
import SwiftUI
import UniformTypeIdentifiers

/// The game library: what's in it, and importing more.
struct LibraryView: View {
    @Bindable var app: AppModel
    @Bindable var games: GamesModel
    @State private var targeted = false
    @State private var showDetails = false
    @State private var showDatabases = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button { app.screen = .home } label: { Label("Home", systemImage: "chevron.left") }
                    .disabled(games.busy)
                Spacer()
                Text("Library").font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Show in Finder") { app.showGamesInFinder() }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    if games.librarySystems.isEmpty {
                        Text("No games yet. Import a folder of games to get started.").foregroundStyle(.secondary)
                    }
                    ForEach(SystemID.allCases.filter { games.librarySystems[$0] != nil }, id: \.self) { system in
                        HStack {
                            Text(system.displayName)
                            Spacer()
                            Text("\(games.librarySystems[system] ?? 0)").foregroundStyle(.secondary)
                        }
                    }
                    if let stats = app.libraryStats { Text(stats).font(.caption).foregroundStyle(.secondary) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 12) {
                Button { chooseFolder() } label: {
                    Label("Import Folder…", systemImage: "folder.badge.plus").frame(minWidth: 160)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .disabled(games.busy)
                Button("Choose Files…") { chooseFiles() }.disabled(games.busy)
                Spacer()
            }

            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
                .foregroundStyle(targeted ? Color.accentColor : .secondary)
                .background(targeted ? Color.accentColor.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 10))
                .overlay(Text("…or drop games, folders or .zip files here").foregroundStyle(.secondary))
                .frame(height: 70)
                .dropDestination(for: URL.self) { urls, _ in
                    guard !games.committing, !games.updatingDats else { return false }
                    Task { await games.analyze(urls) }
                    return true
                } isTargeted: { targeted = $0 }

            if let progress = games.scanProgress {
                HStack {
                    if progress.total > 0 {
                        ProgressView(value: Double(progress.scanned), total: Double(max(progress.total, 1)))
                        Text("Scanning \(progress.scanned.formatted()) of \(progress.total.formatted()) files…")
                            .foregroundStyle(.secondary).monospacedDigit()
                    } else {
                        ProgressView().controlSize(.small)
                        Text("Looking for games…").foregroundStyle(.secondary)
                    }
                    Button("Cancel") { games.cancel() }
                }
            } else if let summary = games.summary {
                SummaryCard(summary: summary, games: games, enabled: app.wizard.profile.systems, showDetails: $showDetails)
            }

            if let message = games.message {
                Text(message).foregroundStyle(message.hasPrefix("Not enough") ? .red : .secondary)
            }

            Spacer(minLength: 0)

            DisclosureGroup("Game Databases", isExpanded: $showDatabases) {
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
                        Button("Update Game Databases") { Task { await games.updateDats() } }.disabled(games.busy)
                        Button("Import DAT Files…") { chooseDats() }.disabled(games.busy)
                        if let progress = games.datProgress { Text(progress).foregroundStyle(.secondary) }
                        if let error = games.datError { Text(error).foregroundStyle(.red) }
                    }
                    Text("Game databases name your games. They download from libretro-database on GitHub.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .task { await app.refreshLibraryStats() }
        .onChange(of: games.committing) { _, committing in
            if !committing { Task { await app.refreshLibraryStats() } }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Import"
        panel.message = "Choose a folder of games. retromac copies them and leaves the originals where they are."
        if panel.runModal() == .OK, let url = panel.url { Task { await games.analyze([url]) } }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        if panel.runModal() == .OK { Task { await games.analyze(panel.urls) } }
    }

    private func chooseDats() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [UTType(filenameExtension: "dat") ?? .data, .xml, .zip]
        if panel.runModal() == .OK { games.importDats(panel.urls) }
    }
}

private struct SummaryCard: View {
    let summary: ImportSummary
    @Bindable var games: GamesModel
    let enabled: Set<SystemID>
    @Binding var showDetails: Bool

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(headline).font(.headline)
                Text(detail).foregroundStyle(.secondary)
                HStack {
                    DisclosureGroup("Show details", isExpanded: $showDetails) { EmptyView() }.fixedSize()
                    Spacer()
                    Button("Clear") { games.clear() }.disabled(games.busy)
                    Button("Import All") { Task { await games.commit() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(games.toAdd == 0 || games.busy)
                }
                if showDetails {
                    List(games.candidates) { item in
                        CandidateRow(item: item, enabledSystems: enabled, installable: games.installable)
                    }
                    .frame(minHeight: 160)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var headline: String {
        let found = summary.identified + summary.unverified
        return found == 0 ? "No new games found" : "Found \(found.formatted()) game\(found == 1 ? "" : "s") to import"
    }

    private var detail: String {
        var parts: [String] = []
        if summary.identified > 0 { parts.append("\(summary.identified.formatted()) found in the databases") }
        if summary.unverified > 0 { parts.append("\(summary.unverified.formatted()) not in a database") }
        if summary.duplicates > 0 { parts.append("\(summary.duplicates.formatted()) already in your library") }
        if summary.unidentified > 0 { parts.append("\(summary.unidentified.formatted()) not recognized") }
        if summary.skipped > 0 { parts.append("\(summary.skipped.formatted()) other files skipped") }
        if summary.failed > 0 { parts.append("\(summary.failed.formatted()) couldn't be read") }
        if summary.bytesToCopy > 0 { parts.append("\(ByteCountFormatter.string(fromByteCount: summary.bytesToCopy, countStyle: .file)) to copy") }
        return parts.joined(separator: " · ")
    }
}

struct CandidateRow: View {
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
