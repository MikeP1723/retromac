// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// What retromac opens to once it's set up.
struct HomeView: View {
    @Bindable var app: AppModel
    @Bindable var updates: UpdateModel

    var body: some View {
        VStack(spacing: 0) {
            if updates.hasUpdates {
                Button { updates.showSheet = true } label: {
                    Label("Updates available", systemImage: "arrow.down.circle").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.tint.opacity(0.12))
            }
            Spacer()
            VStack(spacing: 18) {
                Text("retromac").font(.largeTitle).fontWeight(.bold)
                Button { app.play() } label: {
                    Label("Play", systemImage: "play.fill").font(.title2).frame(width: 240, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!app.canPlay)
                .help(app.canPlay ? "Open your games on the big screen" : "Finish setup in Settings first")

                HStack(spacing: 12) {
                    Button { app.screen = .library } label: {
                        Label("Library", systemImage: "square.grid.2x2").frame(width: 110)
                    }
                    Button { app.wizard.step = .display; app.screen = .wizard } label: {
                        Label("Settings", systemImage: "gearshape").frame(width: 110)
                    }
                    Button {
                        updates.showSheet = true
                        Task { await updates.check(force: true) }
                    } label: {
                        Label("Updates", systemImage: "arrow.triangle.2.circlepath").frame(width: 110)
                    }
                }
                .controlSize(.large)
            }
            Spacer()
            HStack {
                Text(app.libraryStats ?? " ").foregroundStyle(.secondary)
                Spacer()
                Button("Show Games in Finder") { app.showGamesInFinder() }.buttonStyle(.link)
            }
            .font(.callout)
            .padding()
        }
        .task { await app.refreshLibraryStats() }
    }
}
