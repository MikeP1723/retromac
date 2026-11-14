# Phase 3b: PlayStation and Saturn Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PS1 and Saturn installable and playable end to end: cores installed, games launching from ES-DE as one entry per game (multi-disc via `.m3u`), BIOS files recognized and filed by the importer, and optional CHD conversion.

**Architecture:** Two libretro cores join the manifest, and ES-DE gets `psx`/`saturn` system entries that list only `.cue`, `.chd` and `.m3u`. A new `DiscSets.organize` puts each multi-disc game in a `Game.m3u/` folder (ES-DE's "directories interpreted as files") and writes a `.cue` for any bare image. It runs after every import and on every Apply, so older flat libraries get tidied too. The importer recognizes BIOS files by MD5 and copies them to RetroArch's system folder. `ChdTool` wraps Homebrew's `chdman` and converts one disc set at a time, verifying before it deletes anything.

**Tech Stack:** Swift 6 SwiftPM, macOS 14+ arm64, SwiftUI, Swift Testing, CryptoKit (`Insecure.MD5`). No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-13-retromac-design.md`. The relevant parts are the Systems table, the Librarian section and Resolved decisions 4–7.

## Global Constraints

- Every new source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later`.
- Swift 6 strict concurrency, with zero warnings in new code.
- No third-party Swift dependencies.
- Emulators and tools are fetched from upstream at runtime and never vendored. `chdman` comes only from Homebrew's `rom-tools` (decision 4).
- No BIOS, commercial disc images or real DATs in the repo or CI. BIOS tests inject a synthetic `BiosFile` table.
- Licenses:
  - Beetle PSX HW and Beetle Saturn are **GPL-2.0-or-later**. Verified 2026-11-13: the `COPYING` files are GPLv2, and the source headers say "either version 2 … or (at your option) any later version".
  - `rom-tools` (chdman) is GPL-2.0-or-later.
- CHD is optional. Without Homebrew, everything else still works, and the CHD UI doesn't appear.
- Core metadata, from libretro-core-info, 2026-11-13:

  | System | `id` | `version` | `libraryName` | `file` |
  |---|---|---|---|---|
  | psx | `mednafen_psx_hw` | `v0.9.44.1` | `Beetle PSX HW` | `mednafen_psx_hw_libretro.dylib` |
  | saturn | `mednafen_saturn` | `v0.9.45.1` | `Beetle Saturn` | `mednafen_saturn_libretro.dylib` |

  The URLs follow the existing pattern: `https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/<file>.zip`. `sha256` is null (decision 3).
- **BIOS table.** The MD5s come from libretro-core-info and libretro docs. Every file is 524 288 bytes.

  | System | File | Region label | MD5 |
  |---|---|---|---|
  | psx | `scph5500.bin` | Japan | `8dd7d5296a650fac7319bce665a6a53c` |
  | psx | `scph5501.bin` | USA | `490f666e1afb15b7362b406ed1cea246` |
  | psx | `scph5502.bin` | Europe | `32736f17079d0b2b7024407c39bd3050` |
  | saturn | `sega_101.bin` | Japan | `85ec9ca47d8f6807718151cbcca8b964` |
  | saturn | `mpr-17933.bin` | USA/Europe | `3240872c70984b6cbfda1586cab68dbe` |

- **Without a BIOS.** Beetle PSX HW falls back to its built-in OpenBIOS (libretro docs), so PS1 works without one, with lower compatibility. Saturn requires a BIOS.
- **PS1 pads are DualShock:** device `517` = `RETRO_DEVICE_SUBCLASS(RETRO_DEVICE_ANALOG, 1)` (beetle-psx `input.h:9`). RetroArch reads `input_libretro_device_pN` only from remap files (v1.22.2 `configuration.c:6245`, inside `input_remapping_load_file`). Button keys missing from a remap keep their defaults, so a remap holding only the device lines is safe.
- **ES-DE multi-disc layout** (ES-DE USERGUIDE, "Directories interpreted as files"): `psx/Game.m3u/Game.m3u` plus the disc files, all inside a folder named `Game.m3u`.
- **My calls,** none of them confirmed by Mike:
  - PS1 ports 1–2 default to DualShock.
  - Existing users' profiles don't auto-enable PS1/Saturn. The toggles appear in Settings › Systems, off.
  - The lone-image cue modes are `MODE2/2352` for a raw image whose sector header byte 15 is 2, `MODE1/2352` when it's 1, and `MODE1/2048` for 2048-byte ISOs.

## Review Focus

1. **Disc 2 arrives in a later drop than Disc 1.** Both should end up in one `Game.m3u/` folder with a two-line playlist. Test: Task 3 `discTwoInLaterDropJoinsTheSet`.
2. **A library already holding 3a-2-era flat discs and bare `.bin` files** (Mike's real library). Apply should organize them without losing a file, and a second run should change nothing. Tests: Task 2 `organizeIsIdempotent`, `bareBinGetsACue`.
3. **A file named `scph5501.bin` whose MD5 doesn't match** (bad dump or another model). It must not be filed as a BIOS; it goes through normal handling. Test: Task 4 `wrongHashIsNotBios`.
4. **chdman fails partway.** The cue and bins must stay untouched, no `.chd` may sit at the final name, and the playlist must still list the cue. Test: Task 5 `failedConversionKeepsOriginals`.
5. **Re-importing a game that was already converted to CHD.** It should count as a duplicate, not a second copy. Test: Task 5 `chdOfSameNameIsDuplicate`.

---

### Task 1: PS1 and Saturn cores, ES-DE systems and RetroArch config

**Files:**
- Modify: `Sources/RetromacCore/Resources/manifest.json` (two cores, after `mupen64plus_next`)
- Modify: `Sources/RetromacCore/Support/Paths.swift` (`retroarchSystem`, `coreRemap(libraryName:)`)
- Modify: `Sources/RetromacCore/Render/ESDESystems.swift` (`info` entries for psx and saturn)
- Modify: `Sources/RetromacCore/Render/ProfileRenderer.swift` (`system_directory` key; the PS1 remap)
- Test: `Tests/RetromacCoreTests/BundledManifestTests.swift`, `Tests/RetromacCoreTests/RendererTests.swift`, `Tests/RetromacCoreTests/PathsTests.swift`

**Interfaces:**
- Produces:
  - `Paths.retroarchSystem: URL` = `retroarchSupport/system`
  - `Paths.coreRemap(libraryName:) -> URL` = `retroarchSupport/config/remaps/<n>/<n>.rmp`
  - ES-DE systems `psx` (fullname "Sony PlayStation") and `saturn` (fullname "Sega Saturn"). Extensions for both: `cue`, `chd`, `m3u`.

- [ ] **Step 1: Write the failing tests.**
  - `discCoresAreInstallable`: `try Manifest.bundled().installableSystems == [.nes, .snes, .genesis, .n64, .psx, .saturn]`. Also check `core(for: .psx)?.libraryName == "Beetle PSX HW"` and `core(for: .saturn)?.license == "GPL-2.0-or-later"`.
  - `retroarchSystemPath`: `Paths(home: h).retroarchSystem.path == h.path + "/Library/Application Support/RetroArch/system"`. `coreRemap(libraryName: "Beetle PSX HW")` ends with `config/remaps/Beetle PSX HW/Beetle PSX HW.rmp`.
  - `systemDirectoryIsSet`: the rendered `retroarch.cfg` keys contain `"system_directory": paths.retroarchSystem.path`.
  - `psxGetsDualShockRemap`: with `.psx` in `systems`, a file at `paths.coreRemap(libraryName: "Beetle PSX HW")` with `.retroarchKeys(["input_libretro_device_p1": "517", "input_libretro_device_p2": "517"])`. Without `.psx`, no such file.
  - `esdeListsOnlyLaunchableDiscFiles`: `ESDESystems.xml(for: [.psx, .saturn], manifest:)` contains `<name>psx</name>` and `mednafen_psx_hw_libretro.dylib`, `<name>saturn</name>` and `mednafen_saturn_libretro.dylib`, and both `.m3u` and `.chd`. The psx `<extension>` contains neither `.bin` nor `.iso`.
- [ ] **Step 2: Run `swift test`.** Expected: these five FAIL.
- [ ] **Step 3: Implement.** Add the two manifest entries exactly as in Global Constraints (`arch` `arm64`, `rosetta` false), then the paths, the ES-DE info entries and the renderer keys.
- [ ] **Step 4: Run `swift test`, then `swift run retromac-tool verify-manifest`.** Expected: all pass, and verify-manifest exits 0.
- [ ] **Step 5: Commit:** `feat: PlayStation and Saturn cores`

---

### Task 2: `DiscSets`: multi-disc folders and cues for bare images

**Files:**
- Create: `Sources/RetromacCore/Library/DiscSets.swift`
- Test: `Tests/RetromacCoreTests/DiscSetsTests.swift`

**Interfaces:**
- Consumes: `DiscSniffer.cueFiles(_:) -> [(url, name, dataTrack)]`
- Produces:
  - `public enum DiscSets`
  - `public static let systems: Set<SystemID> = [.psx, .saturn]`
  - `@discardableResult public static func organize(_ folder: URL) throws -> [URL: URL]`. It returns old URL → new URL for every file it moved, and maps each bare image → the cue it wrote.
  - `public static func organizeLibrary(_ libraryRoot: URL)`. It runs `organize` on `libraryRoot/<system>` for each system in `systems` whose folder exists, and ignores errors per folder.
  - `static func trackMode(_ image: URL) -> String?`

**Rules for `organize`** (only the folder's top level, plus existing `*.m3u` directories):
1. **Bare images.** For a top-level `.bin`, `.img` or `.iso` that no top-level `.cue` references (by `cueFiles`), when `<stem>.cue` doesn't exist and `trackMode` is non-nil, write `<stem>.cue`:
   `FILE "<file name>" BINARY\n  TRACK 01 <mode>\n    INDEX 01 00:00:00\n`
2. **`trackMode`:**
   - The first 12 bytes are `00 FF×10 00` → byte 15 == 2 ? `MODE2/2352` : `MODE1/2352`.
   - Otherwise, a size that's a multiple of 2048 → `MODE1/2048`.
   - Otherwise nil, and the image is left alone.
3. **Discs:** top-level `.cue` or `.chd` files whose stem matches `/\s*\(Disc (\d+)\)/`. The base is the stem with that match removed, then trimmed.
4. **Grouping.** A base with two or more discs, or whose `<base>.m3u/` directory already exists, gets that directory. Move each disc file into it. For a cue, also move every file `cueFiles` lists. A lone "(Disc 1)" with no set folder stays where it is.
5. **Playlists.** For every `*.m3u` directory, rewrite `<dir>/<base>.m3u` atomically: the disc files inside it (`.cue` or `.chd`, preferring `.chd` when both exist for one disc number), ordered by disc number, one file name per line, `\n`-terminated. Skip the write if the content is unchanged.

- [ ] **Step 1: Write the failing tests** with real temp folders and synthetic images (`DiscBuilders` for raw/ISO sectors):
  - `bareBinGetsACue`: a raw MODE2 `Game.bin` → `Game.cue` holding `FILE "Game.bin" BINARY` and `TRACK 01 MODE2/2352`. The result maps `Game.bin → Game.cue`.
  - `bareIsoGetsMode1Cue`: a 2048-sector `Game.iso` → `MODE1/2048`.
  - `referencedBinIsLeftAlone`: `Game.cue` plus `Game.bin` → no new files.
  - `twoDiscsBecomeOneEntry`: `G (Disc 1).cue`/`G (Disc 1).bin` and `G (Disc 2).cue`/`G (Disc 2).bin` → all four inside `G.m3u/`, and `G.m3u/G.m3u` == `"G (Disc 1).cue\nG (Disc 2).cue\n"`.
  - `multiTrackCueMovesItsTracks`: `G (Disc 1).cue` with `G (Disc 1) (Track 1).bin` and `(Track 2).bin`, plus Disc 2 → every track moved.
  - `loneDiscOneStaysFlat`.
  - `discNumbersSortNumerically`: Disc 10 after Disc 2.
  - `chdPreferredInPlaylist`: `G.m3u/` holding `G (Disc 1).chd` and `G (Disc 2).cue` → `"G (Disc 1).chd\nG (Disc 2).cue\n"`.
  - `organizeIsIdempotent`: a second `organize` returns `[:]`, and file listings are identical.
- [ ] **Step 2: Run `swift test`.** Expected: FAIL (`DiscSets` not found).
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `feat: multi-disc playlists and cues for bare disc images`

---

### Task 3: Organize after import and on Apply

**Files:**
- Modify: `Sources/RetromacCore/Library/Importer.swift` (the end of `commit`)
- Modify: `Sources/retromac/WizardModel.swift` (after a successful apply in `installAndApply` and in `applyConfigs`)
- Modify: `Sources/retromac/AppModel.swift` (`LibraryStats.scan` counts a `*.m3u` directory as one game and sums its contents' sizes)
- Test: `Tests/RetromacCoreTests/ImporterDiscTests.swift`

**Interfaces:**
- Consumes: `DiscSets.organize`, `DiscSets.organizeLibrary`, `DiscSets.systems`
- Produces: `commit` results whose `destination` reflects any move made by `organize`.

- [ ] **Step 1: Write the failing tests** (using `ImportRig` and a PS1 Redump fixture DAT with "Game (USA) (Disc 1)" / "(Disc 2)" serials):
  - `multiDiscPS1ImportsAsOneEntry`: drop both discs (cue+bin each) → `psx/Game (USA).m3u/` holding both sets and the playlist. Each candidate's `destination` is inside that folder.
  - `discTwoInLaterDropJoinsTheSet`: commit Disc 1 alone (it stays flat), then commit Disc 2 → both inside `Game (USA).m3u/`, with a two-line playlist.
  - `discInsideSetFolderIsDuplicate`: after `multiDiscPS1ImportsAsOneEntry`, re-dropping Disc 2 → `.duplicate(.psx)`. This proves `libraryDiscs` sees inside `*.m3u` folders.
  - `bareBinImportGetsCue`: a lone raw PS1 `.bin` → `psx/<name>.cue` exists, and `destination` is the cue.
- [ ] **Step 2: Run `swift test`.** Expected: the first, second and fourth FAIL. The third may already pass, because `walk` is recursive. If so, note it as characterization in the ledger.
- [ ] **Step 3: Implement.** At the end of `commit`, for each system in `DiscSets.systems` that any committed item was filed under, call `organize(libraryRoot/<system>)`, then remap destinations through the returned dictionary. An organize error leaves the items as committed; never fail the import for it. In `WizardModel`, call `DiscSets.organizeLibrary(profile.libraryRoot)` after a successful apply.
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `feat: file multi-disc games as one entry`

---

### Task 4: BIOS files

**Files:**
- Create: `Sources/RetromacCore/Library/Bios.swift`
- Modify: `Sources/RetromacCore/Library/Importer.swift` (init params; detection in `handle` right after the archive branch and before disc sniffing, so zipped BIOS files are unpacked first; `summarize`; `bytesToCopy`; status gating in `commit`)
- Modify: `Sources/retromac/GamesModel.swift` (`addable`, and pass `biosDirectory: paths.retroarchSystem`), `Sources/retromac/Views/LibraryView.swift` (icon, row text, summary), `Sources/retromac/Views/SystemsStep.swift` (status caption), `Sources/retromac-tool/main.swift` (print case and `biosDirectory`)
- Test: `Tests/RetromacCoreTests/BiosTests.swift`

**Interfaces:**
- Produces:
  - `public struct BiosFile: Equatable, Sendable { public let system: SystemID; public let fileName: String; public let region: String; public let md5: String; public static let known: [BiosFile] }`, with the five rows from Global Constraints.
  - `public enum BiosStatus { public static func present(in directory: URL, known: [BiosFile] = BiosFile.known) -> [SystemID: [BiosFile]] }`. A file counts only if it exists **and** its MD5 matches.
  - `ImportStatus.bios(SystemID, region: String)`. `system` returns nil for it, because it isn't filed into the library.
  - `ImportSummary.bios: Int`
  - `Importer.init(…, biosDirectory: URL? = nil, bios: [BiosFile] = BiosFile.known)`. A nil `biosDirectory` turns detection off, so existing call sites are unchanged until they opt in.

**Detection:** a file of exactly 524 288 bytes whose MD5 (`Insecure.MD5`, lowercase hex) is in `bios`. The result is `.bios(system, region:)`. The destination is `biosDirectory/<fileName>`, staged via `stage`, so duplicate handling comes free: an identical file already there → `.duplicate(nil)`. The incoming file's own name doesn't matter.

**UI copy (exact):**
- **Import row:** `→ BIOS · <system displayName> (<region>)`, with icon `cpu` in green. **Summary part:** `<n> BIOS files`.
- **SystemsStep caption** under the PS1 toggle:
  - No BIOS: "Works without a BIOS. Adding your PlayStation's BIOS file improves compatibility — add it in Games like any game file."
  - Otherwise: "BIOS found for: <regions joined by ", ">".
- **SystemsStep caption** under the Saturn toggle:
  - No BIOS: "Needs your Saturn's BIOS file to play. Add it in Games like any game file."
  - Otherwise: "BIOS found for: <regions>".

- [ ] **Step 1: Write the failing tests** with a synthetic table: `BiosFile(system: .saturn, fileName: "mpr-17933.bin", region: "USA/Europe", md5: md5(of: testBytes))`, where `testBytes` is 524 288 deterministic bytes.
  - `biosIsRecognizedAndFiled`: drop `whatever.bin` holding `testBytes` → `.bios(.saturn, region: "USA/Europe")`. After commit, `biosDir/mpr-17933.bin` exists with identical bytes, and nothing appears under the library.
  - `biosInsideZipIsRecognized`.
  - `wrongHashIsNotBios`: 524 288 other bytes named `mpr-17933.bin` → not `.bios`, and nothing is written to `biosDir`.
  - `biosAlreadyPresentIsDuplicate`.
  - `noBiosDirectoryMeansNoDetection`: `biosDirectory: nil` → not `.bios`.
  - `statusRequiresMatchingHash`: `BiosStatus.present` finds the good file and ignores a same-named wrong one.
- [ ] **Step 2: Run `swift test`.** Expected: FAIL.
- [ ] **Step 3: Implement,** including every `switch` over `ImportStatus` listed under Files.
- [ ] **Step 4: Run `swift build` (app and tool targets) and `swift test`.** Expected: success with no warnings in touched files.
- [ ] **Step 5: Commit:** `feat: recognize PlayStation and Saturn BIOS files`

---

### Task 5: Optional CHD conversion

**Files:**
- Create: `Sources/RetromacCore/Library/ChdTool.swift`
- Modify: `Sources/RetromacCore/Library/Importer.swift` (`planDisc`: a duplicate when the folder tree already holds `<name>.chd`)
- Modify: `Sources/retromac/GamesModel.swift` (`convertToCHD()`, progress state), `Sources/retromac/Views/LibraryView.swift` (the section)
- Test: `Tests/RetromacCoreTests/ChdToolTests.swift`, `Tests/RetromacCoreTests/ImporterDiscTests.swift`

**Interfaces:**
- Consumes: `CommandRunner`, `DiscSniffer.cueFiles`, `DiscSets.organize`
- Produces:
  - `public struct ChdTool: Sendable { public init(runner: any CommandRunner, brew: URL = URL(filePath: "/opt/homebrew/bin/brew"), chdman: URL = URL(filePath: "/opt/homebrew/bin/chdman")); public var hasHomebrew: Bool; public var hasChdman: Bool; public func installChdman() throws; public func convert(cue: URL) throws -> URL; public static func convertible(in libraryRoot: URL) -> [URL] }`
  - **`installChdman`** runs `brew install rom-tools`.
  - **`convertible`** returns every `.cue` under `libraryRoot/psx` and `libraryRoot/saturn`, including inside `*.m3u` directories, sorted by path.
  - **`convert`:**
    1. Run `chdman createcd -i <cue> -o <dir>/.retromac-<uuid>.chd`, then `chdman verify -i <tmp>`.
    2. Rename the temp file to `<dir>/<cue stem>.chd`. If that name exists, throw without touching anything.
    3. Delete the cue and every `cueFiles` entry, then return the `.chd`.
    4. On any failure, remove the temp file and rethrow. The originals stay untouched.
  - **The caller** runs `DiscSets.organize` on the system folder after each conversion, so playlists switch to `.chd`.

**UI (LibraryView).** Shown only when `hasHomebrew` and `convertible` is non-empty:
- **Button:** "Shrink disc games".
- **Caption:** "Converts PlayStation and Saturn discs to CHD, which usually takes about half the space. The first time, retromac installs the chdman tool with Homebrew. Each game takes a minute or two."
- **Progress:** "Converting <i> of <n>: <file stem>"
- **Per-game failure:** "Couldn't convert <file stem> — the original files are untouched." Then it continues with the next game.

- [ ] **Step 1: Write the failing tests:**
  - **A fake runner** records commands. On `createcd` it writes a few bytes to the `-o` path; it can be scripted to fail `createcd` or `verify`.
    - `convertRunsCreateThenVerifyAndRemovesOriginals`: exact argument lists, in order. Afterwards `<stem>.chd` exists, and the cue and bins are gone.
    - `failedConversionKeepsOriginals`: `verify` fails → the cue and bins are still present, no `<stem>.chd`, no `.retromac-*.chd` left behind.
    - `existingChdIsNotOverwritten`.
    - `convertibleFindsCuesInSetFolders`.
  - **`chdOfSameNameIsDuplicate`** (Importer): the library holds `psx/Game (USA).chd`, and dropping that game's cue/bin (DAT-identified as "Game (USA)") → `.duplicate(.psx)`.
  - **`realChdmanRoundTrip`:** `.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/chdman"))`. It converts a tiny synthetic MODE2 cue/bin with the real tool, then `DiscSniffer.sniff` on the `.chd` still reports "can't be identified" (documenting the limit).
- [ ] **Step 2: Run `swift test`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`, then `swift build`.** Expected: all pass. The gated test is skipped on machines without chdman.
- [ ] **Step 5: Commit:** `feat: optional CHD conversion for disc games`

---

### Task 6: End to end on Mike's Mac

These steps touch Mike's real library and install `rom-tools` with Homebrew. **Confirm with Mike before Step 2, and again before Step 5.**

- [ ] **Step 1:** Run `RETROMAC_VERSION=0.3.0 scripts/bundle.sh`, then install it as `/Applications/retromac.app`, quitting the running copy first.
- [ ] **Step 2:** Mike opens Settings › Systems and turns on PlayStation and Saturn. Expected: the BIOS captions match the copy. He clicks Install & Apply. Expected: the log lists both cores installed, and these files exist:
  - `~/Library/Application Support/RetroArch/cores/mednafen_psx_hw_libretro.dylib`
  - the matching `mednafen_saturn` dylib
  - `.../config/remaps/Beetle PSX HW/Beetle PSX HW.rmp`

  `retroarch.cfg` should contain `system_directory`.
- [ ] **Step 3:** Mike adds a PS1 game (and his BIOS files, if he has them) through Add Games. Expected: the rows show the BIOS as `→ BIOS · …`, the BIOS lands in `RetroArch/system/`, and the game lands in `Library/psx/`. If it's multi-disc, it lands as a `*.m3u` folder.
- [ ] **Step 4:** Play → ES-DE lists PlayStation with one entry per game. The game boots, and the pad works as a DualShock (the analog sticks respond in a game that uses them).
- [ ] **Step 5:** After Mike confirms, run Shrink disc games. Expected: Homebrew installs rom-tools, the game converts, the library shrinks, and the game still boots from ES-DE.
- [ ] **Step 6:** Record the results, with command output, in the ledger.
