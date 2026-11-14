// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Shown once while an older install is moved into retromac's own folder.
struct MigrationView: View {
    @Bindable var app: AppModel

    var body: some View {
        VStack(spacing: 16) {
            if let error = app.migrationError {
                Image(systemName: "exclamationmark.triangle").font(.largeTitle).foregroundStyle(.orange)
                Text(error).multilineTextAlignment(.center)
                Button("Try Again") { Task { await app.migrate() } }.buttonStyle(.borderedProminent)
            } else {
                ProgressView()
                Text("Updating retromac's files…").foregroundStyle(.secondary)
                Text("Your games and settings are moving into retromac's own folder. This only happens once.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { if app.migrationError == nil { await app.migrate() } }
    }
}
