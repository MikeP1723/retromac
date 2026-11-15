# Phase 6: Rosetta tier and PlayStation 2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PlayStation 2 installable and playable with the official PCSX2 (x86_64, under Rosetta), with retromac installing Rosetta when the user picks PS2, recognizing PS2 BIOS files, configuring PCSX2 for a controller-only full-screen user, and optionally shrinking PS2 discs to CHD.

**Architecture:** Builds on Phase 5 (branch `phase5-standalones`): manifest apps with `systems`, the INI merge renderer, internal-scale display rules, and the Applier's running-app refusal. A new `Rosetta` helper checks for, installs (one admin prompt), and gates on Rosetta; Rosetta-tier systems disappear on a macOS that no longer has it. The installer learns `.tar.xz` archives and installing an app under a stable name. PCSX2's settings go through the existing `.iniKeys` merge. PS2 BIOS files are recognized structurally (PCSX2's own check), not by hash.

**Tech Stack:** Swift 6 SwiftPM, macOS 14+ arm64, SwiftUI, Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-13-retromac-design.md`: Platform reality check (Rosetta tier; PS2 is "Rosetta-tier, official PCSX2 (Mike's decision)"), the Systems table (PS2: PCSX2, GPLv3+, .chd, BIOS required), Librarian steps 5–6, Phasing 5–6.

**Scope note:** the original Phase 6 also held Cemu (Wii U) and Ryubing (Switch, detect-only). Both are split into a Plan 7, each for a reason found in recon on 2026-11-14:
- Cemu 2.6 binds controllers by SDL GUID, not index or name.
- Cemu's only macOS renderer is Vulkan, which runs through MoltenVK. That's what froze Beetle PSX HW's output in Phase 3b, so it needs a spike first.
- Ryubing's GitHub repo is gone and its Forgejo URL now redirects, so its current config schema has to be located first.

## Global Constraints

- Every new source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later`. Swift 6 strict concurrency, zero warnings in new code, no third-party Swift dependencies.
- Emulators are fetched from upstream at runtime, pinned by sha256, never vendored.
- No BIOS or commercial images in the repo or CI; PS2 BIOS tests use a synthetic file with a fake ROM directory.
- **PCSX2 pin** (downloaded and inspected 2026-11-14):

  | id | version | url | sha256 | license | arch | archive app | installed as |
  |---|---|---|---|---|---|---|---|
  | `pcsx2` | `2.8.2` | `https://github.com/PCSX2/pcsx2/releases/download/v2.8.2/pcsx2-v2.8.2-macos-Qt.tar.xz` | `3ed9eb40a33eae67134142c24255a079be444f0616ca29575a04a37981f7d426` | `GPL-3.0-or-later` (spec; GitHub reports GPL-3.0) | `x86_64`, `rosetta: true` (`lipo -archs` → `x86_64`) | `PCSX2-v2.8.2.app` | `PCSX2.app` |

  Upstream: `{ "kind": "githubRelease", "project": "PCSX2/pcsx2", "assetPattern": "^pcsx2-v[0-9.]+-macos-Qt\\.tar\\.xz$" }`. The archive's app name carries the version, so the manifest gives it per release (`archiveAppName`) and retromac always installs `PCSX2.app`.
- **Rosetta** (spec, verbatim):
  - The wizard installs it with `softwareupdate --install-rosetta` (admin) and shows "This system depends on Rosetta, which Apple is phasing out after macOS 27."
  - On a later macOS where Rosetta is gone, these systems are hidden instead of failing at launch.

  Checked on Mike's Mac (macOS 27.2): Rosetta is not installed, and `arch -x86_64 /usr/bin/true` fails with "Bad CPU type in executable".
- **PCSX2 facts** (from PCSX2 v2.8.2 source):
  - **Paths:** data lives in `~/Library/Application Support/PCSX2` (`QtHost.cpp` `MAC_DATA_DIR`) and settings in `inis/PCSX2.ini`.
  - **CLI:** `-batch`, `-nogui`, `-fullscreen` (`QtHost.cpp:2200–2268`).
  - **Settings** (`UI`, `GameList`, `Folders`, `Filenames`, `EmuCore/GS` sections): `UI/StartFullscreen`, `UI/ConfirmShutdown`, `UI/SetupWizardIncomplete`, `GameList/RecursivePaths`, `Folders/Bios`, `Filenames/BIOS`, `EmuCore/GS/Renderer` (Metal = `17`, `Config.h`), `EmuCore/GS/upscale_multiplier`.
  - **Pad bindings** are by SDL player index, never by name (`SDLInputSource.cpp` `ConvertKeyToString`): `SDL-0/FaceSouth`, `SDL-0/-LeftY`, `SDL-0/+LeftTrigger`, with combos joined by ` & `. Pad section `Pad1`, `Type = DualShock2`.
  - **BIOS check** (`BiosTools.cpp`): a file of 4–8 MiB (`MIN_BIOS_SIZE`/`MAX_BIOS_SIZE`) whose 16-byte ROM directory entries include one named `RESET`.
- **Coordination:**
  - **Console Mode (merged):** its exit combo quits `ESDESystems.emulatorApps`, which adding `pcsx2` to `ESDESystems.standalones` (Task 3) extends to `PCSX2.app`. Task 3's tests assert that.
  - **Phase 5:** must merge first, because this branch is cut from `phase5-standalones`.

## Review Focus

1. **The admin prompt for Rosetta is cancelled, or the Mac has no admin rights.** Expected: everything except PS2 still installs and applies; the log says why PS2 was skipped; PS2 stays selected so the next Install & Apply asks again. Test in Task 2 (installer gating) and Task 1 (cancel maps to `.declined`).
2. **PCSX2 opens its first-run setup wizard or a confirm-on-quit dialog** in front of a controller-only user. Expected: neither appears. Test in Task 4.
3. **PCSX2 starts with no PS2 BIOS.** Expected: the Systems step says the BIOS is missing before the user gets that far. Test in Task 5.
4. **A non-BIOS file of 4–8 MiB** (an N64 ROM, a homebrew image) is taken for a PS2 BIOS. Expected: only files with a `RESET` ROM directory entry match. Test in Task 5.
5. **Converting a PS2 disc to CHD loses the game** (wrong `chdman` mode, or deleting before verify). Expected: `createdvd`, verified before the `.iso` is deleted, same contract as Phase 3b. Test in Task 6.

---

### Task 1: Rosetta check, install and support window

**Files:**
- Create: `Sources/RetromacCore/Install/Rosetta.swift`
- Test: `Tests/RetromacCoreTests/RosettaTests.swift`

**Interfaces:**
- Produces:
  - `public enum RosettaInstall: Equatable, Sendable { case installed, declined, failed(String) }`.
  - `public struct Rosetta { init(runner: any CommandRunner) }`:
    - `isInstalled: Bool` runs `/usr/bin/arch -x86_64 /usr/bin/true`; exit 0 means installed.
    - `install() -> RosettaInstall` runs `/usr/bin/osascript -e 'do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with administrator privileges'`. The command is a fixed string with nothing interpolated. osascript's "User canceled." (error -128) maps to `.declined`.
    - `static func isSupported(osMajor: Int) -> Bool` is `osMajor <= 27`.
    - `static let warning = "This system depends on Rosetta, which Apple is phasing out after macOS 27."`

- [ ] **Step 1: Write the failing tests** with a fake runner:
  - `installedWhenX86Runs`, `notInstalledWhenX86Fails`.
  - `installRunsTheFixedAdminCommand`: asserts the exact argv.
  - `cancelledPromptIsDeclined`: the runner throws `commandFailed` with stderr containing `User canceled. (-128)`.
  - `otherFailureIsReported`.
  - `supportedThroughMacOS27`: 27 true, 28 false.
- [ ] **Step 2: Run them.** Expected: FAIL. **Step 3: Implement. Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: Rosetta check, install and support window`

---

### Task 2: Installer: tar.xz apps, stable app names, Rosetta gating

**Files:**
- Modify: `Sources/RetromacCore/Manifest/Manifest.swift`, `Sources/RetromacCore/Install/Installer.swift`, `Sources/RetromacCore/Resources/manifest.json`, `Sources/retromac/WizardModel.swift`, `Sources/retromac/Views/SystemsStep.swift`
- Test: `Tests/RetromacCoreTests/InstallerTests.swift`, `Tests/RetromacCoreTests/BundledManifestTests.swift`

**Interfaces:**
- Consumes: Task 1's `Rosetta`.
- Produces:
  - **Manifest:** `AppEntry.archiveAppName: String?`, the app's name inside the archive when it differs from `appName`. It defaults to `appName`.
  - **`stageApp` handles `.tar.xz`:** it extracts with `/usr/bin/tar -xJf <archive> -C <dir>`, whose bsdtar refuses `..` and absolute paths by default. It then finds `archiveAppName` the same way as zips and copies it to staging as `appName`.
  - **Rosetta gating:** `install(systems:)` skips an app with `rosetta: true` when `Rosetta(runner:).isInstalled` is false. It adds `"<id>: needs Rosetta"` to `report.warnings` and doesn't throw.
  - **Hiding on later macOS:** `Manifest.installableSystems(osMajor: Int) -> [SystemID]` drops systems whose only emulator needs Rosetta when `!Rosetta.isSupported(osMajor:)`. The existing `installableSystems` becomes `installableSystems(osMajor: ProcessInfo…majorVersion)`.
  - **App:**
    - `WizardModel.installAndApply` asks for Rosetta via `Rosetta.install()` before installing, when a selected system's app needs it and it's missing. It logs `Rosetta installed.`, or on `.declined` logs `PlayStation 2 needs Rosetta. Install & Apply again to be asked again.`, and carries on.
    - `SystemsStep` shows `Rosetta.warning` under any Rosetta-tier system.
- **`manifest.json`** gains the PCSX2 entry from Global Constraints, with `"systems": ["ps2"]` and `"archiveAppName": "PCSX2-v2.8.2.app"`.

- [ ] **Step 1: Write the failing tests:**
  - `installsAppFromTarXzUnderItsStableName`: the fixture is built with `tar -cJf` from `Fake-v1.app`, and the app is installed as `Fake.app`.
  - `rosettaAppSkippedWithoutRosetta`: a fake runner fails `arch`; the report has the warning and nothing is installed; other apps still install.
  - `rosettaAppInstalledWithRosetta`.
  - `rosettaSystemsHiddenAfterMacOS27`: with the bundled manifest, `installableSystems(osMajor: 28)` lacks `.ps2` and `installableSystems(osMajor: 27)` has it.
  - `bundledManifestIsCompliant` / `standalonesAreInstallable` updated to include `pcsx2` / `.ps2`. Ledger the update.
- [ ] **Step 2: Run them.** Expected: FAIL. **Step 3: Implement. Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: install PCSX2 under Rosetta, asking for Rosetta when needed`

---

### Task 3: ES-DE PS2 system and find rule

**Files:**
- Modify: `Sources/RetromacCore/Render/ESDESystems.swift`
- Test: `Tests/RetromacCoreTests/ESDELaunchTests.swift`

**Interfaces:**
- Consumes: Phase 5's `ESDESystems.standalones` and `findRules(paths:)`.
- Produces:
  - **System info:** `info[.ps2] = Info(fullname: "Sony PlayStation 2", extensions: ["iso", "chd"])`. Those are what the importer files plus Task 6's CHDs.
  - **Launcher:** `standalones["pcsx2"] = ("PCSX2", "PCSX2.app/Contents/MacOS/PCSX2", "PCSX2", "%EMULATOR_PCSX2% -batch -nogui -fullscreen %ROM%")`.

- [ ] **Step 1: Write the failing tests:**
  - `ps2LaunchesPcsx2`: the xml has `<name>ps2</name>`, the command and `.chd`.
  - `findRulesIncludePcsx2`: has `<emulator name="PCSX2">` with `…/Apps/PCSX2.app/Contents/MacOS/PCSX2`.
- [ ] **Step 2: Run.** Expected: FAIL. **Step 3: Implement. Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: PlayStation 2 in ES-DE`

---

### Task 4: PCSX2 settings and controller

**Files:**
- Create: `Sources/RetromacCore/Render/Pcsx2Renderer.swift`
- Modify: `Sources/RetromacCore/Render/ProfileRenderer.swift`, `Sources/RetromacCore/Support/Paths.swift`, `Sources/RetromacCore/Resources/display_rules.json`
- Test: `Tests/RetromacCoreTests/Pcsx2RendererTests.swift`, `Tests/RetromacCoreTests/DisplayTests.swift`

**Interfaces:**
- Consumes: Phase 5's `.iniKeys`, `internalScale(for:display:chip:)`; Task 5's `Paths.ps2Bios` (defined here, filled by Task 5).
- Produces:
  - `Paths.pcsx2Settings` = `~/Library/Application Support/PCSX2/inis/PCSX2.ini`.
  - `Paths.ps2Bios` = `retroarchSystem/pcsx2/bios`.
  - `display_rules.json`: `"ps2": {"nativeHeight": 448, "maxScale": 4}`.

When `ps2` is selected, one `.iniKeys` file:

| Section | Key | Value |
|---|---|---|
| `UI` | `SetupWizardIncomplete` | `false` |
| | `StartFullscreen` | `true` |
| | `ConfirmShutdown` | `false` |
| `GameList` | `RecursivePaths` | `<libraryRoot>/ps2` |
| `Folders` | `Bios` | `Paths.ps2Bios` |
| `Filenames` | `BIOS` | the first file name (sorted) in `Paths.ps2Bios` that `Ps2Bios.isBios` accepts; key omitted when there is none |
| `EmuCore/GS` | `Renderer` | `17` (Metal) |
| | `upscale_multiplier` | `internalScale(for: .ps2, …)` |
| `Pad1` | `Type` | `DualShock2` |
| | `Cross` / `Circle` / `Square` / `Triangle` | `SDL-0/FaceSouth` / `FaceEast` / `FaceWest` / `FaceNorth` |
| | `Select` / `Start` | `SDL-0/Back` / `SDL-0/Start` |
| | `L1` / `R1` | `SDL-0/LeftShoulder` / `SDL-0/RightShoulder` |
| | `L2` / `R2` | `SDL-0/+LeftTrigger` / `SDL-0/+RightTrigger` |
| | `L3` / `R3` | `SDL-0/LeftStick` / `SDL-0/RightStick` |
| | `Up` / `Down` / `Left` / `Right` | `SDL-0/DPadUp` / `DPadDown` / `DPadLeft` / `DPadRight` |
| | `LUp` / `LDown` / `LLeft` / `LRight` | `SDL-0/-LeftY` / `+LeftY` / `-LeftX` / `+LeftX` |
| | `RUp` / `RDown` / `RLeft` / `RRight` | `SDL-0/-RightY` / `+RightY` / `-RightX` / `+RightX` |
| `Hotkeys` | `ShutdownVM` | `SDL-0/Back & SDL-0/Start` (Select+Start, as RetroArch and Dolphin; with `-batch` PCSX2 then exits to ES-DE) |

Note: PCSX2 maps by SDL index, so this works with any pad, with no name table (unlike Dolphin).

- [ ] **Step 1: Write the failing tests:**
  - `pcsx2SettingsForPs2`: the table at 1440p (`upscale_multiplier` = `4`, since 1440/448 rounds up to 4) with `/tmp/h/Mike's "Games"` as the library root. Values are unquoted to end of line, as in Dolphin.
  - `pcsx2NeverShowsItsWizardOrQuitPrompt` (Review Focus 2): `SetupWizardIncomplete=false`, `ConfirmShutdown=false`.
  - `biosFileNameComesFromTheBiosFolder`: a synthetic BIOS in `ps2Bios` gives `Filenames/BIOS`; an empty folder leaves the key out.
  - `noPcsx2FileWithoutPs2`.
  - `userPcsx2SettingsSurviveReapply`.
  - `internalScaleForPs2`: 1440p → 4, 2160p → 4 (capped), and `"Apple M1"` at 2160p → 3.
- [ ] **Step 2: Run.** Expected: FAIL. **Step 3: Implement. Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: PCSX2 settings and controller`

---

### Task 5: PS2 BIOS recognition

**Files:**
- Create: `Sources/RetromacCore/Library/Ps2Bios.swift`
- Modify: `Sources/RetromacCore/Library/Importer.swift` (the BIOS branch), `Sources/retromac/Views/SystemsStep.swift`, `Sources/retromac/Views/LibraryView.swift` (row text)
- Test: `Tests/RetromacCoreTests/Ps2BiosTests.swift`

**Interfaces:**
- Produces:
  - `public enum Ps2Bios { static func isBios(_ url: URL) -> Bool }`. It's true when the file is 4 194 304–8 388 608 bytes and, scanning the first 1 MiB in 16-byte steps, some entry's first 10 bytes are `RESET` padded with NULs. This is PCSX2's `LoadBiosVersion` check, limited to the first MiB, where real ROM directories sit (around 0x2700).
  - **Importer:** when `BiosFile.match` fails, a file that passes `Ps2Bios.isBios` gets `ImportStatus.bios(.ps2, region: "")`. It's staged to `Paths.ps2Bios/<original file name>`, and an existing file of that name follows the Phase 3b rules (same bytes → duplicate, different → failed).
  - **Systems step caption for `ps2`:**
    - No BIOS: "Needs your PlayStation 2's BIOS file. Add it in Games like any game file."
    - BIOS present: "BIOS found."
    - `Rosetta.warning` appears under either.

- [ ] **Step 1: Write the failing tests:**
  - `syntheticPs2BiosIsRecognized`: 4 MiB of zeros with `RESET\0\0\0\0\0` at 0x2700.
  - `fourMegabyteNonBiosIsNot` (Review Focus 4): 4 MiB without the entry.
  - `smallFileIsNeverRead`: 512 KiB with `RESET` → false.
  - `ps2BiosImportedToItsFolder`: via the Importer with the synthetic file; it lands in `ps2Bios` and the status is `.bios(.ps2, …)`.
  - `ps2BiosCaption` (Review Focus 3): a helper used by the caption reports missing for an empty folder.
- [ ] **Step 2: Run.** Expected: FAIL. **Step 3: Implement. Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: recognize PlayStation 2 BIOS files`

---

### Task 6: Shrink PS2 discs to CHD

**Files:**
- Modify: `Sources/RetromacCore/Library/ChdTool.swift`
- Test: `Tests/RetromacCoreTests/ChdToolTests.swift`

**Interfaces:**
- Consumes: Phase 3b's `ChdTool` (`convert(cue:)`, `convertible(in:)`, `removeLeftovers`).
- Produces: `ChdTool.convert(iso:)`, which runs `chdman createdvd -i <iso> -o .retromac-<uuid>.chd`, then `chdman verify -i <tmp>`, then renames the temp file to `<stem>.chd` and deletes the `.iso`. Every failure path removes the temp file and keeps the `.iso`, the same contract as `convert(cue:)`. `convertible(in:)` also lists non-hidden `ps2/*.iso` files with no `.chd` beside them. The app's existing "Shrink disc games" button calls `convert(iso:)` for `.iso` items.

- [ ] **Step 1: Write the failing tests** with Phase 3b's `FakeChdman`:
  - `ps2IsoConvertsWithCreatedvd` (Review Focus 5): checks the argv and that the iso is gone.
  - `failedPs2ConversionKeepsTheIso`.
  - `convertibleListsPs2Isos`.
  - The gated `realChdmanRoundTrip` gains a DVD variant using a 2 MiB synthetic iso, run only when chdman is installed (it is on Mike's Mac).
- [ ] **Step 2: Run.** Expected: FAIL. **Step 3: Implement. Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: shrink PlayStation 2 discs to CHD`

---

### Task 7: End to end on Mike's Mac

These steps install Rosetta (an admin prompt) and PCSX2 on Mike's Mac. **Confirm with Mike before Step 2.**

- [ ] **Step 1:** `RETROMAC_VERSION=0.5.0 scripts/bundle.sh`; install as `/Applications/retromac.app`.
- [ ] **Step 2:** Settings › Systems: PlayStation 2 shows the Rosetta warning. Install & Apply. Expected:
  - macOS asks for an admin password once, and the log says `Rosetta installed.`.
  - `pcsx2` is installed, and `Apps/PCSX2.app` exists.
  - `arch -x86_64 /usr/bin/true` now exits 0.
  - `PCSX2.ini` carries the Task 4 values.
- [ ] **Step 3:** Add Mike's PS2 BIOS and a PS2 game. The BIOS lands in `RetroArch/system/pcsx2/bios`, the caption says found, and a re-Apply writes `Filenames/BIOS`. The game boots full screen from ES-DE with the Pro Controller, without PCSX2's setup wizard. Select+Start returns to ES-DE.
- [ ] **Step 4:** Shrink disc games converts the PS2 iso to CHD; it still boots.
- [ ] **Step 5:** Record results with command output in the ledger.
