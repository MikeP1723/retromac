# retromac Encapsulation Phase Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** retromac becomes the only thing a user sees. Its data, the game library, RetroArch and ES-DE all live in `~/Library/Application Support/retromac`. The app opens to a home screen (Play, Add Games, Settings, Check for Updates), and existing installs are migrated once, automatically.

**Architecture:**
- **One root.** `Paths` gets a single root, `~/Library/Application Support/retromac` (`Paths.root`). Everything retromac owns hangs off it: `Apps/` for RetroArch.app and ES-DE.app, `Library/` for games, `ES-DE/` for ES-DE's data, and retromac's own state.
- **ES-DE's data folder:** retromac launches ES-DE with `--home <root>`, so ES-DE keeps its data in `<root>/ES-DE`. This was verified in the ES-DE 3.5 binary: `--home [path]  Directory to use as home path`.
- **Finding RetroArch:** retromac writes `<root>/ES-DE/custom_systems/es_find_rules.xml` so ES-DE finds RetroArch in `Apps/`. ES-DE 3.5 reads `custom_systems/es_find_rules.xml`.
- **Migration:** a `Migrator` moves the old layout (`~/retromac`, `~/ES-DE`, and retromac-managed apps in `/Applications`) to the new one with same-volume renames. It's idempotent. After it runs, configs are re-rendered.
- **App flow:** on first run the app shows the wizard; afterwards it shows a home screen.

**Tech Stack:** Swift 6, SwiftPM and SwiftUI, as before. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-13-retromac-design.md`, Resolved decision 8. Mike asked for this phase directly ("extremely user friendly for non technical users").

**Branch:** `encapsulation`, stacked on the unmerged `phase3a-importer` (3a and 3a-2). Merging needs Mike's OK, as before.

## Decisions made in this plan (Claude's calls)

- **The library location is fixed** at `<root>/Library`, and the wizard's **Library step is removed**. Non-technical users never choose a folder; **Show Games in Finder** is the way in. `Profile.libraryRoot` stays in the file format for compatibility, but the migration and new profiles always set it to `<root>/Library`.
- **RetroArch's own data stays in `~/Library/Application Support/RetroArch`.** It's already hidden. Moving it would mean overriding a dozen RetroArch directory keys for no visible gain.
- **A RetroArch or ES-DE the user installed themselves** (`managed: false`, in `/Applications`) is **left alone**. retromac installs its own copy into `Apps/` the next time Install runs. The Phase 2 adopt flow no longer applies to new layouts, because `Paths.applications` is retromac's own folder.
- **Old config backups are kept and re-pointed.** In each snapshot, a top-level `ES-DE/` folder moves to `Library/Application Support/retromac/ES-DE/`. The `.retromac-created` entries starting with `ES-DE/` are rewritten the same way, so Restore never recreates `~/ES-DE`.

## Global Constraints

- All earlier phases' constraints still apply. The ones that matter most here: **user files are never deleted**, every config write is backed up, and nothing runs while RetroArch or ES-DE is running.
- **Layout:**

  | Path | What it holds |
  |---|---|
  | `<root>` | `~/Library/Application Support/retromac` |
  | `<root>/Apps/{RetroArch.app, ES-DE.app}` | The two emulator apps |
  | `<root>/Library/<system>/…` | Games |
  | `<root>/ES-DE/` | ES-DE's data (it's launched with `--home <root>`) |
  | `<root>/{profile.json, state.json, manifest.json, update-cache.json}` | retromac's own state |
  | `<root>/{backups, previous, dats}/` | Config backups, rollback copies and game databases |
- **Migration only moves.** It renames on the same volume, never copies and deletes. It never touches anything not created by retromac: an unmanaged app in `/Applications` stays, and `~/ES-DE` is only moved when `state.apps["esde"].managed == true`. It's idempotent, so re-running after a partial failure finishes the job.
- **After a successful migration,** `~/retromac` and `~/ES-DE` no longer exist, and `/Applications` contains no retromac-managed app. retromac.app itself stays wherever the user put it.
- **The home screen's Play button** launches `<root>/Apps/ES-DE.app` with the arguments `["--home", <root path>]`, using `NSWorkspace.openApplication(at:configuration:)`.

## Review Focus

1. **Migration while ES-DE or RetroArch is running.** Expected: it refuses before moving anything, and the app shows "Quit ES-DE to finish updating retromac." Test in Task 3.
2. **Migration interrupted half-way** (e.g. one app move fails). Expected: what already moved stays moved, and a relaunch finishes the rest. No item is ever lost or duplicated. Test in Task 3.
3. **A user who already had their own RetroArch, ES-DE or `~/ES-DE`.** Expected: all three are untouched. retromac installs its own copies under `<root>/Apps`. Test in Task 3.
4. **Restoring a config backup taken before migration.** Expected: it restores into the new ES-DE location and never recreates `~/ES-DE`. Test in Task 3.
5. **Paths with spaces** (`Application Support`) in ES-DE's find rules and launch arguments. Expected: they work unquoted inside the XML, and are passed as one argument. Tests in Tasks 2 and 5.

---

### Task 1: New layout in `Paths`

**Files:**
- Modify: `Sources/RetromacCore/Support/Paths.swift`, the tests that construct `Paths` with explicit `/Applications` assumptions, `Sources/retromac-tool/main.swift` (the `--applications` default)
- Test: `Tests/RetromacCoreTests/PathsTests.swift`

**Interfaces:**
- Produces:
  - `Paths(home:applications:)` keeps its signature. `applications` now defaults to **nil**, which means `<root>/Apps`.
  - `root` = `home/Library/Application Support/retromac`, and `retromacRoot` becomes an alias of `root` so existing callers compile.
  - `esdeHome` = `root`, the value passed as `--home`. `esdeRoot` = `root/ES-DE`. `esdeSettings` and `esdeCustomSystems` move under `esdeRoot`.
  - New: `esdeFindRules` = `esdeRoot/custom_systems/es_find_rules.xml`, and `retroarchExecutable` = `applications/RetroArch.app/Contents/MacOS/RetroArch`.
  - `struct LegacyPaths: Sendable { init(home: URL, applications: URL = URL(filePath: "/Applications")); root (home/retromac); esde (home/ES-DE); applications }`

- [ ] **Step 1: Write the failing tests.**
  - `pathsResolveUnderApplicationSupport`: `root`, `defaultLibraryRoot`, `applications`, `esdeSettings` and `esdeFindRules` resolve to the exact strings under `/tmp/h/Library/Application Support/retromac/…`.
  - `explicitApplicationsStillWins`: tests that pass `applications:` keep working.
  - `legacyPaths`: `LegacyPaths` resolves to `/tmp/h/retromac`, `/tmp/h/ES-DE` and `/Applications`.
  - Update `pathsResolveUnderHome` to match.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Change the CLI's `--applications` default to `nil`.
- [ ] **Step 4: Run `swift test`.** Expected: all pass. Fix any test that hard-coded `~/ES-DE` or `~/retromac` by switching it to `Paths`.
- [ ] **Step 5: Commit:** `feat: one Application Support root for everything retromac owns`

---

### Task 2: ES-DE find rules and launch

**Files:**
- Modify: `Sources/RetromacCore/Render/ProfileRenderer.swift`, `Sources/RetromacCore/Render/ESDESystems.swift`
- Create: `Sources/RetromacCore/Render/ESDELauncher.swift`
- Test: `Tests/RetromacCoreTests/ESDELaunchTests.swift`

**Interfaces:**
- Produces:
  - `enum ESDESystems { static func findRules(retroarch: URL, cores: URL) -> String }`. It's a `<ruleList>` with `<emulator name="RETROARCH"><rule type="staticpath"><entry>{retroarch path}</entry></rule></emulator>` and `<core name="RETROARCH"><rule type="corepath"><entry>{cores path}</entry></rule></core>`. Paths are XML-escaped, never quoted.
  - The renderer adds `RenderedFile(url: paths.esdeFindRules, kind: .whole(findRules(...)))`. retromac owns this file because it lives under retromac's own ES-DE home.
  - `enum ESDELauncher { static func arguments(paths: Paths) -> [String] }`, returning `["--home", paths.esdeHome.path]`.

- [ ] **Step 1: Write the failing tests.**
  - `findRulesPointAtEncapsulatedRetroArch`: the content contains `<entry>/tmp/my home/Library/Application Support/retromac/Apps/RetroArch.app/Contents/MacOS/RetroArch</entry>` and parses with `XMLDocument`.
  - `rendererWritesFindRules`.
  - `launchArgumentsAreOneHomeArgument`: with home `/tmp/my home` → `["--home", "/tmp/my home/Library/Application Support/retromac"]`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Live check in the scratchpad.** Copy `/Applications/ES-DE.app` into `<scratch>/Apps/`. Launch it with `open -n <scratch>/Apps/ES-DE.app --args --home <scratch>/home`, quit it after 5 seconds, and check that `<scratch>/home/ES-DE/` was created and `~/ES-DE` was not modified (compare its mtime before and after). Record the result in the ledger.
- [ ] **Step 6: Commit:** `feat: ES-DE finds the encapsulated RetroArch and keeps its data under retromac`

---

### Task 3: Migrator

**Files:**
- Create: `Sources/RetromacCore/Support/Migrator.swift`
- Modify: `Sources/RetromacCore/Install/Installer.swift` (adds `InstallState.layoutVersion: Int?`)
- Test: `Tests/RetromacCoreTests/MigratorTests.swift`

**Interfaces:**
- Produces:
  - `struct MigrationReport: Equatable, Sendable { var moved: [String]; var leftAlone: [String] }`
  - `enum MigrationError: Error, Equatable { case appRunning(String); case moveFailed(String) }`
  - `struct Migrator { init(paths: Paths, legacy: LegacyPaths, isRunning: @escaping @Sendable (String) -> Bool); var isNeeded: Bool; func run() throws -> MigrationReport }`
  - `isNeeded` is true when `legacy.root` exists, or when the state has `layoutVersion != 2` and a managed app exists in `legacy.applications`.

**`run` steps, in order:**
1. If `RetroArch.app` or `ES-DE.app` is running, throw `.appRunning`.
2. Create `paths.root`.
3. **Merge-move `legacy.root/*` into `paths.root`:**
   - A file or folder missing at the destination is renamed into place.
   - A folder that exists at both is merged recursively.
   - A file that exists at both is left in place and listed in `leftAlone` (the newer layout wins).
   - Afterwards, remove `legacy.root` only if it's empty.
4. **Move managed apps.** For each `state.apps[id]` with `managed == true`, rename `legacy.applications/<appName>` to `paths.applications/<appName>` when the source exists and the destination doesn't. Unmanaged apps are listed in `leftAlone`. The app name comes from the bundled manifest.
5. **Move ES-DE's data.** If `state.apps["esde"]?.managed == true` and `legacy.esde` exists, merge-move it into `paths.esdeRoot`.
6. **Re-point backups.** In every snapshot under `paths.backups`, move `ES-DE/` to `Library/Application Support/retromac/ES-DE/`, and rewrite `.retromac-created` lines with the prefix `ES-DE/` the same way.
7. **Fix the profile.** If `profile.libraryRoot` equals `legacy.root/Library`, set it to `paths.defaultLibraryRoot`.
8. **Mark the layout.** Set `state.layoutVersion = 2` and save. This happens last, so an interrupted run is detected as still needed.

Any rename error throws `.moveFailed("<item>: <error>")` right away. Everything already moved stays moved, and the next `run()` continues.

- [ ] **Step 1: Write the failing tests.** Each builds a legacy layout in a temp home with a temp `applications` folder.
  - `migratesFullLegacyInstall`: `~/retromac` has `profile.json` (libraryRoot = legacy Library), `state.json` (retroarch and esde managed), `Library/nes/a.nes`, `backups/<snap>/ES-DE/settings/es_settings.xml` plus a `.retromac-created` file with `ES-DE/custom_systems/es_systems.xml`, and `previous/x.dylib`. Also `~/ES-DE/gamelists/nes/gamelist.xml`, and `Apps/RetroArch.app` plus `ES-DE.app` in the legacy applications folder. After `run()`:
    - everything is under the new root
    - `~/retromac`, `~/ES-DE` and the legacy apps are gone
    - the profile's libraryRoot is the new Library
    - `layoutVersion == 2`
    - the snapshot's ES-DE folder is re-pointed and its created-list is rewritten
    - `isNeeded == false`
  - `refusesWhileESDERunning`: throws `.appRunning("ES-DE.app")`, and nothing has moved.
  - `resumesAfterPartialFailure`: pre-create a regular file at `paths.applications` so the app move fails → throws `.moveFailed`. The `~/retromac` contents are already moved. Remove the blocker and run again → it completes.
  - `leavesUserOwnedThingsAlone`: an unmanaged RetroArch in legacy applications, and esde not managed while `~/ES-DE` exists → both untouched, both listed in `leftAlone`.
  - `conflictingFileKeepsNewer`: `profile.json` exists in both places → the new one is kept, the legacy one stays, and `~/retromac` is not removed.
  - `restoreAfterMigrationUsesNewLocation`: run `BackupStore.restore` on a migrated snapshot → it writes under the new root, and `~/ES-DE` is not recreated.
  - `nothingToMigrateIsNoOp`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `feat: one-time migration into Application Support`

---

### Task 4: CLI support

**Files:**
- Modify: `Sources/retromac-tool/main.swift`

**Interfaces:**
- Produces:
  - `retromac-tool migrate [--home DIR] [--legacy-applications DIR] [--dry-run]`.
    - It prints `move <item>` and `leave <item>` lines.
    - With `--dry-run`, it reports what would move without moving anything. `Migrator` gains `func plan() -> MigrationReport`, which shares the walk with `run()`.
    - Without `--dry-run`, it runs, then re-renders and applies with the migrated profile.
  - `retromac-tool play [--home DIR]` launches ES-DE with `ESDELauncher.arguments`.

- [ ] **Step 1: Write a failing test for `Migrator.plan()`.** The `migratesFullLegacyInstall` fixture → `plan()` lists the same items `run()` moves, and nothing moves.
- [ ] **Step 2: Implement `plan()` and both commands.**
- [ ] **Step 3: Run `swift test`, then a scratchpad smoke test.** Build a fake legacy home in the scratchpad, then run `migrate --dry-run`, then `migrate`. Expected: the dry run lists the items and the real run moves them.
- [ ] **Step 4: Commit:** `feat: migrate and play commands`

---

### Task 5: Home screen, first-run routing and migration screen

**Files:**
- Create: `Sources/retromac/Views/HomeView.swift`, `Sources/retromac/Views/MigrationView.swift`
- Modify: `Sources/retromac/RetromacApp.swift`, `Sources/retromac/WizardModel.swift` (remove `.library`; the steps become display, systems, controllers, apply), `Sources/retromac/Views/LibraryStep.swift` (deleted), `Sources/retromac/GamesModel.swift` (the library root is always `paths.defaultLibraryRoot`)

**Interfaces:**
- Produces:
  - `enum Screen { case migrating, wizard, home, games }` on a new `@Observable AppModel`, which owns `WizardModel`, `UpdateModel` and `GamesModel`.
  - **Routing at launch:**
    - `Migrator.isNeeded` → `.migrating`.
    - Otherwise, if `profile.json` exists and `state.apps["esde"] != nil` → `.home`.
    - Otherwise → `.wizard`.
  - **MigrationView:** "Updating retromac's files…" while it runs. On `.appRunning`, it shows "Quit ES-DE to finish updating retromac." with a **Try Again** button. On `.moveFailed`, it shows the reason with **Try Again**. On success it applies the configs, then goes to `.home`.
  - **HomeView**, a centered column:
    - **Play**: a large, prominent button. Disabled with a tooltip until ES-DE is installed.
    - **Add Games**: goes to `.games`, the existing `GamesStep`, with a **Back** button.
    - **Settings**: goes to `.wizard`, starting at Display.
    - **Check for Updates**: opens the existing sheet.
    - A footer: "<N> games · <size>" from a background scan of `Library/`, plus a **Show Games in Finder** link (`NSWorkspace.activateFileViewerSelecting`).
    - The Updates-available banner, as now.
  - **Wizard:** finishing Install & Apply goes to `.home`. "Done" becomes **Continue** on the last step.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run `swift build && swift test`, then `scripts/bundle.sh` and `codesign --verify --strict build/retromac.app`.** Expected: success.
- [ ] **Step 3: Commit:** `feat: home screen, first-run routing and migration screen`

---

### Task 6: End-to-end on Mike's Mac

These steps move Mike's real install. **Confirm with Mike before Step 2.**

- [ ] **Step 1: Snapshot the current state.** Record `ls ~/retromac ~/ES-DE`, `ls /Applications | grep -E 'RetroArch|ES-DE'`, `state.json`, and `shasum` of `~/retromac/Library/nes/*`.
- [ ] **Step 2: Mike quits ES-DE and RetroArch, then opens `build/retromac.app`.** Expected: the migration screen, then the home screen.
- [ ] **Step 3: Verify the result.**
  - `~/retromac` and `~/ES-DE` are gone.
  - `/Applications` has no RetroArch or ES-DE. It may still have retromac.app.
  - `~/Library/Application Support/retromac` has `Apps/`, `Library/` (with the same shas) and `ES-DE/`.
  - ES-DE's `es_settings.xml` ROMDirectory points to the new Library.
- [ ] **Step 4: Mike clicks Play.** Expected: ES-DE opens full screen, lists his NES game, and launches it in RetroArch.
- [ ] **Step 5: Mike runs Add Games and Update Game Databases from the home screen.** This is the deferred 3a-2 hands-on test: SMB3 → `Super Mario Bros 3 (USA) (PRG 1) [Hack]`, or already present.
- [ ] **Step 6: Report the results to Mike.**
