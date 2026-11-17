# Switch through Ryubing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Switch games launch from ES-DE in a Ryubing that the user installed, after a guided, clearly-labelled-advanced setup in retromac.

**Architecture:**
- **Core logic in RetromacCore, all of it tested.** That covers detecting Ryubing and its config, a `Config.json` merge that refuses unknown versions, a `RyubingRenderer`, and an ES-DE `switch` entry gated on a single `Ryubing.isLive` predicate.
- **The app layer adds three things:**
  - Switch in the Systems step, with the warning
  - a three-step setup card
  - a "Done" action that re-applies

**Tech Stack:** Swift 6 SwiftPM, Swift Testing, Foundation `JSONSerialization`; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-15-switch-ryubing-design.md`. Read it, including "Spike results".

## Global Constraints

- **Keys and firmware.** retromac never downloads Ryubing, and never reads, writes, hashes, copies or **names** key or firmware files. That covers code, copy, comments and tests. Nothing under Ryubing's `system/` folder is ever touched.
- **Location.** Ryubing is `/Applications/Ryujinx.app` and its executable is `Contents/MacOS/Ryujinx`. Its config is `~/Library/Application Support/Ryujinx/Config.json`.
- **Known config versions:** `[70]`. For any other version, a missing file or unparseable JSON, retromac writes nothing and Switch stays out of ES-DE.
- **Owned keys, and only these:**
  - `show_confirm_exit = false`
  - `update_checker_type = "Off"`
  - `game_dirs`: add `<library>/switch`, and drop retromac's previously recorded entry if it's different. Never drop any other entry.
  - Never write `input_config`.
- **ES-DE command:** `%EMULATOR_RYUJINX% --fullscreen --docked-mode --hide-updates %ROM%`, label `Ryubing`. Extensions: `nca nro nso nsp xci`, each also in upper case. Full name: `Nintendo Switch`.
- **Switch is live** only when four conditions hold:
  - `.switch` is selected
  - the app exists
  - the user clicked Done (`switchSetup.confirmed`)
  - the config's version is known
- **Ryujinx.app blocks Apply only when `.switch` is selected.**
- **Fixed copy** (from the spec):
  - **Systems warning:** "For advanced users. Needs Ryubing, which you install yourself, and keys and firmware from your own Switch, set up inside Ryubing. retromac can't do those steps for you."
  - **Step 1:** "Move Ryujinx.app to Applications. The first time you open it, macOS blocks it; allow it in System Settings › Privacy & Security › Open Anyway."
  - **Step 2:** "Ryubing will say 'Keys not found' until you add them. In Ryubing, use the File menu to install your keys and firmware, then set up your controller under Options › Settings › Input › Player 1. Quit Ryubing and click Done."
  - **Ready:** "Switch games now show in Play."
  - **No config:** "Open Ryubing once, then click Done again."
  - **Unknown version:** "Ryubing was updated; retromac can't set it up until retromac updates too."
  - **Open while Done:** "Quit Ryubing, then click Done."
- **Defaults.** Switch is never pre-selected. Older profiles decode with no Switch setup.

## Review Focus

1. **A user who never chose Switch but has Ryubing installed or open** gets no prompts, no `Config.json` writes and no Switch in ES-DE. *(Task 3, `nothingForRyubingUnlessSwitchIsChosen`; Task 4, `ryubingBlocksApplyOnlyForSwitch`)*
2. **Ryubing updates its config format, or the file is corrupt:** nothing is written and Switch leaves ES-DE. *(Task 2, `unknownVersionOrBadJSONWritesNothing`; Task 3, `switchLeavesESDEWhenConfigIsUnknown`)*
3. **The user has their own `game_dirs` and the library moves:** their entries stay, and retromac's old entry is swapped for the new one. *(Task 2, `gameDirsKeepTheirsAndSwapOurs`; Task 4, `appliedRecordsTheGameDir`)*
4. **A network library:** the Switch folder is never created on the share, and `game_dirs` points at the share. *(Task 3, `switchOnANetworkLibrary`)*
5. **Clicking Done while Ryubing is open:** the tick is kept, nothing is written, and the card says to quit Ryubing. *(Task 5: app layer, manual check in Task 6)*

---

### Task 1: Detecting Ryubing and recording the setup

**Files:**
- Create: `Sources/RetromacCore/Detect/Ryubing.swift`
- Modify:
  - `Sources/RetromacCore/Support/Paths.swift`
  - `Sources/RetromacCore/Model/Profile.swift`
- Test: `Tests/RetromacCoreTests/RyubingTests.swift`

**Interfaces:**
- **Produces, `Paths`:**
  - `init(home:applications:systemApplications: URL? = nil)`, where `systemApplications` defaults to `/Applications`
  - `var systemApplications: URL`
  - `var ryubingApp: URL` (`systemApplications/Ryujinx.app`)
  - `var ryubingExecutable: URL` (`…/Contents/MacOS/Ryujinx`)
  - `var ryubingConfig: URL` (`home/Library/Application Support/Ryujinx/Config.json`)
- **Produces, `Profile`:**
  - `public struct SwitchSetup: Codable, Equatable, Sendable { public var confirmed: Bool; public var gameDir: String? }`
  - `public var switchSetup: SwitchSetup?` on `Profile`
- **Produces, `Ryubing`:**
  - `public enum Ryubing { public enum Status: Equatable { case notInstalled, noConfig, unknownVersion, ready } }`
  - `static func status(paths: Paths) -> Status`
  - `static func isLive(_ p: Profile, paths: Paths) -> Bool`
  - `static let knownConfigVersions: Set<Int> = [70]`

- [ ] **Step 1: Write failing tests** in `RyubingTests.swift`. Use a temp home and a temp `systemApplications`.
  - **`ryubingStatusFollowsAppAndConfig`:**
    - no app → `.notInstalled`
    - app folder with the executable but no config → `.noConfig`
    - `{"version": 71}` → `.unknownVersion`
    - `not json` → `.unknownVersion`
    - `{"version": 70}` → `.ready`
  - **`switchIsLiveOnlyWhenChosenInstalledConfirmedAndKnown`:** with `.ready`, `isLive` is true only when `systems` contains `.switch` and `switchSetup?.confirmed == true`. Flipping each of the four conditions makes it false.
  - **`olderProfilesHaveNoSwitchSetup`:** a profile saved without the field decodes with `switchSetup == nil`, and the saved JSON doesn't contain `switchSetup`. Mirror `olderProfilesHaveNoNetworkLibrary`.
- [ ] **Step 2:** Run `swift test --filter "ryubingStatus|switchIsLive|olderProfilesHaveNoSwitchSetup"`. Expected: compile failure, because `Ryubing` isn't defined.
- [ ] **Step 3:** Implement the code above. "Installed" means the executable file exists. Version is read with `JSONSerialization`, using the top-level `version` as `Int`.
- [ ] **Step 4:** Re-run the filter. Expected: PASS. Then run `swift test`; expected: all pass.
- [ ] **Step 5:** Commit `feat: detect Ryubing and record the Switch setup`.

### Task 2: Merging into Ryubing's Config.json

**Files:**
- Create: `Sources/RetromacCore/Render/RyubingConfig.swift`
- Test: `Tests/RetromacCoreTests/RyubingConfigTests.swift`

**Interfaces:**
- **Consumes:** `Ryubing.knownConfigVersions`.
- **Produces:** `public enum RyubingConfig { static func merge(existing: String?, gameDir: String, replacing: String?) -> String? }`. It returns nil for these:
  - a nil input
  - unparseable JSON
  - a non-object top level
  - a version not in the known set

  Otherwise it returns the JSON with the owned keys applied. Every other key and value is kept.

- [ ] **Step 1: Write failing tests:**
  - **`ownedKeysAreSetAndOthersKept`:** input `{"version":70,"show_confirm_exit":true,"update_checker_type":"PromptAtStartup","game_dirs":[],"docked_mode":true,"input_config":[{"id":"0-x"}],"res_scale":1}`. Expect:
    - `show_confirm_exit == false`
    - `update_checker_type == "Off"`
    - `game_dirs == ["/lib/switch"]`
    - `docked_mode == true`, and `input_config` is unchanged
    - `res_scale == 1`, as an integer
  - **`gameDirsKeepTheirsAndSwapOurs`:** start `["/mine", "/old/switch"]`, `gameDir "/new/switch"`, `replacing "/old/switch"` → `["/mine", "/new/switch"]`. If `/new/switch` is already present it isn't duplicated. `replacing: nil` never removes anything.
  - **`unknownVersionOrBadJSONWritesNothing`:** each of these gives nil:
    - `nil`
    - `""`
    - `"[]"`
    - `{"version":71}`
    - `{"game_dirs":[]}` (no version)
  - **`mergeIsStable`:** merging the result again with the same arguments returns an equal string. That lets the Applier report the file as unchanged.
- [ ] **Step 2:** Run `swift test --filter RyubingConfig`. Expected: compile failure.
- [ ] **Step 3:** Implement with `JSONSerialization`. Write with `[.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]`, so the output is deterministic for `mergeIsStable`; Ryubing reads keys in any order. Keep `game_dirs` order, and append ours at the end.
- [ ] **Step 4:** Re-run the filter, then `swift test`. Expected: all pass.
- [ ] **Step 5:** Commit `feat: merge retromac's keys into Ryubing's Config.json`.

### Task 3: Rendering: ES-DE entry and config file

**Files:**
- Create: `Sources/RetromacCore/Render/RyubingRenderer.swift`
- Modify:
  - `Sources/RetromacCore/Render/ProfileRenderer.swift`: the `RenderedFile.Kind`, `render`, and the `esdeSystems` gate
  - `Sources/RetromacCore/Render/ESDESystems.swift`
  - `Sources/RetromacCore/Apply/Applier.swift`
- Test: `Tests/RetromacCoreTests/RyubingRendererTests.swift`

**Interfaces:**
- **Consumes:** Task 1's `Ryubing.isLive` and `Paths.ryubingConfig`/`ryubingExecutable`; Task 2's `RyubingConfig.merge`.
- **Produces:**
  - `RenderedFile.Kind.ryubingConfig(gameDir: String, replacing: String?)`. The Applier calls `RyubingConfig.merge(existing:gameDir:replacing:)`, and a nil result means unchanged: nothing is written and nothing backed up.
  - `public enum RyubingRenderer { static func files(_ p: Profile, paths: Paths) -> [RenderedFile] }`. It returns `[]` unless `isLive`. Otherwise it returns one file at `paths.ryubingConfig` with `gameDir = libraryRoot/switch` and `replacing = p.switchSetup?.gameDir`.
  - `ESDESystems` changes:
    - an `info[.switch]` entry per Global Constraints
    - `xml(for:)` emits `.switch` with label `Ryubing` and `static let ryubingCommand` when `.switch` is in the set (it has no manifest entry)
    - `isOurs` recognises `ryubingCommand`
    - `emulatorApps` gains `"Ryujinx.app"`
    - `findRules(paths:)` gains a `RYUJINX` emulator at `paths.ryubingExecutable`
  - `ProfileRenderer.esdeSystems` drops `.switch` unless `Ryubing.isLive`.

- [ ] **Step 1: Write failing tests:**
  - **`nothingForRyubingUnlessSwitchIsChosen`:** Ryubing is ready, but the profile has no `.switch`. Expect no file at `ryubingConfig` and no `<name>switch</name>` in the esdeSystems XML.
  - **`liveSwitchRendersConfigAndESDEEntry`:** live. Expect:
    - a `.ryubingConfig(gameDir: "<lib>/switch", replacing: nil)` file
    - XML containing `<name>switch</name>` and the exact command `%EMULATOR_RYUJINX% --fullscreen --docked-mode --hide-updates %ROM%`
    - find rules containing `name="RYUJINX"` with `ryubingExecutable`'s path
  - **`switchLeavesESDEWhenConfigIsUnknown`:** the same profile with `{"version":71}` gives no switch entry and no config file. Also, merging the previously rendered XML with the new one removes the old `switch` entry, through `isOurs`.
  - **`switchOnANetworkLibrary`:** live, with `useNetworkLibrary(…, at: /Volumes/roms)`. Expect `gameDir == "/Volumes/roms/switch"` and no `.directory` under `/Volumes/roms`.
  - **`ryujinxIsAnEmulatorAppForConsoleMode`:** `ESDESystems.emulatorApps.contains("Ryujinx.app")`.
  - **Applier:** `applyWritesRyubingConfigOnlyWhenKnown` writes and backs up for version 70, and leaves a version-71 file byte-identical and out of `written`.
- [ ] **Step 2:** Run `swift test --filter "Ryubing|ryujinx|switchOn|switchLeaves|nothingForRyubing|liveSwitch"`. Expected: FAIL or compile failure.
- [ ] **Step 3:** Implement. Add `files += RyubingRenderer.files(p, paths: paths)` next to the other standalone renderers.
- [ ] **Step 4:** Re-run the filter, then `swift test`. Expected: all pass. That includes `droppedRetromacSystemsLeaveESDE` and `keepsUserSystemsAndCoreOverrideKeys`.
- [ ] **Step 5:** Commit `feat: render Ryubing's config and ES-DE's Switch system`.

### Task 4: Blocking apps and recording retromac's games folder

**Files:**
- Modify:
  - `Sources/RetromacCore/Apply/Applier.swift`
  - `Sources/RetromacCore/Render/RyubingRenderer.swift`
  - `Sources/retromac/WizardModel.swift`: both `Applier(` sites, and recording after a successful apply
  - `Sources/retromac-tool/main.swift`: both `Applier(` sites, and recording
- Test: `Tests/RetromacCoreTests/RyubingRendererTests.swift`

**Interfaces:**
- **Produces:**
  - `public static func blockingApps(manifest: Manifest, profile: Profile) -> [String]` on `Applier`. It returns `manifest.apps.map(\.appName)`, plus `"Ryujinx.app"` only when `profile.systems.contains(.switch)`.
  - `public static func applied(_ p: Profile, paths: Paths) -> Profile` on `RyubingRenderer`. When `isLive`, it returns `p` with `switchSetup.gameDir = libraryRoot/switch` path. Otherwise it returns `p` unchanged.
- **The callers:** each caller saves the profile after a successful apply when `applied` changed it. Callers are the app's `applyConfigs` and `installAndApply`, and the CLI's `apply`.

- [ ] **Step 1: Write failing tests:**
  - **`ryubingBlocksApplyOnlyForSwitch`:** without `.switch`, the result doesn't contain `"Ryujinx.app"`. With it, the result does. In both cases the manifest's apps come first.
  - **`appliedRecordsTheGameDir`:**
    - a live profile on `/lib1` gets `gameDir "/lib1/switch"`
    - the profile then changes to `/lib2`, and the next render's file has `replacing: "/lib1/switch"`
    - a profile that isn't live comes back equal to its input
- [ ] **Step 2:** Run `swift test --filter "ryubingBlocks|appliedRecords"`. Expected: compile failure.
- [ ] **Step 3:** Implement, and switch the four `Applier(` call sites (two in `WizardModel`, two in the CLI) to `Applier.blockingApps(manifest:profile:)`. Leave `UpdateModel` alone: updates never touch Ryubing's files (see the spec's Running apps).
- [ ] **Step 4:** Run `swift test`. Expected: all pass. Also `swift build`, to cover the app and CLI targets.
- [ ] **Step 5:** Commit `feat: Ryubing blocks Apply only for Switch; remember retromac's games folder`.

### Task 5: Switch in the Systems step, and the setup card (app)

**Files:**
- Create: `Sources/retromac/Views/SwitchSetupCard.swift`
- Modify:
  - `Sources/retromac/Views/SystemsStep.swift`
  - `Sources/retromac/WizardModel.swift`
  - `Sources/retromac/GamesModel.swift`: `installable` includes `.switch`
  - `Sources/RetromacCore/Detect/Ryubing.swift`: the copy constants
- Test: none. There's no app test target, so Task 6 checks this by hand.

**Interfaces:**
- **Consumes:** `Ryubing.status`/`isLive`, `Profile.switchSetup`, `Applier.blockingApps`, and `WizardModel.applyConfigs`.
- **Produces:**
  - The copy constants on `Ryubing`: `warning`, `installStep`, `setupStep`, `ready`, `noConfig`, `unknownVersion`, `quitFirst`, verbatim from Global Constraints.
  - `WizardModel.confirmSwitchSetup() -> String?`:
    1. Sets `switchSetup.confirmed = true` and saves the profile.
    2. Runs `applyConfigs()`.
    3. Returns `nil` on success, `Ryubing.quitFirst` on `ApplyError.appRunning("Ryujinx.app")`, or the error's description otherwise.

    The tick stays saved in every case.

- [ ] **Step 1: Systems step.** Show `.switch` after the manifest's `installableSystems`, with `Ryubing.warning` as an orange caption, never pre-selected. While `.switch` is selected, show `SwitchSetupCard` under its row.
- [ ] **Step 2: The card.** Its steps:
  1. **Install:** a ✓ when `status != .notInstalled`; otherwise a "Get Ryubing" link to `https://ryubing.org` and `installStep`.
  2. **Set up:** enabled after step 1. It has "Open Ryubing" (`NSWorkspace.open(paths.ryubingApp)`), `setupStep`, and "Done", which calls `confirmSwitchSetup` and shows the returned message.
  3. **Ready:** shows `ready` when `isLive`, and `noConfig` or `unknownVersion` when confirmed but the status says so.

  Re-check status on appear and on `NSApplication.didBecomeActiveNotification`.
- [ ] **Step 3:** Make `GamesModel.installable` include `.switch`, so Switch imports don't say "arrives in a later update".
- [ ] **Step 4:** Run `swift build` and `swift test`. Expected: the build succeeds and all tests pass.
- [ ] **Step 5:** Commit `feat: guided Switch setup in the Systems step`.

### Task 6: Hands-on check on Mike's Mac

Installing Ryubing to `/Applications` touches Mike's machine: **confirm with Mike before Step 2.**

- [ ] **Step 1:** Run `scripts/bundle.sh` and install as in earlier phases.
- [ ] **Step 2:** Install Ryubing 1.3.3 to `/Applications`, either from a **browser** download, to see the Gatekeeper prompt, or Mike does it.
- [ ] **Step 3:** In the Systems step:
  - Switch is unticked, with the warning.
  - Ticking it shows the card, and step 1 ticks itself.
  - "Open Ryubing" opens it, showing "Keys not found" as described.
  - Done with Ryubing open shows "Quit Ryubing, then click Done."
  - After quitting, Done shows Ready.
  - `Config.json` has `show_confirm_exit: false`, `update_checker_type: "Off"`, and `game_dirs` containing `<library>/switch`, with a backup in `backups/`.
  - `es_systems.xml` has the switch entry.
  - Nothing under Ryubing's `system/` folder changed: compare the folder listing's mtimes before and after; don't read any contents.
- [ ] **Step 4:** Untick Switch and apply. ES-DE's switch entry is gone, and `Config.json` is unchanged from Step 3.
- [ ] **Step 5:** Clean up with Mike's say-so: remove Ryubing and its data, as after the spike.
- [ ] **Step 6:** **Manual checks for the first tester with a Switch game:**
  - It launches from ES-DE full screen and docked, with no update prompt.
  - ⌘Q and Console Mode's quit combo return to ES-DE with no confirmation.

  Record them as pending in the ledger, and in the PR description.
