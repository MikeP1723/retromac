// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

struct LegacyRig {
    let home: URL
    let paths: Paths
    let legacy: LegacyPaths

    init() throws {
        home = try makeTempDir()
        legacy = LegacyPaths(home: home, applications: home.appending(path: "Applications"))
        paths = Paths(home: home)
    }

    func migrator(running: String? = nil) -> Migrator {
        Migrator(paths: paths, legacy: legacy, isRunning: { $0 == running })
    }

    /// A Phase 1–3 install: ~/retromac, ~/ES-DE, and retromac-managed apps in Applications.
    func buildLegacy(esdeManaged: Bool = true, retroarchManaged: Bool = true) throws {
        let old = legacy.root
        let profile = Profile(display: tv65_4k, look: .crisp, systems: [.nes], controllers: [], facePolicy: .position,
                              libraryRoot: old.appending(path: "Library"))
        try profile.save(to: old.appending(path: "profile.json"))
        var state = InstallState.empty
        state.apps["retroarch"] = .init(version: "1.22.2", sha256: nil, managed: retroarchManaged)
        state.apps["esde"] = .init(version: "3.5.0", sha256: nil, managed: esdeManaged)
        try state.save(to: old.appending(path: "state.json"))
        try write("rom", to: old.appending(path: "Library/nes/a.nes"))
        try write("old", to: old.appending(path: "previous/x.dylib"))
        let snap = old.appending(path: "backups/20261113-175217")
        try write("<settings/>", to: snap.appending(path: "ES-DE/settings/es_settings.xml"))
        try write("ES-DE/custom_systems/es_systems.xml\nLibrary/Application Support/RetroArch/config/retroarch.cfg\n",
                  to: snap.appending(path: ".retromac-created"))
        try write("<gamelist/>", to: legacy.esde.appending(path: "gamelists/nes/gamelist.xml"))
        try writePlist(version: "1.22.2", to: legacy.applications.appending(path: "RetroArch.app"))
        try writePlist(version: "3.5.0", to: legacy.applications.appending(path: "ES-DE.app"))
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}

@Test func migratesFullLegacyInstall() throws {
    let rig = try LegacyRig()
    try rig.buildLegacy()
    #expect(rig.migrator().isNeeded)
    _ = try rig.migrator().run()
    let root = rig.paths.root
    #expect(try read(root.appending(path: "Library/nes/a.nes")) == "rom")
    #expect(try read(root.appending(path: "previous/x.dylib")) == "old")
    #expect(rig.exists(rig.paths.applications.appending(path: "RetroArch.app/Contents/Info.plist")))
    #expect(rig.exists(rig.paths.applications.appending(path: "ES-DE.app/Contents/Info.plist")))
    #expect(try read(rig.paths.esdeRoot.appending(path: "gamelists/nes/gamelist.xml")) == "<gamelist/>")
    #expect(!rig.exists(rig.legacy.root) && !rig.exists(rig.legacy.esde))
    #expect(!rig.exists(rig.legacy.applications.appending(path: "RetroArch.app")))
    #expect(try Profile.load(from: rig.paths.profile).libraryRoot == rig.paths.defaultLibraryRoot)
    #expect(try InstallState.load(from: rig.paths.state).layoutVersion == 2)
    let snap = rig.paths.backups.appending(path: "20261113-175217")
    #expect(try read(snap.appending(path: "Library/Application Support/retromac/ES-DE/settings/es_settings.xml")) == "<settings/>")
    #expect(!rig.exists(snap.appending(path: "ES-DE")))
    #expect(try read(snap.appending(path: ".retromac-created"))
        == "Library/Application Support/retromac/ES-DE/custom_systems/es_systems.xml\nLibrary/Application Support/RetroArch/config/retroarch.cfg\n")
    #expect(!rig.migrator().isNeeded)
}
@Test func refusesWhileESDERunning() throws {
    let rig = try LegacyRig()
    try rig.buildLegacy()
    #expect(throws: MigrationError.appRunning("ES-DE.app")) { try rig.migrator(running: "ES-DE.app").run() }
    #expect(rig.exists(rig.legacy.root.appending(path: "Library/nes/a.nes")))
    #expect(!rig.exists(rig.paths.root))
}
@Test func leavesUserOwnedThingsAlone() throws {
    let rig = try LegacyRig()
    try rig.buildLegacy(esdeManaged: false, retroarchManaged: false)
    let report = try rig.migrator().run()
    #expect(rig.exists(rig.legacy.applications.appending(path: "RetroArch.app")))
    #expect(rig.exists(rig.legacy.esde.appending(path: "gamelists/nes/gamelist.xml")))
    #expect(Set(report.leftAlone).isSuperset(of: ["RetroArch.app (yours)", "ES-DE.app (yours)", "~/ES-DE (yours)"]))
}
@Test func conflictingFileGoesToLeftovers() throws {
    let rig = try LegacyRig()
    try rig.buildLegacy()
    try write("newer", to: rig.paths.root.appending(path: "update-cache.json"))
    try write("older", to: rig.legacy.root.appending(path: "update-cache.json"))
    _ = try rig.migrator().run()
    #expect(try read(rig.paths.root.appending(path: "update-cache.json")) == "newer")
    #expect(try read(rig.paths.root.appending(path: "Leftovers from ~:retromac/update-cache.json")) == "older")
    #expect(!rig.exists(rig.legacy.root))
}
@Test func restoreAfterMigrationUsesNewLocation() throws {
    let rig = try LegacyRig()
    try rig.buildLegacy()
    _ = try rig.migrator().run()
    let store = BackupStore(root: rig.paths.backups, home: rig.home)
    try store.restore(rig.paths.backups.appending(path: "20261113-175217"))
    #expect(try read(rig.paths.esdeSettings) == "<settings/>")
    #expect(!rig.exists(rig.legacy.esde))
}
@Test func nothingToMigrateIsNoOp() throws {
    let rig = try LegacyRig()
    #expect(!rig.migrator().isNeeded)
    #expect(try rig.migrator().run() == MigrationReport())
}
@Test func planListsWhatRunMovesAndMovesNothing() throws {
    let rig = try LegacyRig()
    try rig.buildLegacy()
    let planned = rig.migrator().plan()
    #expect(rig.exists(rig.legacy.root.appending(path: "Library/nes/a.nes")))
    #expect(!rig.exists(rig.paths.root))
    let ran = try rig.migrator().run()
    #expect(Set(planned.moved) == Set(ran.moved))
    #expect(planned.moved.contains("RetroArch.app") && planned.moved.contains("~/ES-DE"))
}
@Test func freshInstallNextToUsersOwnAppsIsNotMigrated() async throws {
    let rig = try LegacyRig()
    try writePlist(version: "3.5.0", to: rig.legacy.applications.appending(path: "ES-DE.app"))
    try write("<mine/>", to: rig.legacy.esde.appending(path: "gamelists/nes/gamelist.xml"))
    let installer = Installer(manifest: manifest(), paths: rig.paths, downloader: host, runner: ProcessRunner())
    _ = try await installer.install(systems: [])
    var state = try InstallState.load(from: rig.paths.state)
    #expect(state.layoutVersion == 2)
    state.apps["esde"] = .init(version: "3.5.0", sha256: "x", managed: true)
    try state.save(to: rig.paths.state)
    #expect(!rig.migrator().isNeeded)
    #expect(try rig.migrator().run() == MigrationReport())
    #expect(try read(rig.legacy.esde.appending(path: "gamelists/nes/gamelist.xml")) == "<mine/>")
}
@Test func blockedAppMoveIsLeftForReinstall() throws {
    let rig = try LegacyRig()
    try rig.buildLegacy()
    let blocked = rig.legacy.applications.appending(path: "ES-DE.app")
    try ProcessRunner().run("/usr/bin/chflags", ["uchg", blocked.path])
    defer { _ = try? ProcessRunner().run("/usr/bin/chflags", ["nouchg", blocked.path]) }
    let report = try rig.migrator().run()
    #expect(report.leftAlone.contains("ES-DE.app (couldn't move — retromac will install a fresh copy)"))
    #expect(rig.exists(rig.paths.applications.appending(path: "RetroArch.app")))
    #expect(try read(rig.paths.esdeRoot.appending(path: "gamelists/nes/gamelist.xml")) == "<gamelist/>")
    #expect(!rig.exists(rig.legacy.esde))
    #expect(!rig.migrator().isNeeded)
}
@Test func dataMoveFailureStillResumes() throws {
    let rig = try LegacyRig()
    try rig.buildLegacy()
    let stuck = rig.legacy.root.appending(path: "previous")
    try ProcessRunner().run("/usr/bin/chflags", ["uchg", stuck.path])
    #expect(throws: MigrationError.self) { try rig.migrator().run() }
    try ProcessRunner().run("/usr/bin/chflags", ["nouchg", stuck.path])
    #expect(rig.migrator().isNeeded)
    _ = try rig.migrator().run()
    #expect(try read(rig.paths.root.appending(path: "previous/x.dylib")) == "old")
    #expect(!rig.migrator().isNeeded)
}
@Test func migrationPreparesESDEBeforeConfigsAreApplied() throws {
    let rig = try LegacyRig()
    try rig.buildLegacy()
    try write("<?xml version=\"1.0\"?>\n<string name=\"ROMDirectory\" value=\"\(rig.legacy.root.appending(path: "Library").path)\" />\n",
              to: rig.legacy.esde.appending(path: "settings/es_settings.xml"))
    _ = try rig.migrator().run()
    #expect(try read(rig.paths.esdeSettings).contains("value=\"\(rig.paths.defaultLibraryRoot.path)\""))
    #expect(try read(rig.paths.esdeFindRules).contains(rig.paths.retroarchExecutable.path))
    let snapshot = rig.paths.backups.appending(path: "20261113-175217/Library/Application Support/retromac/ES-DE/settings/es_settings.xml")
    #expect(try !read(snapshot).contains(rig.legacy.root.path))
}
@Test func customLibraryOnSameVolumeMovesIn() throws {
    let rig = try LegacyRig()
    try rig.buildLegacy()
    let custom = rig.home.appending(path: "Games")
    try write("rom", to: custom.appending(path: "snes/b.sfc"))
    var profile = try Profile.load(from: rig.legacy.root.appending(path: "profile.json"))
    profile.libraryRoot = custom
    try profile.save(to: rig.legacy.root.appending(path: "profile.json"))
    _ = try rig.migrator().run()
    #expect(try read(rig.paths.defaultLibraryRoot.appending(path: "snes/b.sfc")) == "rom")
    #expect(try Profile.load(from: rig.paths.profile).libraryRoot == rig.paths.defaultLibraryRoot)
    #expect(!rig.exists(custom))
}
