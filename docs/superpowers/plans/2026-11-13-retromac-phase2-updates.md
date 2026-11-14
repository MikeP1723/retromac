# retromac Phase 2 (Updates) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update retromac itself, plus every emulator and core it manages, through an in-app wizard with staged, sha-verified swaps and one-generation rollback. A release pipeline and a weekly upstream-bump Action keep the pins current.

**Architecture:** GitHub Releases on `MikeP1723/retromac` is the single update channel. Each release carries `retromac.zip` and a release `manifest.json` (the bundled manifest plus a `retromac` self-entry). `UpdatePlanner` is pure. It diffs `InstallState` against the latest manifest for apps, and against libretro's buildbot `.index-extended` for unpinned cores. `Updater` stages through `Installer`, swaps with `previous/` as the rollback slot, then re-renders and re-applies configs. `SelfUpdater` stages the zip and hands off to a detached swap script. Maintainer-side automation lives in `retromac-tool` subcommands plus two workflows.

**Tech Stack:** Same as Phase 1. No new dependencies. Workflows use `gh` (preinstalled on GitHub macOS runners).

**Spec:** `docs/superpowers/specs/2026-11-13-retromac-design.md` (section "Updates"). **Requires Phase 1 complete:** `Manifest`, `ManifestPolicy`, `Paths`, `Installer`, `InstallState`, `Applier`, `ProfileRenderer`, `BackupStore`, `retromac-tool`, `scripts/bundle.sh`.

> **Revised 2026-11-13 after Phase 1 merged (PR #1).** This revision incorporates the following:
> - `AppEntry` has no `bundleID`; running-app checks use app bundle names (`apps:`).
> - `CommandRunner.run(_:_:input:)` takes stdin input.
> - Core `sha256` is optional: cores are fetched unpinned from `buildbot.libretro.com/nightly/apple/osx/arm64/latest/`.
> - Test fixtures are served over https URLs by `FixtureDownloader`, because `URLSessionDownloader` refuses non-https.
>
> **Core rebuild detection (verified 2026-11-13).** `https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/.index-extended` lists `<date> <crc32> <file>.zip` per core. The CRC32 is of the **dylib inside** the zip, not of the zip itself (checked: mesen zip CRC `4019ca04`, dylib CRC `4a3d52b1` = index value). retromac records the installed dylib's CRC32 and offers a rebuild when the index value differs.

## Global Constraints

- Phase 1's Global Constraints all still apply: arm64, zero third-party deps, SPDX headers, license allowlists, host allowlist, no ROM/BIOS/firmware/key content, bundle ID `petersoft.retromac`.
- Update channel: `https://api.github.com/repos/MikeP1723/retromac/releases/latest`. Release assets are named exactly `retromac.zip` and `manifest.json`.
- A release manifest that has any `ManifestPolicy` violation is rejected as a whole, and nothing from it is offered.
- The retromac self-entry URL host must be `github.com`. The extracted bundle ID must be `petersoft.retromac`.
- Nothing is swapped until every selected component has been staged and sha-verified.
- Updates are refused while any manifest app (matched by bundle name, e.g. `ES-DE.app`) is running.
- Apps with `managed == false` are never replaced unless the user adopts them explicitly.
- The rollback slot is `~/retromac/previous/` and holds exactly one generation per component.
- Tests never use `file://` URLs. Release and asset fixtures are served through `FixtureDownloader` keyed by https URLs (Phase 1 `InstallerTests.swift`).
- The automatic update check runs at most once every 24h (last-check time in `UserDefaults`), plus on demand with ⌘U. Nothing is installed without the user confirming in the wizard.

## Review Focus

1. **A failure mid-swap** (the move-in fails after the current copy was moved out). Expected: the current copy is moved back, `InstallState` is unchanged, and the error is reported. Test in Task 3.
2. **Tampered or invalid release manifest** (unlisted host, non-free license, bad sha, x86 without rosetta). Expected: `UpdateError.policy` lists the violations, and the planner never sees the manifest. Test in Task 2.
3. **Updating while an emulator is running.** Expected: refused before any download or swap. Test in Task 3.
4. **App older than `minAppVersion`.** Expected: only the self-update is offered, and component updates are blocked with the required version. Test in Task 1.
5. **A pre-existing, unmanaged RetroArch.** Expected: it's listed but never replaced unless adopted. On adoption, the original goes to `previous/` and can be reverted. Test in Task 3.

---

### Task 1: Manifest additions and update planner

**Files:**
- Modify: `Sources/RetromacCore/Manifest/Manifest.swift`, `Sources/RetromacCore/Support/Paths.swift`, `Sources/RetromacCore/Install/Installer.swift` (InstallState optional fields)
- Create: `Sources/RetromacCore/Update/SemVer.swift`, `Sources/RetromacCore/Update/UpdatePlanner.swift`
- Test: `Tests/RetromacCoreTests/UpdatePlannerTests.swift`

**Interfaces:**
- Consumes: `Manifest`, `AppEntry`, `CoreEntry`, `InstallState`, `Paths`, `Manifest.fixture()` (Phase 1)
- Produces:
  - `struct Upstream: Codable, Equatable, Sendable { enum Kind: String, Codable, Sendable { case githubRelease, gitlabRelease, libretroStable }; var kind: Kind; var project: String; var assetPattern: String }`.
    - For the `githubRelease` and `gitlabRelease` kinds, `assetPattern` is a regex matched against asset names.
    - For `libretroStable`, it's a URL template containing `{version}`.
  - Add `var upstream: Upstream?` to `AppEntry` and `CoreEntry`.
  - `struct SelfEntry: Codable, Equatable, Sendable { var version: String; var url: URL; var sha256: String }`. Add `var retromac: SelfEntry?` to `Manifest`. It's nil in the bundled manifest and set in release manifests.
  - `ManifestPolicy.violations` additionally checks `retromac`. Its sha must be 64 lowercase hex and its host must be exactly `github.com`. The violation id is `retromac`.
  - Add to `InstallState`: `var previousApps: [String: App]?` and `var previousCores: [String: Core]?`, plus `var crc32: String?` on `InstallState.Core`. All are optional, so Phase 1 state files still decode. `crc32` is the lowercase 8-hex CRC32 of the installed dylib.
  - `enum CRC32 { static func hex(of: URL) throws -> String }`, table-driven in Swift (no zlib dependency). Test: CRC32 of the 9 bytes `"123456789"` is `cbf43926`.
  - `Installer` records `crc32` when it installs a core.
  - `struct CoreIndex: Equatable, Sendable { struct Entry: Equatable, Sendable { var date: String; var crc32: String }; var entries: [String: Entry]; static let url = URL(string: "https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/.index-extended")!; static func parse(_ text: String) -> CoreIndex }`. Keys are archive names (`mesen_libretro.dylib.zip`). Lines that don't match `<date> <8 hex> <name>` are skipped.
  - Add to `Paths`: `previous` (`~/retromac/previous`) and `appliedManifest` (`~/retromac/manifest.json`).
  - `enum SemVer { static func compare(_ a: String, _ b: String) -> ComparisonResult }`. Strip a leading `v`, split on `.`, and compare integer components (missing = 0). A non-numeric component compares as 0.
  - `enum ComponentKind: String, Codable, Sendable { case app, core }`
  - `struct ComponentUpdate: Equatable, Sendable, Identifiable { var id: String; var kind: ComponentKind; var installed: String; var available: String; var managed: Bool; var license: String; var previousLicense: String?; var requiresRosetta: Bool }`. `previousLicense` is non-nil only when the license changed.
  - `struct UpdatePlan: Equatable, Sendable { var updates: [ComponentUpdate]; var retromacUpdate: SelfEntry?; var blockedByMinAppVersion: String? }`
  - `enum UpdatePlanner { static func plan(state: InstallState, applied: Manifest, latest: Manifest, coreIndex: CoreIndex?, appVersion: String) -> UpdatePlan }`
    - If `SemVer.compare(appVersion, latest.minAppVersion) == .orderedAscending`: set `blockedByMinAppVersion = latest.minAppVersion` and `updates = []`.
    - `retromacUpdate = latest.retromac` when its version is greater than `appVersion`.
    - An app is offered when `state.apps[id]` exists and its version or sha differs from the latest entry. `managed` comes from state.
    - A **pinned** core (`sha256 != nil`) is offered when `state.cores[id]` exists and its sha differs.
    - An **unpinned** core is offered when `state.cores[id]` exists, `coreIndex` has `<file>.zip`, and the index CRC differs from `state.cores[id].crc32`. Its `available` is `"rebuild <index date>"`. A core with `crc32 == nil` (installed before this phase) is offered once, so its CRC gets recorded.
    - Components missing from `state` are never offered, because installing new systems belongs to the main wizard.
    - `license`, `previousLicense`, and `requiresRosetta` come from comparing the `applied` and `latest` entries.
    - Output is sorted by `id`.

- [ ] **Step 1: Write the failing tests** (fixtures derive `latest` from `Manifest.fixture()` by mutating fields):

```swift
@Test func semverOrdering() {
    #expect(SemVer.compare("0.1.0", "0.2.0") == .orderedAscending)
    #expect(SemVer.compare("v1.10.0", "1.9.3") == .orderedDescending)
    #expect(SemVer.compare("1.2", "1.2.0") == .orderedSame)
}
@Test func offersChangedManagedApp() { /* state retroarch 1.0 managed; latest retroarch version "1.1" → updates == [ComponentUpdate(id:"retroarch", kind:.app, installed:"1.0", available:"1.1", managed:true, license:"GPL-3.0-or-later", previousLicense:nil, requiresRosetta:false)] */ }
@Test func flagsLicenseChange() { /* latest core mesen license "GPL-2.0-only" (applied GPL-3.0-or-later), sha changed → previousLicense == "GPL-3.0-or-later" */ }
@Test func flagsRosetta() { /* latest retroarch arch x86_64 rosetta true, version bump → requiresRosetta == true */ }
@Test func ignoresComponentsNotInstalled() { /* state has only mesen; latest bumps bsnes → updates.isEmpty */ }
@Test func offersUnpinnedCoreRebuild() { /* mesen unpinned, state crc32 "4a3d52b1"; index mesen_libretro.dylib.zip crc "deadbeef" date "2026-11-20" → one ComponentUpdate(id:"mesen", kind:.core, installed:"0.9.9", available:"rebuild 2026-11-20", ...) */ }
@Test func unpinnedCoreUpToDate() { /* index crc == state crc → no update */ }
@Test func parsesCoreIndex() { /* "2026-11-13 4a3d52b1 mesen_libretro.dylib.zip\ngarbage\n" → entries["mesen_libretro.dylib.zip"] == .init(date:"2026-11-13", crc32:"4a3d52b1"), count 1 */ }
@Test func crc32KnownVector() { /* CRC32 of "123456789" == "cbf43926" */ }
@Test func unmanagedAppListedAsUnmanaged() { /* state retroarch managed:false v0.9; latest 1.0 → managed == false */ }
@Test func minAppVersionBlocksComponents() {
    /* latest.minAppVersion "0.3.0", retromac SelfEntry version "0.3.0", appVersion "0.2.0", retroarch bumped
       → updates.isEmpty, blockedByMinAppVersion == "0.3.0", retromacUpdate?.version == "0.3.0" */
}
@Test func selfEntryPolicy() { /* retromac.url host "evil.example" → violations contains "retromac: host evil.example not in allowlist"; host "buildbot.libretro.com" → contains "retromac: url host must be github.com" */ }
@Test func phase1StateStillDecodes() throws { /* JSON without previousApps/previousCores decodes */ }
```

- [ ] **Step 2: Run `swift test --filter UpdatePlannerTests`.** Expected: FAIL.
- [ ] **Step 3: Implement the Produces types.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass, including the Phase 1 suite.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: update planner, semver, manifest self-entry and upstream fields"`

---

### Task 2: Release client

**Files:**
- Create: `Sources/RetromacCore/Update/ReleaseClient.swift`
- Test: `Tests/RetromacCoreTests/ReleaseClientTests.swift`

**Interfaces:**
- Consumes: `Downloader`, `URLSessionDownloader` (Phase 1), `Manifest`, `ManifestPolicy`
- Produces:
  - `enum UpdateError: Error, Equatable { case policy([String]); case noManifestAsset; case appRunning(String); case notManaged(String); case nothingToRollBack(String); case badSelfBundle(String) }`
  - `struct LatestRelease: Equatable, Sendable { var tag: String; var manifest: Manifest }`
  - `struct ReleaseClient { static let defaultAPIBase = URL(string: "https://api.github.com/repos/MikeP1723/retromac")!; init(apiBase: URL = defaultAPIBase, downloader: Downloader); func latest() async throws -> LatestRelease }`
    - Downloads `<apiBase>/releases/latest` into a temp dir and decodes `tag_name` and `assets[].{name, browser_download_url}`.
    - Downloads the asset named `manifest.json` (throws `noManifestAsset` if absent) and decodes it.
    - Throws `.policy(violations)` if any violations exist.
    - `URLSessionDownloader` gains an optional `headers: [String: String]` init parameter. `ReleaseClient`'s production downloader sets `Accept: application/vnd.github+json`.
  - `func coreIndex() async throws -> CoreIndex` downloads `CoreIndex.url` and parses it. It's a separate method, so a failing index never blocks app updates.

- [ ] **Step 1: Write the failing tests.** Serve `https://api.github.com/repos/MikeP1723/retromac/releases/latest` and the manifest's `browser_download_url` (an `https://github.com/...` URL) through `FixtureDownloader`, which gains `serve(_ local: URL, at url: URL)` to register an exact URL.

```swift
@Test func returnsValidatedManifest() async throws { /* valid fixture manifest → tag "v0.2.0", manifest == fixture */ }
@Test func rejectsPolicyViolations() async throws { /* manifest with core host evil.example → throws UpdateError.policy(["mesen: host evil.example not in allowlist"]) */ }
@Test func missingManifestAsset() async throws { /* assets: [] → throws .noManifestAsset */ }
```

- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: release client with manifest policy validation"`

---

### Task 3: Installer staging refactor, updater, and rollback

**Files:**
- Modify: `Sources/RetromacCore/Install/Installer.swift`
- Create: `Sources/RetromacCore/Update/Updater.swift`
- Test: `Tests/RetromacCoreTests/UpdaterTests.swift`

**Interfaces:**
- Consumes: `Installer`, `InstallState`, `Paths`, `Applier`, `ApplyReport`, `ProfileRenderer`, `Profile`, `DisplayRules`, `Manifest`, `ComponentUpdate`, `UpdateError`, `FileOps` (below)
- Produces:
  - In `Installer`:
    - `func stageApp(_ e: AppEntry) async throws -> URL`: download, verify sha, mount (feeding the license-agreement `Y`s as Phase 1 does), and `ditto` into a `.retromac-staging-<uuid>` dir inside `paths.applications`, so the later swap is a same-volume rename. Then detach. Returns the staged `.app` URL.
    - `func stageCore(_ e: CoreEntry, in dir: URL) async throws -> (dylib: URL, sha256: String, crc32: String)`: download, verify the sha when pinned, extract, reject symlinks. Returns the staged dylib and its hashes.
    - `install(systems:)` is reimplemented on top of these, and Phase 1 tests stay green.
  - `protocol FileOps: Sendable { func move(_ from: URL, to: URL) throws; func removeIfExists(_ url: URL) throws }` and `struct RealFileOps: FileOps`. These exist so the test can inject a failure.
  - `struct UpdateReport: Equatable, Sendable { var updated: [String]; var skipped: [String]; var config: ApplyReport? }`
  - `struct Updater { init(paths: Paths, installer: Installer, applier: Applier, apps: [String], isRunning: @escaping (String) -> Bool, fileOps: FileOps = RealFileOps()); func apply(_ updates: [ComponentUpdate], adopt: Set<String>, latest: Manifest, profile: Profile, rules: DisplayRules) async throws -> UpdateReport; func rollback(_ id: String) throws }`

**`apply` algorithm:**
1. If any app in `apps` is running, throw `.appRunning`.
2. Unmanaged updates whose id isn't in `adopt` go to `skipped` with `"<id>: not managed by retromac"`.
3. Stage **all** remaining components into one temp dir. Any staging error aborts before any swap.
4. Swap each component:
   - Remove `previous/<name>`.
   - Move the current copy to `previous/<name>`.
   - Move the staged copy into place.
   - If the move-in fails, move `previous/<name>` back and rethrow.
   - On success, `state.previousApps[id]` (or `previousCores`) gets the old entry, and the new entry is recorded with `managed: true`.
   - `<name>` is the `appName` for apps and the `file` for cores.
5. Save the state, write `latest` to `paths.appliedManifest`, then set `config = applier.apply(ProfileRenderer.render(profile, manifest: latest, rules:, paths:))`.

**`rollback(id)`:**
- Throws `.nothingToRollBack(id)` when there's no previous entry.
- Otherwise it swaps the current copy and `previous/` (using a temp name), swaps the state entries, and saves.

- [ ] **Step 1: Write the failing tests.** These use the Phase 1 dmg and zip fixture builders, with temp `home` and `applications`.

```swift
@Test func updatesManagedCoreAndKeepsPrevious() async throws { /* state mesen sha A; latest sha B (new fixture zip) → cores/<file> has new bytes; previous/<file> has old bytes; state.cores["mesen"].sha256 == B; previousCores["mesen"].sha256 == A */ }
@Test func refusesWhileEmulatorRunning() async throws { /* isRunning true for "RetroArch.app" → throws .appRunning("RetroArch.app"); downloader never called (counting fake Downloader) */ }
@Test func unpinnedCoreRebuildRecordsNewCrc() async throws { /* unpinned mesen, new fixture zip → state.cores["mesen"].crc32 == CRC32 of new dylib; previousCores holds the old entry */ }
@Test func skipsUnmanagedUnlessAdopted() async throws { /* retroarch managed:false → skipped ["retroarch: not managed by retromac"]; with adopt ["retroarch"] → updated, original Fake.app in previous/ */ }
@Test func stagingFailureSwapsNothing() async throws { /* two updates, second has wrong sha → throws checksumMismatch; first component unchanged on disk and in state */ }
@Test func moveInFailureRestoresCurrent() async throws { /* FileOps fake that throws on move into cores dir → error rethrown; cores/<file> still has old bytes; previous/ empty; state unchanged */ }
@Test func rollbackSwapsBack() throws { /* after update → rollback("mesen") → old bytes restored, state sha A, previous holds B */ }
@Test func rollbackWithoutPreviousThrows() { /* → .nothingToRollBack("bsnes") */ }
@Test func reappliesConfigAfterUpdate() async throws { /* report.config != nil; paths.appliedManifest decodes == latest */ }
```

- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass, including the Phase 1 installer tests.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: staged updater with one-generation rollback"`

---

### Task 4: Self-update

**Files:**
- Create: `Sources/RetromacCore/Update/SelfUpdater.swift`
- Test: `Tests/RetromacCoreTests/SelfUpdaterTests.swift`

**Interfaces:**
- Consumes: `SelfEntry`, `Downloader`, `CommandRunner`, `SHA256File`, `Paths`, `UpdateError`
- Produces:
  - `enum SelfUpdater { static let bundleID = "petersoft.retromac"; static func stage(_ e: SelfEntry, in dir: URL, downloader: Downloader, runner: CommandRunner) async throws -> URL; static func swapScript(pid: Int32, staged: URL, target: URL, previous: URL) -> String }`
    - `stage`:
      - Download, then verify the sha (`checksumMismatch(id: "retromac", …)` on a mismatch).
      - Run `/usr/bin/ditto -x -k <zip> <dir>/x` and locate `retromac.app`.
      - Throw `.badSelfBundle(reason)` if the `CFBundleIdentifier` isn't `bundleID` or the `CFBundleShortVersionString` isn't `e.version`.
    - `swapScript` is POSIX `sh`. Every path is single-quoted, with each `'` escaped as `'\''`.

      Exact output for pid 42, staged `/t/x/retromac.app`, target `/Applications/retromac.app`, previous `/Users/m/retromac/previous/retromac.app`:
      ```
      while kill -0 42 2>/dev/null; do sleep 0.2; done
      rm -rf '/Users/m/retromac/previous/retromac.app'
      mv '/Applications/retromac.app' '/Users/m/retromac/previous/retromac.app' || exit 1
      if ! mv '/t/x/retromac.app' '/Applications/retromac.app'; then mv '/Users/m/retromac/previous/retromac.app' '/Applications/retromac.app'; exit 1; fi
      open '/Applications/retromac.app'
      ```

- [ ] **Step 1: Write the failing tests:**
  - `swapScriptExact`: the output above, verbatim.
  - `swapScriptQuotesSpaces`: target `/Apps/My 'Stuff'/retromac.app` produces `'/Apps/My '\''Stuff'\''/retromac.app'`.
  - `stageVerifiesBundle`: build a fixture zip of a fake `retromac.app` with `ditto -c -k --keepParent`. Bundle ID `petersoft.retromac` and version `0.2.0` succeeds. Bundle ID `other` throws `.badSelfBundle`.
  - `stageRejectsBadSha`.
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: self-update staging and swap script"`

---

### Task 5: Upstream resolution and `check-upstream`

**Files:**
- Create: `Sources/RetromacCore/Update/UpstreamResolver.swift`
- Modify: `Sources/retromac-tool/main.swift`, `Sources/RetromacCore/Resources/manifest.json` (add `upstream` to every entry)
- Test: `Tests/RetromacCoreTests/UpstreamResolverTests.swift`, plus fixture files `Tests/RetromacCoreTests/Fixtures/github-release.json`, `gitlab-releases.json`, `libretro-stable.html` (trimmed real API responses captured once with `curl`)

**Interfaces:**
- Consumes: `Upstream`, `Manifest`, `SHA256File`, `Downloader`, `ManifestPolicy`
- Produces:
  - `struct Candidate: Equatable, Sendable { var version: String; var url: URL }`
  - `enum UpstreamResolver`:
    - `static func endpoint(_ u: Upstream) -> URL`:
      - github: `https://api.github.com/repos/<project>/releases/latest`
      - gitlab: `https://gitlab.com/api/v4/projects/<project, percent-encoded incl. "/">/releases`
      - libretro: `https://buildbot.libretro.com/stable/`
    - `static func resolve(_ u: Upstream, body: Data) -> Candidate?`:
      - github: `tag_name` (leading `v` stripped), first asset whose name matches the regex.
      - gitlab: first release, `assets.links[]` by name regex.
      - libretro: the highest `SemVer` among `href="<x.y.z>/"` directory links, with `{version}` substituted into the template.
  - `retromac-tool check-upstream [--write]`:
    - For each entry with `upstream`, fetch the endpoint and resolve a candidate.
    - If the candidate version differs from the entry's version, download it, compute its sha, and update `version`, `url`, and `sha256`. License and arch are untouched; a human verifies those in the PR.
    - Print one line per entry: `same <id> <v>`, `bump <id> <old> -> <new>`, or `FAIL <id> <reason>`.
    - With `--write`: if anything changed, increment `manifestVersion` and rewrite `manifest.json` (`JSONEncoder`, `.prettyPrinted` and `.sortedKeys`, trailing newline).
    - Exit 1 if any line is `FAIL` or the written manifest has policy violations.
  - `retromac-tool release-manifest --version X --zip-url URL --sha SHA`: prints the bundled manifest with `retromac = SelfEntry(...)` set, in the same encoding.

- [ ] **Step 1: Write the failing tests:**
  - github, gitlab, and libretro resolution against the fixtures, asserting the exact `Candidate` for each.
  - `endpoint` for each kind. The gitlab project `es-de/emulationstation-de` encodes to `es-de%2Femulationstation-de`.
  - A libretro listing that includes a non-version `href="../"` link, which must be ignored.
- [ ] **Step 2: Run the tests.** Expected: FAIL.
- [ ] **Step 3: Implement. Add `upstream` to both app entries.** Cores get none, because their updates come from `.index-extended` at runtime.
  - RetroArch: `libretroStable`, template `https://buildbot.libretro.com/stable/{version}/apple/osx/universal/RetroArch_Metal.dmg`.
  - ES-DE: `gitlabRelease` on `es-de/emulationstation-de`, regex `^ES-DE_.*-arm64\.dmg$`. GitLab's asset `url` is the `/-/package_files/<id>/download` form that Phase 1 pinned.
- [ ] **Step 4: Run `swift test`, then `swift run retromac-tool check-upstream`.** Expected: tests pass. Every entry prints `same` or `bump`, and none print `FAIL`.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: upstream resolver and check-upstream/release-manifest commands"`

---

### Task 6: Release and upstream-bump workflows

**Files:**
- Modify: `scripts/bundle.sh`. If `RETROMAC_VERSION` is set, it runs `/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RETROMAC_VERSION"` on the bundled plist.
- Create: `.github/workflows/release.yml`, `.github/workflows/upstream-bump.yml`

**`release.yml`** runs on `push: tags: ['v*']`, on `macos-latest`, with `permissions: contents: write`:
1. checkout, then `swift test`.
2. `RETROMAC_VERSION=${GITHUB_REF_NAME#v} scripts/bundle.sh`
3. `ditto -c -k --keepParent build/retromac.app retromac.zip`
4. `SHA=$(shasum -a 256 retromac.zip | cut -d' ' -f1)`
5. `swift run retromac-tool release-manifest --version "${GITHUB_REF_NAME#v}" --zip-url "https://github.com/MikeP1723/retromac/releases/download/${GITHUB_REF_NAME}/retromac.zip" --sha "$SHA" > manifest.json`
6. `gh release create "$GITHUB_REF_NAME" retromac.zip manifest.json --generate-notes` (with `GH_TOKEN: ${{ github.token }}`)

**`upstream-bump.yml`** runs on `schedule: cron '0 14 * * 1'` and `workflow_dispatch`, on `macos-latest`, with `permissions: contents: write, pull-requests: write`:
1. checkout.
2. `swift run retromac-tool check-upstream --write | tee bump.txt`
3. If `git diff --quiet`, exit 0.
4. Run `swift test` and `swift run retromac-tool verify-manifest`. This must happen here, because PRs created with `GITHUB_TOKEN` don't trigger `ci.yml`.
5. Create branch `upstream-bump/$(date +%Y%m%d)`, commit, and push.
6. `gh pr create` with title `Upstream bump $(date +%F)`. The body is `bump.txt` followed by this checklist:
   - `- [ ] License unchanged for each bumped component (check upstream LICENSE/.info)`
   - `- [ ] Builds are arm64 or universal`
   - `- [ ] Release notes reviewed for config-format changes (bump minAppVersion if the renderer must change)`

- [ ] **Step 1: Write the bundle.sh change and both workflows.**
- [ ] **Step 1b: Ask Mike first,** because this is a repository settings change. With his OK, allow Actions to open PRs: `gh api -X PUT repos/MikeP1723/retromac/actions/permissions/workflow -f default_workflow_permissions=write -F can_approve_pull_request_reviews=false`, then `gh api repos/MikeP1723/retromac/actions/permissions/workflow` to confirm. Without this, `gh pr create` in the bump job fails with "GitHub Actions is not permitted to create or approve pull requests".
- [ ] **Step 2: Local check.** Run `RETROMAC_VERSION=0.9.9 scripts/bundle.sh && /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" build/retromac.app/Contents/Info.plist`. Expected: `0.9.9`. Running `codesign --verify --strict build/retromac.app` exits 0.
- [ ] **Step 3: Lint both workflows with `actionlint`** (`brew install actionlint` if missing; it's a dev tool only). Expected: no findings.
- [ ] **Step 4: Commit:** `git add -A && git commit -m "ci: release and weekly upstream-bump workflows"`

---

### Task 7: Update wizard UI

**Files:**
- Create: `Sources/retromac/Update/UpdateModel.swift`, `Sources/retromac/Update/UpdatesView.swift`
- Modify: `Sources/retromac/RetromacApp.swift` (⌘U command, launch check), `Sources/retromac/WizardModel.swift` (expose shared `paths`, `profile`)

**Interfaces:**
- Consumes: `ReleaseClient`, `UpdatePlanner`, `Updater`, `SelfUpdater`, `InstallState`, `Manifest.bundled()`, `Paths.appliedManifest`, `RunningApps`, `DisplayRules.bundled()`, `BackupStore`
- Produces: `@Observable @MainActor final class UpdateModel`:
  - `func check(force: Bool) async`. It skips the check if `!force` and less than 24h have passed since `UserDefaults` `lastUpdateCheck`. Otherwise it loads `applied` (from `paths.appliedManifest`, falling back to `Manifest.bundled()`), calls `ReleaseClient.latest()` and `ReleaseClient.coreIndex()`, and runs `UpdatePlanner.plan(…, coreIndex:, appVersion: Bundle.main CFBundleShortVersionString)`. If the index fetch fails, it logs the error and passes `nil`, so app updates still show.
  - `var plan: UpdatePlan?`, `var selected: Set<String>`, `var adopt: Set<String>`, `var log: [String]`, `var error: String?`
  - `func applySelected() async`
  - `func updateSelf() async`. It stages, launches `/bin/sh -c <swapScript>` via `Process` (not waited on), then calls `NSApp.terminate(nil)`.
  - `func revert(_ id: String)`

**UpdatesView behavior:**
- A banner in the main window when `plan` has anything to offer: "Updates available". Clicking it opens the sheet. ⌘U runs `check(force: true)` and opens the sheet.
- **Self-update row first:** "retromac <current> → <new>", with an **Update & Relaunch** button.
- When `blockedByMinAppVersion` is set: "This update needs retromac <v> or newer. Update retromac first." Component rows are hidden.
- **Component rows:** a checkbox, `id`, and `installed → available`.
  - Managed rows start checked.
  - Unmanaged rows start unchecked and disabled, with an **Adopt** toggle and the note "Replaces your existing copy; the old one is kept and can be reverted." Adopting enables the checkbox.
  - Warnings: a red "License changed from X to Y" when `previousLicense` is set, and an orange "Needs Rosetta" when `requiresRosetta` is set.
- An **Update Selected** button, which streams `log`. On `UpdateError.appRunning` it shows "Quit <app> and try again".
- An **Installed** section lists components with a previous entry, each with a **Revert** button.
- Errors from `UpdateError.policy` show "The latest release failed safety checks and was ignored" plus the violation list.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run `swift build && swift test`.** Expected: success.
- [ ] **Step 3: Manual check against a local fake release.** Add a hidden `RETROMAC_RELEASE_FIXTURES=<dir>` environment override, honored only in `#if DEBUG` builds. It swaps the downloader for one that serves `<dir>/<url host>/<url path>` for any https URL, so the code paths stay the same as production.
  - Build a fixture release whose manifest bumps one pinned test entry, plus a fixture `.index-extended` with a changed CRC for one installed core.
  - Run `RETROMAC_RELEASE_FIXTURES=<scratchpad>/rm-release swift run retromac`.
  - Press ⌘U. Expected: the sheet lists the bumped core, Update Selected swaps it, and Revert restores it. Confirm the core file sha before and after with `shasum`.
- [ ] **Step 4: Commit:** `git add -A && git commit -m "feat: update wizard UI"`

---

### Task 8: End-to-end with a real release

Creating the GitHub repo, pushing, and tagging are outward-facing. **Confirm each with Mike before doing it.**

- [ ] **Step 1: Confirm CI is green on `main`** (`gh run list --branch main --limit 1`). The repo `MikeP1723/retromac` already exists; the remote is `git@github.com:MikeP1723/retromac.git`.
- [ ] **Step 2: Tag `v0.1.0` and push the tag** (after confirming). Expected: `release.yml` publishes `retromac.zip` and `manifest.json`. Run `gh release view v0.1.0 --json assets -q '.assets[].name'` and confirm both names.
- [ ] **Step 3: Install the `v0.1.0` zip into `/Applications` and run it.** ⌘U should report "up to date".
- [ ] **Step 4: Trigger `upstream-bump.yml` via `gh workflow run upstream-bump.yml`.** Expected: either no diff or a PR with the checklist. Review and merge only with Mike's go-ahead.
- [ ] **Step 5: Bump to `v0.1.1` and tag it** (after confirming). Expected: the installed `v0.1.0` offers retromac 0.1.1. Update & Relaunch replaces the app and relaunches, the About window shows 0.1.1, and `~/retromac/previous/retromac.app` exists.
- [ ] **Step 6: Report the results to Mike with command output.**
