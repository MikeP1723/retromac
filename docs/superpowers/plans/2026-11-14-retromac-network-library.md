# Network Library Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an advanced user point retromac's game library at a server share (one folder per console), which retromac mounts itself and only ever reads from.

**Architecture:**
- **Profile:** `Profile` gains an optional `NetworkLibrary` (the share's address, plus the local library to restore). When it's set, `libraryRoot` is the mounted folder and the library is read-only.
- **Mounting:** a `NetworkShare` type in RetromacCore mounts the share through a small `ShareMounter` protocol. NetFS is the real implementation; tests use a fake.
- **Read-only:** the existing library writers, and the two "missing library → reset to local" fallbacks, check `Profile.isLibraryReadOnly`.
- **App:** the Library screen gets an "Advanced: network library" section. Play, launch and Console Mode mount before ES-DE starts.

**Tech Stack:** Swift 6 SwiftPM, macOS 14+ arm64, SwiftUI, Swift Testing, NetFS.framework (system). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-14-network-library-design.md` (approved by Mike 2026-11-14).

## Global Constraints

- New files start with `// SPDX-License-Identifier: GPL-3.0-or-later`. Swift 6 strict concurrency, zero warnings in new code, no third-party dependencies. NetFS is a system framework; link it in `Package.swift` (`.linkedFramework("NetFS")`).
- **Never write to the share.** That covers console folders, `.cue`, `Game.m3u`, imports, CHD conversion and leftover cleanup. The two library-reset fallbacks are skipped too (spec anti-goals).
- **No server passwords.** NetFS mounts with macOS's login UI allowed (`kNAUIOptionKey: kNAUIOptionAllowUI`). macOS prompts and can save the password to the Keychain. retromac stores only the address.
- **Protocols:** SMB only. `smb://` addresses are accepted; anything else is rejected with "Enter an smb:// address, for example smb://nas/media/roms." This settles the spec's "Left to the builder" item (Claude's call):
  - AFP is deprecated in macOS.
  - NFS export paths don't split cleanly into share and sub-folder.
- **Folder names:** console folders are matched against `SystemID.allCases` raw values, case-insensitively. SMB mounts on macOS are case-insensitive, and ES-DE's `%ROMPATH%/snes` resolves on them.
- **Copy** (verbatim):
  - Section title: `Advanced: network library`
  - Read-only note: `retromac only reads from this folder. It never adds, moves, converts or deletes anything there. Multi-disc PS1 and Saturn games need their .m3u playlist, and .bin discs their .cue, already on the share.`
  - Not connected (Play alert and home-screen banner): `Your network library isn't connected.` The Play alert's button is `Try again`; the banner's is `Reconnect`.
  - Add Games while read-only: `Games come from your network library, so Add Games is off. Turn the network library off to add games here.`
  - Bad address: `Enter an smb:// address, for example smb://nas/media/roms.`
- **Coordination:** Phase 6 (`phase6-rosetta`, unmerged) derives PCSX2's `GameList/RecursivePaths` from `libraryRoot`, so it follows the share with no change here. Its `ChdTool` PS2 path goes through the same `removeLeftovers` / Shrink gates.

## Review Focus

1. **The share is already mounted** under another `/Volumes` name (`media-1`), or Finder mounted it with `user@` in the URL. Expected: retromac reuses that mount and never mounts it twice. Test in Task 2.
2. **An address typed loosely:** with spaces, a trailing slash, `user@`, `SMB://` in capitals, or no sub-folder. Expected: it parses to the right share and sub-folder, or is clearly rejected. Test in Task 1.
3. **The server is unreachable** at launch, at Play, or at login with Console Mode. Expected: ES-DE never opens on an empty library, and the library path never changes by itself. Tests in Task 3 (`resolvingLibrary`), plus a hands-on check in Task 6.
4. **Anything writes to the share:** console folders on Apply, disc organizing, leftover CHD cleanup, imports, a legacy migration. Expected: nothing touches it. Tests in Task 3.
5. **Turning it off doesn't restore the exact previous local library,** including a custom one on an external drive. Expected: the same path as before. Test in Task 1.

---

### Task 1: The network library in the profile

**Files:**
- Create: `Sources/RetromacCore/Model/NetworkLibrary.swift`
- Modify: `Sources/RetromacCore/Model/Profile.swift`
- Test: `Tests/RetromacCoreTests/NetworkLibraryTests.swift`

**Interfaces:**
- Produces:
  - `public struct NetworkLibrary: Codable, Equatable, Sendable { public var url: URL; public var localLibrary: URL }`
  - `public static func parse(_ text: String) -> URL?`: trims whitespace, accepts `smb://` in any letter case, percent-encodes spaces, drops a trailing slash, and needs a host plus at least one path component (the share).
  - `public var share: URL`, which is `smb://[user@]host/<first path component>`.
  - `public var subpath: String`, the remaining components joined by `/`, or `""`.
  - `Profile.networkLibrary: NetworkLibrary?` (decodes as nil from older profiles) and `Profile.isLibraryReadOnly: Bool` (`networkLibrary != nil`).
  - `mutating func useNetworkLibrary(_ url: URL, at folder: URL)` keeps `localLibrary` as the current local `libraryRoot`, or keeps the stored one when a network library is already on. It then sets `libraryRoot = folder`.
  - `mutating func useLocalLibrary()` restores `libraryRoot = localLibrary` and sets `networkLibrary = nil`.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func addressesParseToShareAndSubfolder() throws {
    let a = try #require(NetworkLibrary.parse("  SMB://nas/media/roms/  "))
    let lib = NetworkLibrary(url: a, localLibrary: URL(filePath: "/x"))
    #expect(lib.share.absoluteString == "smb://nas/media" && lib.subpath == "roms")
    let b = try #require(NetworkLibrary.parse("smb://mike@nas/My Games"))
    #expect(NetworkLibrary(url: b, localLibrary: URL(filePath: "/x")).share.absoluteString == "smb://mike@nas/My%20Games")
    #expect(NetworkLibrary(url: b, localLibrary: URL(filePath: "/x")).subpath == "")
    #expect(NetworkLibrary.parse("smb://nas") == nil)
    #expect(NetworkLibrary.parse("afp://nas/media") == nil && NetworkLibrary.parse("/Volumes/media") == nil)
}
@Test func olderProfilesHaveNoNetworkLibrary() throws { /* decode a saved profile JSON without the key → nil, not read-only */ }
@Test func turningItOffRestoresTheExactLocalLibrary() {
    var p = profile(library: URL(filePath: "/Volumes/External/Games"))
    p.useNetworkLibrary(URL(string: "smb://nas/media/roms")!, at: URL(filePath: "/Volumes/media/roms"))
    #expect(p.isLibraryReadOnly && p.libraryRoot.path == "/Volumes/media/roms")
    p.useNetworkLibrary(URL(string: "smb://nas/other")!, at: URL(filePath: "/Volumes/other"))  // switching shares keeps the original
    p.useLocalLibrary()
    #expect(!p.isLibraryReadOnly && p.libraryRoot.path == "/Volumes/External/Games")
}
```

- [ ] **Step 2: Run** `swift test --filter NetworkLibrary`. Expected: compile failure.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: network library in the profile`

---

### Task 2: Mounting the share

**Files:**
- Create: `Sources/RetromacCore/Support/NetworkShare.swift`
- Modify: `Package.swift` (link NetFS to RetromacCore)
- Test: `Tests/RetromacCoreTests/NetworkShareTests.swift`

**Interfaces:**
- Consumes: Task 1's `NetworkLibrary.share` / `subpath`.
- Produces:
  - `public enum NetworkShareError: Error, Equatable { case cancelled, unreachable(String), folderMissing(String) }`
  - `public protocol ShareMounter: Sendable { func mount(_ share: URL) throws -> URL; func mounted() -> [(remount: URL, mountPoint: URL)] }`
  - `public struct NetFSMounter: ShareMounter`:
    - Mounting uses `NetFSMountURLSync` with `kNAUIOptionKey: kNAUIOptionAllowUI`.
    - `ECANCELED` and `userCanceledErr` (-128) map to `.cancelled`. `EEXIST` falls back to `mounted()`. Any other code maps to `.unreachable(<strerror>)`.
    - `mounted()` reads `FileManager.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeURLForRemountingKey])`.
  - `public struct NetworkShare: Sendable { init(mounter: any ShareMounter = NetFSMounter()); func libraryFolder(for library: NetworkLibrary) throws -> URL }`:
    - A volume whose remount URL has the same host (case-insensitive) and share (case-insensitive, user ignored) is reused.
    - Otherwise it calls `mount`.
    - It returns `mountPoint/subpath`, or throws `.folderMissing(subpath)` when that folder doesn't exist.

- [ ] **Step 1: Write the failing tests** using a `FakeMounter` that records `mount` calls and returns configured mounts. Every test uses temp directories as mount points.
  - `alreadyMountedUnderAnotherNameIsReused` (Review Focus 1): mounted `smb://MIKE@NAS/Media` at `<tmp>/media-1`, library `smb://nas/media/roms`; the result is `<tmp>/media-1/roms`; `mount` is never called.
  - `mountsWhenNotMounted`: `mount` is called once with `smb://nas/media`, and the result has the sub-folder.
  - `missingSubfolderIsReported`: `.folderMissing("roms")`.
  - `cancelledLoginIsReported`: the fake throws `.cancelled`, and it propagates.
- [ ] **Step 2: Run.** Expected: FAIL. **Step 3: Implement.** **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: mount the network library share`

---

### Task 3: Never write to the share; never fall back silently

**Files:**
- Modify:
  - `Sources/RetromacCore/Render/ProfileRenderer.swift` (the `.directory` loop)
  - `Sources/RetromacCore/Support/Migrator.swift` (step 5)
  - `Sources/RetromacCore/Model/Profile.swift`
  - `Sources/retromac/WizardModel.swift` (`loadProfile`, the two `DiscSets.organizeLibrary` calls)
  - `Sources/retromac/GamesModel.swift` (`refreshConvertible`)
  - `Sources/retromac-tool/main.swift` (`importGames`)
- Test: `Tests/RetromacCoreTests/NetworkLibraryTests.swift`, `Tests/RetromacCoreTests/MigratorTests.swift`

**Interfaces:**
- Consumes: Task 1's `isLibraryReadOnly`.
- Produces:
  - **`Profile.resolvingLibrary(paths: Paths) -> Profile`** moves the existing reset rule out of `WizardModel.loadProfile`: a missing or legacy-folder library resets to `paths.defaultLibraryRoot`. When `isLibraryReadOnly`, it returns the profile unchanged. `loadProfile` calls it.
  - **Writers skipped while read-only:**
    - `ProfileRenderer.render` emits no `.directory` files.
    - `Migrator` step 5 leaves the library alone.
    - `WizardModel` skips `DiscSets.organizeLibrary`.
    - `GamesModel.refreshConvertible` skips `removeLeftovers` and reports `convertibleCount = 0`.
    - `retromac-tool import` prints `The library is a read-only network library.` and exits 1, unless `--library` is given.

- [ ] **Step 1: Write the failing tests**
  - `noConsoleFoldersAreCreatedOnTheShare` (Review Focus 4): render a read-only profile; no file has `.directory` kind.
  - `networkLibraryIsNeverResetWhenOffline` (Review Focus 3): `resolvingLibrary` on a read-only profile whose `libraryRoot` doesn't exist returns it unchanged.
  - `missingLocalLibraryStillResets`: the existing behaviour, kept.
  - `migrationLeavesANetworkLibraryAlone` (MigratorTests): a legacy install whose saved profile has a network library with a missing `libraryRoot`; after `run()` the profile's `libraryRoot` and `networkLibrary` are unchanged.
- [ ] **Step 2: Run.** Expected: FAIL. **Step 3: Implement.** **Step 4: Run** `swift test`. Expected: all pass. `swift build` succeeds for all targets.
- [ ] **Step 5: Commit** `feat: a network library is never written to or reset`

---

### Task 4: Finding the console folders

**Files:**
- Modify: `Sources/RetromacCore/Model/NetworkLibrary.swift`
- Test: `Tests/RetromacCoreTests/NetworkLibraryTests.swift`

**Interfaces:**
- Produces: `public static func consoleFolders(in folder: URL) -> (found: [SystemID], other: [String])`.
  - `found` lists the `SystemID.allCases` whose raw value matches a subfolder name case-insensitively, in `allCases` order.
  - `other` lists the remaining non-hidden subfolder names, sorted, so the user can see what to rename.
  - Files are ignored.

- [ ] **Step 1: Write the failing test** `consoleFoldersAreMatchedByESDEName`: subfolders `SNES`, `psx`, `Nintendo 64`, `.Trashes` and a file `readme.txt` give `found == [.snes, .psx]` and `other == ["Nintendo 64"]`.
- [ ] **Step 2: Run.** Expected: FAIL. **Step 3: Implement.** **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: list a network library's console folders`

---

### Task 5: The app: setting it up, connecting, read-only screens

**Files:**
- Modify:
  - `Sources/retromac/AppModel.swift` (`play`, `showGamesInFinder`, `LibraryStats.scan`, a new connection state)
  - `Sources/retromac/WizardModel.swift`
  - `Sources/retromac/Views/LibraryView.swift`
  - `Sources/retromac/Views/HomeView.swift` (or wherever the home screen view lives)

**Interfaces:**
- Consumes: Tasks 1–4.
- Produces (app target; no unit tests, verified in Task 7):
  - **Connection state:** `AppModel.networkStatus: NetworkStatus` with `enum NetworkStatus { case local, connected, notConnected(String) }`.
  - **Connecting:** `AppModel.connectNetworkLibrary() async` runs `NetworkShare().libraryFolder(for:)` off the main actor, updates `wizard.profile.libraryRoot` if the mount point changed, then sets the status. It's called at launch, by **Reconnect**, and at the start of `play()`.
  - **Play:**
    - If not connected, Play shows an alert, `Your network library isn't connected.`, with `Try again`. It doesn't post the console play notification and doesn't open ES-DE.
    - If connected, it does what it does today.
  - **Home screen:** shows the `Your network library isn't connected.` banner with `Reconnect` when the status is `.notConnected`.
- **Library screen:**
  - **The `Advanced: network library` disclosure** holds:
    - an address field, **Connect** (which runs `parse` and `libraryFolder`, or shows the bad-address copy), and the result of `consoleFolders(in:)` (found consoles by display name, and other folders as "Not used: …").
    - **Use this library**, which calls `profile.useNetworkLibrary`, saves the profile, and runs `applyConfigs()`. On `ApplyError.appRunning` it shows "Quit <app> and try again." and rolls the profile back.
    - **Turn off network library**, which calls `useLocalLibrary` and runs `applyConfigs()`.
    - the read-only note.
  - **While read-only:**
    - Add Games, folder import and the drop target are disabled, with the Add Games copy.
    - DAT import stays available. *(Claude's call: DATs are retromac's own data, not the share's.)*
    - Shrink disc games is hidden.
- **Other changes:**
  - `showGamesInFinder` doesn't create the folder when it's read-only.
  - `LibraryStats.scan` counts games but skips the size total when read-only (the storage readout shows only the game count).

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run** `swift build` and `swift test`. Expected: zero errors or warnings in changed files; all pass.
- [ ] **Step 3: Commit** `feat: network library setup, connection and read-only Library screen`

---

### Task 6: Console Mode mounts before ES-DE

**Files:**
- Modify: `Sources/retromac-console/AgentController.swift` (`launchESDE`)

**Interfaces:**
- Consumes: Task 2's `NetworkShare`; the profile from `paths.profile`.
- Produces:
  - When the saved profile has a network library, `launchESDE` (login, wake, and Play's notification) first runs `NetworkShare().libraryFolder(for:)` off the main actor.
  - On failure it calls the agent's existing `openHome()` instead of opening ES-DE. retromac then shows the banner from Task 5.
  - A play notification only arrives after Play has connected, so this path only matters at login and on wake.

- [ ] **Step 1: Implement.** **Step 2: Run** `swift build`. Expected: no errors or warnings. Then `swift test`; all pass.
- [ ] **Step 3: Commit** `feat: console mode connects the network library before ES-DE`

---

### Task 7: End to end with Mike's server

Touches Mike's real setup and server, read-only. **Confirm with Mike before Step 2.**

- [ ] **Step 1:** `RETROMAC_VERSION=0.6.0 scripts/bundle.sh` (or the next free version); install as `/Applications/retromac.app`.
- [ ] **Step 2:** Mike enters his share in Library › Advanced: network library, then **Connect**. Expected:
  - macOS's login prompt appears, if needed.
  - The found consoles match his folders.
  - **Use this library** applies.
  - `es_settings.xml` `ROMDirectory`, Dolphin `ISOPath0` and xemu `games_dir` point into `/Volumes/<share>/…`.
- [ ] **Step 3:** Play. ES-DE lists games from the share and a game launches. Record ES-DE's start-up time with the share, and with the local library for comparison. If it's long, record it as a follow-up; the spec's ES-DE setting question is decided here.
- [ ] **Step 4:** Read-only check:
  - Before and after Install & Apply and a Library visit, `find /Volumes/<share>/<sub> -newer <timestamp file>` lists nothing.
  - Add Games is disabled and Shrink is hidden.
- [ ] **Step 5:** Offline check:
  - Eject the share in Finder, quit retromac, reopen it. The banner shows, and **Reconnect** works.
  - With the server unreachable (Wi-Fi off), Play shows the alert and ES-DE doesn't open.
- [ ] **Step 6:** **Turn off network library** restores the previous local library and its games.
- [ ] **Step 7:** Record the results in the ledger.
