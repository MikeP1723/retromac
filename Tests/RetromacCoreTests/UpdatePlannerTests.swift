// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Testing
@testable import RetromacCore

func installedState(apps: [String: InstallState.App] = [:], cores: [String: InstallState.Core] = [:]) -> InstallState {
    InstallState(manifestVersion: 1, apps: apps, cores: cores)
}

let managedRetroArch = InstallState.App(version: "1.0", sha256: String(repeating: "a", count: 64), managed: true)
let unpinnedMesen = InstallState.Core(version: "0.9.9", sha256: String(repeating: "c", count: 64), file: "mesen_libretro.dylib", crc32: "4a3d52b1")

func unpinned(_ m: Manifest) -> Manifest {
    var m = m
    for i in m.cores.indices { m.cores[i].sha256 = nil }
    return m
}

@Test func semverOrdering() {
    #expect(SemVer.compare("0.1.0", "0.2.0") == .orderedAscending)
    #expect(SemVer.compare("v1.10.0", "1.9.3") == .orderedDescending)
    #expect(SemVer.compare("1.2", "1.2.0") == .orderedSame)
}
@Test func offersChangedManagedApp() {
    var latest = Manifest.fixture(); latest.apps[0].version = "1.1"
    let plan = UpdatePlanner.plan(state: installedState(apps: ["retroarch": managedRetroArch]), applied: .fixture(),
                                  latest: latest, coreIndex: nil, appVersion: "0.1.0")
    #expect(plan.updates == [ComponentUpdate(id: "retroarch", kind: .app, installed: "1.0", available: "1.1", managed: true,
                                             license: "GPL-3.0-or-later", previousLicense: nil, requiresRosetta: false)])
}
@Test func flagsLicenseChange() {
    var latest = Manifest.fixture(); latest.cores[0].license = "GPL-2.0-only"; latest.cores[0].sha256 = String(repeating: "b", count: 64)
    let state = installedState(cores: ["mesen": .init(version: "1.0", sha256: String(repeating: "a", count: 64), file: "mesen_libretro.dylib")])
    let plan = UpdatePlanner.plan(state: state, applied: .fixture(), latest: latest, coreIndex: nil, appVersion: "0.1.0")
    #expect(plan.updates.first?.previousLicense == "GPL-3.0-or-later")
    #expect(plan.updates.first?.license == "GPL-2.0-only")
}
@Test func flagsRosetta() {
    var latest = Manifest.fixture(); latest.apps[0].version = "1.1"; latest.apps[0].arch = .x86_64; latest.apps[0].rosetta = true
    let plan = UpdatePlanner.plan(state: installedState(apps: ["retroarch": managedRetroArch]), applied: .fixture(),
                                  latest: latest, coreIndex: nil, appVersion: "0.1.0")
    #expect(plan.updates.first?.requiresRosetta == true)
}
@Test func ignoresComponentsNotInstalled() {
    var latest = Manifest.fixture(); latest.cores[1].sha256 = String(repeating: "b", count: 64)
    let state = installedState(cores: ["mesen": .init(version: "1.0", sha256: String(repeating: "a", count: 64), file: "mesen_libretro.dylib")])
    #expect(UpdatePlanner.plan(state: state, applied: .fixture(), latest: latest, coreIndex: nil, appVersion: "0.1.0").updates.isEmpty)
}
@Test func offersUnpinnedCoreRebuild() {
    let index = CoreIndex.parse("2026-11-20 deadbeef mesen_libretro.dylib.zip\n")
    let plan = UpdatePlanner.plan(state: installedState(cores: ["mesen": unpinnedMesen]), applied: unpinned(.fixture()),
                                  latest: unpinned(.fixture()), coreIndex: index, appVersion: "0.1.0")
    #expect(plan.updates == [ComponentUpdate(id: "mesen", kind: .core, installed: "0.9.9", available: "rebuild 2026-11-20", managed: true,
                                             license: "GPL-3.0-or-later", previousLicense: nil, requiresRosetta: false)])
}
@Test func unpinnedCoreUpToDate() {
    let index = CoreIndex.parse("2026-11-13 4a3d52b1 mesen_libretro.dylib.zip\n")
    #expect(UpdatePlanner.plan(state: installedState(cores: ["mesen": unpinnedMesen]), applied: unpinned(.fixture()),
                               latest: unpinned(.fixture()), coreIndex: index, appVersion: "0.1.0").updates.isEmpty)
}
@Test func unpinnedCoreWithoutRecordedCrcIsOfferedOnce() {
    var core = unpinnedMesen; core.crc32 = nil
    let index = CoreIndex.parse("2026-11-13 4a3d52b1 mesen_libretro.dylib.zip\n")
    #expect(UpdatePlanner.plan(state: installedState(cores: ["mesen": core]), applied: unpinned(.fixture()),
                               latest: unpinned(.fixture()), coreIndex: index, appVersion: "0.1.0").updates.map(\.id) == ["mesen"])
}
@Test func parsesCoreIndex() {
    let index = CoreIndex.parse("2026-11-13 4a3d52b1 mesen_libretro.dylib.zip\ngarbage\n")
    #expect(index.entries == ["mesen_libretro.dylib.zip": .init(date: "2026-11-13", crc32: "4a3d52b1")])
}
@Test func crc32KnownVector() throws {
    let url = try makeTempDir().appending(path: "v")
    try Data("123456789".utf8).write(to: url)
    #expect(try CRC32.hex(of: url) == "cbf43926")
}
@Test func unmanagedAppListedAsUnmanaged() {
    var latest = Manifest.fixture(); latest.apps[0].version = "1.0"
    let state = installedState(apps: ["retroarch": .init(version: "0.9", sha256: nil, managed: false)])
    #expect(UpdatePlanner.plan(state: state, applied: .fixture(), latest: latest, coreIndex: nil, appVersion: "0.1.0").updates.first?.managed == false)
}
@Test func minAppVersionBlocksComponents() {
    var latest = Manifest.fixture(); latest.minAppVersion = "0.3.0"; latest.apps[0].version = "1.1"
    latest.retromac = SelfEntry(version: "0.3.0", url: URL(string: "https://github.com/MikeP1723/retromac/releases/download/v0.3.0/retromac.zip")!,
                                sha256: String(repeating: "d", count: 64))
    let plan = UpdatePlanner.plan(state: installedState(apps: ["retroarch": managedRetroArch]), applied: .fixture(),
                                  latest: latest, coreIndex: nil, appVersion: "0.2.0")
    #expect(plan.updates.isEmpty)
    #expect(plan.blockedByMinAppVersion == "0.3.0")
    #expect(plan.retromacUpdate?.version == "0.3.0")
}
@Test func selfEntryPolicy() {
    var m = Manifest.fixture()
    m.retromac = SelfEntry(version: "0.2.0", url: URL(string: "https://evil.example/retromac.zip")!, sha256: String(repeating: "d", count: 64))
    #expect(ManifestPolicy.violations(m).contains("retromac: host evil.example not in allowlist"))
    m.retromac?.url = URL(string: "https://buildbot.libretro.com/retromac.zip")!
    #expect(ManifestPolicy.violations(m).contains("retromac: url host must be github.com"))
}
@Test func phase1StateStillDecodes() throws {
    let json = #"{"manifestVersion":1,"apps":{"esde":{"version":"3.5.0","managed":true}},"cores":{"mesen":{"version":"0.9.9","sha256":"x","file":"m.dylib"}}}"#
    let state = try JSONDecoder().decode(InstallState.self, from: Data(json.utf8))
    #expect(state.cores["mesen"]?.crc32 == nil)
    #expect(state.previousApps == nil)
}
