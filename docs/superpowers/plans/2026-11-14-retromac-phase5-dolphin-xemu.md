# Phase 5: GameCube, Wii and Xbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make GameCube, Wii and original Xbox installable and playable from ES-DE with the standalone emulators Dolphin and xemu: downloaded from upstream, configured by retromac, launched full screen with a controller, with Xbox BIOS files recognized by the importer.

**Architecture:** The manifest's `apps` gain an optional `systems` list, so a standalone emulator is installed only when one of its systems is turned on, and `installableSystems` includes those systems. A new `assets` list carries data files that an emulator needs (xemu's blank hard disk image), which are installed once and never overwritten. The installer learns `.zip` apps (xemu ships a zip). ES-DE gets `gc`/`wii`/`xbox` systems that launch Dolphin or xemu through new find rules. Two new merge-style renderers write Dolphin's INI files and xemu's TOML, keeping every key retromac doesn't own, because both emulators rewrite their config on exit. Display rules gain a per-system internal resolution scale.

**Tech Stack:** Swift 6 SwiftPM, macOS 14+ arm64, SwiftUI, Swift Testing. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-13-retromac-design.md`: the Systems table, Platform reality check, Licensing, Display (3D-era scale), Controllers (Dolphin `GCPadNew.ini` / `WiimoteNew.ini`, xemu input), Librarian step 6 (Xbox BIOS) and Phasing item 5.

## Global Constraints

- Every new source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later`. Swift 6 strict concurrency, zero warnings in new code, no third-party Swift dependencies.
- Emulators and data files are fetched from upstream at runtime, pinned by sha256, never vendored or re-hosted.
- No BIOS, commercial images or real DATs in the repo or CI. BIOS tests inject a synthetic `BiosFile` table.
- Upstream pins (downloaded and hashed 2026-11-14):

  | id | version | url | sha256 | license | arch | appName / fileName |
  |---|---|---|---|---|---|---|
  | `dolphin` | `2609` | `https://dl.dolphin-emu.org/releases/2609/dolphin-2609-universal.dmg` | `b8910a6f8710cbe93b916f5b3867a46e67e49aa8272657d282d4accae359cd6b` | `GPL-2.0-or-later` (source SPDX headers) | `universal` | `Dolphin.app` |
  | `xemu` | `0.8.139` | `https://github.com/xemu-project/xemu/releases/download/v0.8.139/xemu-0.8.139-macos-universal.zip` | `9817aaa5e187a698416271a6ddc083a40d7ff5e09c3231cff32a692638c7427d` | `GPL-2.0-only` (QEMU `LICENSE`: "version 2") | `universal` | `xemu.app` (top level of the zip, beside `LICENSE.txt`) |
  | `xemu-hdd` (asset) | `1.0` | `https://github.com/xemu-project/xemu-hdd-image/releases/download/1.0/xbox_hdd.qcow2.zip` | `d9f5a4c1224ff24cf9066067bda70cc8b9c874ea22b9c542eb2edbfc4621bb39` | see ruling below | — | `xbox_hdd.qcow2` (4 521 984 bytes inside the zip) |

- **Host allowlist** gains `dl.dolphin-emu.org`. Dolphin has no GitHub releases; its universal dmg is only published there.
- **Licensing ruling (Mike to confirm at plan review):** the xemu HDD image repo has no license file. Its README describes it as "free of any copyrighted content": a blank FATX disk with a dummy dashboard built with nxdk. It's treated as a data file like the DATs. The manifest records `"license": "LicenseRef-xemu-hdd-image-copyright-free"`, and that one identifier joins `LicensePolicy.runtimeAllowed` (not `vendoredAllowed`).
- **Dolphin** user folder is `~/Library/Application Support/Dolphin`; config in `Config/Dolphin.ini`, `Config/GFX.ini`, `Config/GCPadNew.ini`, `Config/WiimoteNew.ini`, `Config/Hotkeys.ini`. Key names verified in Dolphin's `MainSettings.cpp` / `GraphicsSettings.cpp`; the Metal backend's config name is `Metal` (`VideoBackends/Metal/VideoBackend.h`).
- **xemu** config is `~/Library/Application Support/xemu/xemu/xemu.toml` (`SDL_GetPrefPath("xemu","xemu")`). Key names from `config_spec.yml`. `input.auto_bind` defaults to true, so xemu binds the first controller itself; retromac writes no xemu input config.
- **Xbox BIOS** (MD5s from Batocera's `batocera-systems` table):

  | File | MD5 | Size |
  |---|---|---|
  | `mcpx_1.0.bin` | `d49c52a4102f6df7bcf8d0617ac475ed` | 512 |
  | `Complex_4627.bin` | `39cee882148a87f93cb440b99dde3ceb` | 262 144 (verify in Task 7 Step 1) |

- **Not in this plan:**
  - RVZ conversion. Dolphin's macOS bundle ships no `dolphin-tool` (checked inside the 2609 dmg), so the spec's "GameCube and Wii to RVZ" has no upstream tool on macOS. Games stay in the format they arrive in; RVZ, WIA and WBFS already play.
  - A Dolphin update feed. Dolphin has no release API that the updater's `Upstream.Kind` cases can read, so `dolphin` has `upstream: null` and moves only when the manifest is bumped by hand. xemu gets a `githubRelease` upstream.
  - GameCube multi-disc `.m3u`. Dolphin swaps to disc 2 by itself when it's in a game-list folder, which retromac configures.
  - The per-chip cap is limited to base M1/M2 chips (below); a finer table waits for real performance data.
  - Converting full Redump-layout Xbox images (video partition first) to XISO. The importer already recognizes them, and Task 8 Step 4 checks whether xemu boots one. If it doesn't, a follow-up copies just the game partition at import, since `DiscSniffer.xbox` already finds it.
- **Coordination with Console Mode** (branch `console-mode`, unmerged): its exit combo quits RetroArch and ES-DE only. Whichever of the two branches merges second adds Dolphin and xemu to the agent's quit list (`ConsoleAction.quitRetroArch` becomes a list of app names), per the spec's "standalone emulators extend the same 'ask, then terminate' list".

## Review Focus

1. **Dolphin doesn't see the controller** because the SDL device name retromac writes doesn't match the pad. Expected: a connected pad drives GameCube port 1 and Wiimote 1 with no setup. Owned by Task 5 (hands-on name capture plus a test that the device line comes from the captured table).
2. **Re-apply clobbers settings the user changed inside Dolphin or xemu.** Expected: only retromac's keys change; everything else, including keys Dolphin and xemu add on exit, survives. Tests in Tasks 4 and 6.
3. **The Xbox hard disk image (which holds game saves) is replaced** on re-install, update or a second Apply. Expected: never overwritten once it exists. Test in Task 2.
4. **Xbox BIOS missing.** Expected: the Systems step says exactly which file is missing, and xemu's own error is the only other symptom. Test in Task 7.
5. **Library paths with spaces or quotes** (`Application Support`, a user library named `Mike's "Games"`) break the INI or TOML. Expected: Dolphin and xemu read the right folder. Tests in Tasks 4 and 6.

---

### Task 1: Manifest: standalone apps, assets and policy

**Files:**
- Modify: `Sources/RetromacCore/Manifest/Manifest.swift`, `Sources/RetromacCore/Manifest/ManifestPolicy.swift`, `Sources/RetromacCore/Resources/manifest.json`
- Test: `Tests/RetromacCoreTests/BundledManifestTests.swift`, `Tests/RetromacCoreTests/ManifestPolicyTests.swift`

**Interfaces:**
- Produces:
  - `AppEntry.systems: [SystemID]?` (nil = always installed, as RetroArch and ES-DE are today).
  - `public struct AssetEntry: Codable, Equatable, Sendable { id, version, url: URL, sha256: String, license, system: SystemID, fileName: String }`.
  - `Manifest.assets: [AssetEntry]`, decoded as `[]` when the key is absent (older manifests and release manifests keep decoding).
  - `Manifest.app(for: SystemID) -> AppEntry?`; `installableSystems` = systems with a core **or** an app.
  - `ManifestPolicy.violations` also checks assets with the same `common(...)` rules.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func standalonesAreInstallable() throws {
    let m = try Manifest.bundled()
    #expect(m.installableSystems == [.nes, .snes, .genesis, .n64, .psx, .saturn, .gc, .wii, .xbox])
    #expect(m.app(for: .gc)?.id == "dolphin" && m.app(for: .wii)?.id == "dolphin")
    #expect(m.app(for: .xbox)?.id == "xemu")
    #expect(m.apps.first { $0.id == "retroarch" }?.systems == nil)
    #expect(m.assets.map(\.id) == ["xemu-hdd"])
    #expect(ManifestPolicy.violations(m).isEmpty)
}
@Test func manifestWithoutAssetsStillDecodes() throws {
    let json = #"{"schemaVersion":1,"manifestVersion":1,"minAppVersion":"0.1.0","apps":[],"cores":[]}"#
    #expect(try JSONDecoder().decode(Manifest.self, from: Data(json.utf8)).assets.isEmpty)
}
@Test func assetFromUnlistedHostIsRejected() {
    var m = manifest()
    m.assets = [AssetEntry(id: "x", version: "1", url: URL(string: "https://evil.example/x.zip")!, sha256: String(repeating: "0", count: 64),
                           license: "MIT", system: .xbox, fileName: "x")]
    #expect(ManifestPolicy.violations(m).contains { $0.contains("evil.example") })
}
```

- [ ] **Step 2: Run** `swift test --filter 'standalonesAreInstallable|manifestWithoutAssetsStillDecodes|assetFromUnlistedHostIsRejected'`. Expected: compile failure (no `systems`, `assets`, `app(for:)`).
- [ ] **Step 3: Implement** the produced interfaces; add the two app entries (with `"systems": ["gc","wii"]` / `["xbox"]`) and the asset from the Global Constraints table to `manifest.json`; xemu's upstream is `{ "kind": "githubRelease", "project": "xemu-project/xemu", "assetPattern": "^xemu-[0-9.]+-macos-universal\\.zip$" }`. Add `dl.dolphin-emu.org` to `allowedHosts` and the HDD license identifier to `runtimeAllowed`.
- [ ] **Step 4: Run** `swift test`. Expected: all pass. (`discCoresAreInstallable` asserts the old installable list; update it to the new one, since it now describes the same thing as `standalonesAreInstallable`, and say so in the ledger.)
- [ ] **Step 5: Commit** `feat: standalone emulators and data assets in the manifest`

---

### Task 2: Installer: zip apps, per-system apps, assets

**Files:**
- Modify: `Sources/RetromacCore/Install/Installer.swift`, `Sources/RetromacCore/Support/Paths.swift`
- Test: `Tests/RetromacCoreTests/InstallerTests.swift`

**Interfaces:**
- Consumes: Task 1's `AppEntry.systems`, `Manifest.assets`.
- Produces:
  - `Paths.xemuSupport` = `~/Library/Application Support/xemu`; `Paths.xemuHDD` = `xemuSupport/xbox_hdd.qcow2`; `Paths.assetTarget(_ asset: AssetEntry) -> URL` (xbox → `xemuSupport/<fileName>`).
  - `install(systems:)` installs an app only when `systems == nil` or it shares a system with the selection; installs each asset whose `system` is selected **only if its target doesn't exist**; `InstallReport.installed` lists asset ids too.
  - `stageApp` accepts `.zip` (extract with `/usr/bin/ditto -x -k`, then find `appName` at the top level or one level down) as well as `.dmg` (unchanged), chosen by the URL's path extension.

- [ ] **Step 1: Write the failing tests** (add a `makeAppZip(in:appName:version:)` fixture beside `makeAppDmg`, built with `ditto -c -k --keepParent`):
  - `installsAppFromZip`: the app lands in `paths.applications` with its version.
  - `standaloneInstalledOnlyForItsSystems`: an app with `systems: [.xbox]` is skipped for `[.nes]` and installed for `[.xbox]`.
  - `assetInstalledUnzippedOnce`: a zip asset lands at `assetTarget` with the inner file's bytes; report lists its id.
  - `existingHardDiskIsNeverReplaced` (Review Focus 3): pre-write `"saves"` to `paths.xemuHDD`, install with the asset, expect the file still reads `"saves"`, and a second install also leaves it.
  - `assetShaMismatchWritesNothing`: a wrong sha throws `checksumMismatch` and `assetTarget` doesn't exist.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** Assets go through the existing `fetch(_:id:sha256:into:)` (sha-checked), are extracted into a temp dir, and the named file is moved to its target; a zip without `fileName` throws `fileNotFoundInArchive`.
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: install zip apps, standalone emulators per system, and data assets`

---

### Task 3: ES-DE systems and find rules for Dolphin and xemu

**Files:**
- Modify: `Sources/RetromacCore/Render/ESDESystems.swift`, callers of `ESDESystems.findRules(retroarch:cores:)` (`ProfileRenderer.swift`, `Support/Migrator.swift`)
- Test: `Tests/RetromacCoreTests/RendererTests.swift`

**Interfaces:**
- Consumes: Task 1's `Manifest.app(for:)`.
- Produces: `ESDESystems.findRules(paths: Paths) -> String` (replaces the two-argument form) with emulator rules `RETROARCH`, `DOLPHIN` (`<applications>/Dolphin.app/Contents/MacOS/Dolphin`) and `XEMU` (`<applications>/xemu.app/Contents/MacOS/xemu`), all `staticpath`, plus the existing `RETROARCH` core rule.

`info` gains (extensions are what the importer files for these systems; `gcz` is refused at import):

| system | fullname | extensions |
|---|---|---|
| `gc` | `Nintendo GameCube` | `iso gcm rvz wia ciso` |
| `wii` | `Nintendo Wii` | `iso rvz wia wbfs ciso` |
| `xbox` | `Microsoft Xbox` | `iso xiso` |

The `<command>` for a system with no core comes from its app: `dolphin` → label `Dolphin`, `%EMULATOR_DOLPHIN% -b -e %ROM%`; `xemu` → label `xemu`, `%EMULATOR_XEMU% -dvd_path %ROM%` (full screen comes from `xemu.toml`, Task 6).

- [ ] **Step 1: Write the failing tests**
  - `gamecubeLaunchesDolphin`: `xml(for: [.gc, .wii], manifest: .bundled())` contains `<name>gc</name>`, `<name>wii</name>`, `%EMULATOR_DOLPHIN% -b -e %ROM%`, `.rvz`, and not `.gcz`.
  - `xboxLaunchesXemu`: contains `<name>xbox</name>` and `%EMULATOR_XEMU% -dvd_path %ROM%`.
  - `findRulesPointAtRetromacApps`: `findRules(paths:)` contains `<emulator name="DOLPHIN">` with `…/Apps/Dolphin.app/Contents/MacOS/Dolphin` and the same for `XEMU`, XML-escaped (use a home path containing `&` to prove escaping).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: GameCube, Wii and Xbox in ES-DE`

---

### Task 4: Dolphin settings, INI merge and internal resolution

**Files:**
- Create: `Sources/RetromacCore/Config/IniConfig.swift`, `Sources/RetromacCore/Render/DolphinRenderer.swift`, `Sources/RetromacCore/Support/Chip.swift`
- Modify: `Sources/RetromacCore/Render/ProfileRenderer.swift` (new `Kind`, call sites), `Sources/RetromacCore/Apply/Applier.swift`, `Sources/RetromacCore/Display/DisplayRules.swift`, `Sources/RetromacCore/Resources/display_rules.json`, `Sources/RetromacCore/Support/Paths.swift`
- Test: `Tests/RetromacCoreTests/IniConfigTests.swift`, `Tests/RetromacCoreTests/DolphinRendererTests.swift`, `Tests/RetromacCoreTests/DisplayTests.swift`

**Interfaces:**
- Produces:
  - `RenderedFile.Kind.iniKeys([String: [String: String]])` (section → key → value), applied with `IniConfig.merge(existing: String, owned: [String: [String: String]]) -> String`: replaces owned keys in place, appends missing keys to their section and missing sections at the end, keeps every other line byte-for-byte; output is deterministic (sorted keys within appended content).
  - `Paths.dolphinConfig` = `~/Library/Application Support/Dolphin/Config`.
  - `DisplayRules.internalScale: [SystemID: ScaleRule]` with `struct ScaleRule: Codable { nativeHeight: Int; maxScale: Int }`, `baseChips: [String]`, `baseChipMaxScale: Int`, and `func internalScale(for system: SystemID, display: DisplayProfile, chip: String) -> Int?` = `min(maxScale, chip cap, max(1, ceil(display.heightPx / nativeHeight)))`, where the chip cap applies when `chip` is exactly one of `baseChips`.
  - `Chip.brand() -> String` (`sysctlbyname("machdep.cpu.brand_string")`, e.g. `"Apple M4 Pro"`).
  - `ProfileRenderer.render(_:manifest:rules:paths:chip:)` with `chip: String = Chip.brand()`.
- `display_rules.json` adds: `"internalScale": {"gc": {"nativeHeight": 528, "maxScale": 5}, "wii": {"nativeHeight": 528, "maxScale": 5}, "xbox": {"nativeHeight": 480, "maxScale": 4}}`, `"baseChips": ["Apple M1", "Apple M2"]`, `"baseChipMaxScale": 3`.

When `gc` or `wii` is selected, the renderer emits:

| File | Section | Key | Value |
|---|---|---|---|
| `Dolphin.ini` | `General` | `ISOPaths` | `2` |
| | | `ISOPath0` / `ISOPath1` | `<libraryRoot>/gc` / `<libraryRoot>/wii` |
| | `Core` | `GFXBackend` | `Metal` (Vulkan here is MoltenVK, which froze Beetle PSX HW's output in Phase 3b) |
| | `Display` | `Fullscreen` | `True` |
| | `Interface` | `ConfirmStop` | `False` |
| | `Analytics` | `PermissionAsked` / `Enabled` | `True` / `False` (no first-run prompt) |
| | `AutoUpdate` | `UpdateTrack` | empty (retromac owns updates) |
| `GFX.ini` | `Settings` | `InternalResolution` | `internalScale(for: .gc, …)` |

- [ ] **Step 1: Write the failing tests**
  - `IniConfigTests`: `mergeReplacesOwnedKeysAndKeepsTheRest` (unknown keys and sections untouched, comments kept), `mergeAddsMissingKeyToExistingSection`, `mergeAddsMissingSection`, `mergeIsIdempotent`, `mergeOfEmptyFile`.
  - `dolphinSettingsForGameCube`: the table above, with a library root of `/tmp/h/Mike's "Games"` appearing verbatim as `ISOPath0 = /tmp/h/Mike's "Games"/gc` (Review Focus 5: Dolphin's INI values are unquoted to end of line).
  - `noDolphinFilesWithoutGameCubeOrWii`.
  - `userDolphinSettingsSurviveReapply` (Review Focus 2): apply, append `[Display]\nRenderToMain = True` and change `ISOPath0`, apply again; `RenderToMain` is still there and `ISOPath0` is retromac's again.
  - `DisplayTests`: `internalScaleFromDisplayHeight` (1440p → gc 3, xbox 3; 2160p → gc 5, xbox 4) and `baseChipCapsScale` (2160p on `"Apple M1"` → gc 3; on `"Apple M1 Pro"` → gc 5).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.** No change is needed to the Applier's running-app check: its list comes from `manifest.apps`, so it already refuses to apply while Dolphin or xemu runs (both rewrite their config on exit).
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: Dolphin settings and internal resolution from display rules`

---

### Task 5: Dolphin controllers and the exit hotkey

**Files:**
- Create: `Sources/RetromacCore/Render/DolphinPads.swift`
- Modify: `Sources/RetromacCore/Render/DolphinRenderer.swift`
- Test: `Tests/RetromacCoreTests/DolphinRendererTests.swift`

Dolphin names gamepad inputs by position (`SDLGamepad.h`): `Button S/E/W/N`, `Pad N/S/W/E`, `Shoulder L/R`, `Trigger L/R`, `Thumb L/R`, `Start`, `Back`, `Guide`, `Left X±`, `Left Y±`, `Right X±`, `Right Y±`. Its device line is `SDL/<index>/<SDL gamepad name>`, which is SDL's name for the pad, not necessarily `GCController.vendorName`.

- [ ] **Step 1 (hands-on, Mike at the screen; confirm first):** install Dolphin through retromac (Tasks 1–4 bundled into `/Applications/retromac.app`), connect each controller Mike uses, open Dolphin › Controllers › GameCube Port 1 › Configure, and read the Device list. Record in the ledger, per pad: `GCController.vendorName` (from retromac's Controllers step) → Dolphin's device string. Also note whether a fresh Dolphin (no `GCPadNew.ini`) already maps the pad by itself.
- [ ] **Step 2: Decide by Step 1's result, and ledger it as a ruling:**
  - **Dolphin auto-maps with no file:** retromac writes only `Hotkeys.ini` and the Wiimote file below, with `Device` left to Dolphin.
  - **It doesn't:** `DolphinPads.device(for: ControllerProfile) -> String` maps `vendorName` to the recorded SDL name (table from Step 1; unknown pads fall back to `vendorName`), and retromac writes the full mappings below for port 1 using the first profile controller.
- [ ] **Step 3: Write the failing tests** (`[GCPad1]` in `GCPadNew.ini`, `[Wiimote1]` in `WiimoteNew.ini`, `[Hotkeys]` in `Hotkeys.ini`; every value is wrapped in backticks only when it contains a space):

| GameCube | Input | | Wii (emulated Wiimote + Nunchuk, `Source = 1`, `Extension = Nunchuk`) | Input |
|---|---|---|---|---|
| `Buttons/A` | `Button S` | | `Buttons/A` | `Button S` |
| `Buttons/B` | `Button W` | | `Buttons/B` | `Trigger R` |
| `Buttons/X` | `Button E` | | `Buttons/1` / `Buttons/2` | `Button W` / `Button N` |
| `Buttons/Y` | `Button N` | | `Buttons/-` / `Buttons/+` | `Back` / `Start` |
| `Buttons/Z` | `Shoulder R` | | `Buttons/Home` | `Guide` |
| `Buttons/Start` | `Start` | | `D-Pad/Up…Right` | `Pad N/S/W/E` |
| `Main Stick/Up…Right` | `Left Y-`, `Left Y+`, `Left X-`, `Left X+` | | `IR/Up…Right` | `Right Y-`, `Right Y+`, `Right X-`, `Right X+` |
| `C-Stick/Up…Right` | `Right Y-`, `Right Y+`, `Right X-`, `Right X+` | | `Nunchuk/Buttons/C` / `Z` | `Shoulder L` / `Trigger L` |
| `Triggers/L` / `R` | `Trigger L` / `Trigger R` | | `Nunchuk/Stick/Up…Right` | as Main Stick |
| `Triggers/L-Analog` / `R-Analog` | `Trigger L` / `Trigger R` | | `Shake/X`, `Y`, `Z` | `Button E` |
| `D-Pad/Up…Right` | `Pad N/S/W/E` | | | |

  Hotkeys: `General/Stop` = `@(Back+Start)` (Select+Start, the same exit RetroArch uses). Tests: `gamecubePadMapping`, `wiimoteWithNunchukMapping`, `exitHotkeyIsSelectStart`, and `deviceLineUsesTheRecordedSdlName` (Review Focus 1; only in the "doesn't auto-map" branch).
- [ ] **Step 4: Run them.** Expected: FAIL. **Step 5: Implement. Step 6: Run** `swift test`. Expected: all pass.
- [ ] **Step 7 (hands-on):** rebuild, Apply, start a GameCube and a Wii game from ES-DE; sticks, triggers and Select+Start (returns to ES-DE) work. Ledger the result.
- [ ] **Step 8: Commit** `feat: Dolphin controller mapping and exit hotkey`

---

### Task 6: xemu settings and TOML merge

**Files:**
- Create: `Sources/RetromacCore/Config/TomlConfig.swift`, `Sources/RetromacCore/Render/XemuRenderer.swift`
- Modify: `Sources/RetromacCore/Render/ProfileRenderer.swift`, `Sources/RetromacCore/Apply/Applier.swift`, `Sources/RetromacCore/Support/Paths.swift`
- Test: `Tests/RetromacCoreTests/TomlConfigTests.swift`, `Tests/RetromacCoreTests/XemuRendererTests.swift`

**Interfaces:**
- Consumes: Task 2's `Paths.xemuSupport`/`xemuHDD`; Task 4's `internalScale`; Task 7's BIOS file names (fixed strings here, so Tasks 6 and 7 can land in either order).
- Produces:
  - `enum TomlValue: Equatable, Sendable { case bool(Bool), int(Int), string(String) }`; strings are written as TOML basic strings with `\` and `"` escaped and control characters as `\uXXXX`.
  - `RenderedFile.Kind.tomlKeys([String: [String: TomlValue]])` (table path like `"sys.files"` → key → value), applied with `TomlConfig.merge(existing: String, owned: …) -> String`: same keep-everything-else contract as `IniConfig.merge`; only `[a.b]` tables and `key = value` lines need parsing (xemu writes nothing else).
  - `Paths.xemuConfig` = `xemuSupport/xemu/xemu.toml`.

When `xbox` is selected:

| Table | Key | Value |
|---|---|---|
| `general` | `show_welcome` | `false` |
| | `skip_boot_anim` | `true` |
| | `games_dir` | `<libraryRoot>/xbox` |
| `display.window` | `fullscreen_on_startup` | `true` |
| `display.quality` | `surface_scale` | `internalScale(for: .xbox, …)` |
| `sys.files` | `bootrom_path` | `<retroarchSystem>/mcpx_1.0.bin` |
| | `flashrom_path` | `<retroarchSystem>/Complex_4627.bin` |
| | `hdd_path` | `Paths.xemuHDD` |

The renderer leaves `display.renderer` at xemu's default (`OPENGL`), not Vulkan, for the same MoltenVK reason as Task 4.

- [ ] **Step 1: Write the failing tests:** `tomlMergeKeepsUnknownTablesAndKeys`, `tomlMergeAddsMissingTable`, `tomlStringEscaping` (a path containing `"` and `\` round-trips as a valid basic string), `xemuSettingsForXbox` (the table above), `noXemuFileWithoutXbox`, `userXemuSettingsSurviveReapply` (Review Focus 2: a user-set `[audio] volume_limit = 0.5` survives).
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `swift test`. Expected: all pass.
- [ ] **Step 5: Commit** `feat: xemu settings`

---

### Task 7: Xbox BIOS recognition

**Files:**
- Modify: `Sources/RetromacCore/Library/Bios.swift`, `Sources/retromac/Views/SystemsStep.swift`
- Test: `Tests/RetromacCoreTests/BiosTests.swift`

**Interfaces:**
- Produces: `BiosFile.size: Int` (per entry; the single `static let size` goes away) and `BiosFile.match` checks a file's size against `Set(known.map(\.size))` before hashing. `BiosFile.known` gains the two Xbox rows from Global Constraints, region `"All"`. The importer's BIOS branch is unchanged, so Xbox BIOS files land in RetroArch's system folder beside the others, where Task 6 points xemu.

- [ ] **Step 1: Verify the Complex 4627 size.** If Mike has the file, `stat -f %z` it and confirm its MD5 matches; otherwise keep 262 144 and ledger the assumption (cost if wrong: that BIOS isn't auto-filed and the Systems caption says it's missing).
- [ ] **Step 2: Write the failing tests:** `xboxBiosOfDifferentSizesAreRecognized` (synthetic table: a 512-byte and a 262 144-byte entry both match by MD5), `fileOfAnUnknownSizeIsNeverHashed` (stays nil), `xboxBiosStatusNamesWhatIsMissing` (Review Focus 4: `BiosStatus.present` with only the MCPX returns just it, so the caption can name `Complex_4627.bin` as missing).
- [ ] **Step 3: Run them.** Expected: FAIL.
- [ ] **Step 4: Implement**, and add the Xbox caption to `SystemsStep.biosCaption`: none present → "Needs your Xbox's MCPX boot ROM (mcpx_1.0.bin) and BIOS (Complex_4627.bin). Add them in Games like any game file."; one present → "Still needs <missing file name>."; both → "BIOS found."
- [ ] **Step 5: Run** `swift test`. Expected: all pass.
- [ ] **Step 6: Commit** `feat: recognize Xbox BIOS files`

---

### Task 8: End to end on Mike's Mac

These steps download two emulators and change Mike's real setup. **Confirm with Mike before Step 2.**

- [ ] **Step 1:** `RETROMAC_VERSION=0.4.0 scripts/bundle.sh`, install as `/Applications/retromac.app` after quitting the running copy.
- [ ] **Step 2:** Settings › Systems: turn on GameCube, Wii and Xbox; Install & Apply. Expected: the log lists `dolphin`, `xemu` and `xemu-hdd` installed; `Apps/Dolphin.app`, `Apps/xemu.app` and `~/Library/Application Support/xemu/xbox_hdd.qcow2` exist; `Dolphin.ini`, `GFX.ini` and `xemu.toml` carry the Task 4 and 6 values.
- [ ] **Step 3:** Add a GameCube or Wii game Mike owns; ES-DE lists it; it boots full screen in Dolphin (Metal), the controller works, Select+Start returns to ES-DE.
- [ ] **Step 4:** Add Mike's Xbox BIOS files and an Xbox game in XISO form; the Systems caption updates; the game boots full screen in xemu with the controller. If Mike has a full Redump-layout image, try it too and ledger whether it boots. A second Install & Apply leaves `xbox_hdd.qcow2` unchanged (`shasum` before and after).
- [ ] **Step 5:** Record results with command output in the ledger.
