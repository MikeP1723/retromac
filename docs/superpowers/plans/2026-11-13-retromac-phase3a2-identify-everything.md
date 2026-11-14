# retromac Phase 3a-2 (Identify Everything) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Games step recognizes and files games for **every console on Mike's list**. Game databases download in one click from libretro-database. Games not in any database still get clean names.

**Architecture:** This builds on Phase 3a's `Importer`, which lives on the same branch, `phase3a-importer`.
- **Systems:** `SystemID` grows to every listed console, using ES-DE folder names. A separate *installable* set keeps the Systems step and the config renderer limited to consoles with an emulator.
- **Databases:** a clrmamepro DAT parser feeds the existing `DatStore`, which gains a serial index next to the SHA-1 index. A `DatUpdater` downloads the libretro DATs.
- **Disc and modern consoles:** a `DiscSniffer` identifies files by reading **a few header sectors** (ISO9660 `SYSTEM.CNF`, the Saturn header, the GameCube/Wii disc header, the Xbox XBE certificate, or the Wii U/Switch container magic). It never hashes multi-GB images.
- **Names:** `NameCleaner` turns GoodTools-style filenames into readable names for games that aren't in a database.
- **The Importer** stops loading big files into memory. It copies them from the original, or moves them out of its own temp dir when they came from an archive. It also files `.cue`/`.bin` sets together.

**Tech Stack:** Swift 6 and SwiftPM. FileHandle ranged reads, `/usr/bin/tar`, and the existing `Downloader`. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-13-retromac-design.md`, Resolved decisions 6–7 and "Librarian". Phase 3b keeps BIOS detection, multi-disc `.m3u`, CHD conversion, and installing the Saturn and PS1 cores.

## Verified facts this plan relies on (2026-11-13)

- libretro-database `metadat/` has `no-intro/*.dat` and `redump/*.dat` in **clrmamepro** format:

  ```
  game ( name "…" region "…" serial "…" rom ( name "…" size … crc … md5 … sha1 … serial "…" ) )
  ```

- **Redump serial coverage:**

  | DAT | Games | Serials |
  |---|---|---|
  | PS1 | 13,407 | 13,230 |
  | PS2 | 13,618 | 13,242 |
  | Saturn | 2,622 | 2,608 |
  | Wii | 3,817 | 3,814 |
  | Xbox | 2,559 | 2,553 |

  GameCube serials look like `DL-DOL-GW7P-EUR`, which embeds the 4-character game ID `GW7P`.
- **The No-Intro NES DAT** lists both headered (`.nes`) and headerless (`.unh`) hashes per game. **The N64 DAT** lists both `.z64` and `.v64` hashes.
- Switch has no DAT, and Wii U only has a digital DAT whose hashes don't help with disc images. Both are named from the filename.

## Global Constraints

- Phase 1, 2 and 3a constraints still apply. Above all: **dropped originals are never modified, moved or deleted**, and the repo, tests and CI contain no ROM, BIOS, DAT or disc content. Fixtures are synthetic sparse files with hand-written header bytes.
- **`SystemID` raw values are ES-DE folder names:** `nes snes genesis n64 psx ps2 saturn gc wii xbox wiiu switch`.
- **The installable set** is `SystemID.allCases.filter { Manifest.bundled().core(for:) != nil }`. Today that's the four cartridge systems. Only installable systems appear on the Systems step, in `Profile.systems` defaults, and in `ESDESystems`.
- **The DAT download base** is `https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/`. Files are fetched at runtime through `URLSessionDownloader`, never committed or bundled.
- **No full read or hash of any file over 64 MiB.** Disc identification uses at most a few MiB of ranged reads per file.
- **Archive extraction:**
  - **Cap:** total uncompressed size is capped at **16 GiB**. Above that, the archive is unidentified with the reason "archive too large to unpack".
  - **Cartridge members:** each must be at most 64 MiB, as in 3a.
  - **Disc members:** large members are allowed, but only when their extension is a disc or container type.
- **Moves:** large files extracted into the session dir are **moved** into the library at commit, so there's no double copy. Files from the user's own folders are **copied**; APFS clones them when they're on the same volume.

## Review Focus

1. **A 4–8 GB PS2, Wii or Xbox image dropped directly.** Expected: identified from header reads alone, in under a second, with no full read. Committing copies (or clones) it once. Test in Task 5.
2. **A zipped PS1 game (`.cue` plus several `.bin` tracks) dropped as one archive.** Expected: filed as one set, `<Name>.cue` plus `<Name> (Track N).bin`, with the `.cue`'s `FILE` lines rewritten to match. Moved, not copied twice. Test in Task 6.
3. **The DAT download fails part-way** (no network, a 404 for one file). Expected: the systems that downloaded are updated, the failed ones keep their previous index, and the UI lists which failed. Test in Task 3.
4. **A game for a console with no emulator yet** (Saturn, GameCube…). Expected: filed under `Library/<system>/` with the note "<System> emulator arrives in a later update — this game is filed and waiting." It is **not** offered on the Systems step. Test in Task 6, plus a UI check.
5. **Ambiguous containers** (`.chd`, `.gcz`, `.bin` with no `.cue`). Expected: never misfiled. A `.chd` or `.gcz` is unidentified with a specific reason. A lone raw `.bin` is identified if its sector header says PS1 or Saturn, otherwise it falls through to the 3a cartridge path. Test in Task 4.

---

### Task 1: Expand `SystemID` and gate installable systems

**Files:**
- Modify: `Sources/RetromacCore/Model/SystemID.swift`, `Sources/RetromacCore/Manifest/Manifest.swift`, `Sources/retromac/WizardModel.swift`, `Sources/retromac/Views/SystemsStep.swift`, `Sources/retromac/Views/GamesStep.swift`
- Test: `Tests/RetromacCoreTests/SystemIDTests.swift`; modify `Tests/RetromacCoreTests/BundledManifestTests.swift`

**Interfaces:**
- Produces:
  - `enum SystemID: String, Codable, CaseIterable, Sendable { case nes, snes, genesis, n64, psx, ps2, saturn, gc, wii, xbox, wiiu, switch }`
  - `extension SystemID { public var displayName: String; public var isCartridge: Bool }`. `isCartridge` is true for nes, snes, genesis and n64. Display names:

    | ID | Display name |
    |---|---|
    | nes | Nintendo Entertainment System |
    | snes | Super Nintendo |
    | genesis | Sega Genesis |
    | n64 | Nintendo 64 |
    | psx | PlayStation |
    | ps2 | PlayStation 2 |
    | saturn | Sega Saturn |
    | gc | GameCube |
    | wii | Wii |
    | xbox | Xbox |
    | wiiu | Wii U |
    | switch | Nintendo Switch |

  - `extension Manifest { public var installableSystems: [SystemID] }`, meaning `SystemID.allCases` that have a core, in case order.
- Behavior changes:
  - The Systems step iterates `installableSystems`.
  - The new-profile default is `Set(installableSystems)`.
  - `SystemsStep.names` and `GamesStep` switch to `displayName`.
  - `BundledManifestTests` expects the cores to cover `installableSystems`, and expects that set to equal `SystemID.allCases.filter(\.isCartridge)`.

- [ ] **Step 1: Write failing tests.** `rawValuesAreESDEFolders` checks the exact 12 strings. `installableIsCartridgeToday` checks `Manifest.bundled().installableSystems == [.nes, .snes, .genesis, .n64]`. `displayNamesCoverAll` checks every case has a non-empty name.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement, and update the existing call sites.**
- [ ] **Step 4: Run `swift test` and `swift build`.** Expected: all pass, including Phase 1 renderer tests (ES-DE systems stay limited to selected installable systems).
- [ ] **Step 5: Commit** `feat: SystemID for every console; installable systems gate the wizard`

---

### Task 2: clrmamepro DATs and the serial index

**Files:**
- Create: `Sources/RetromacCore/Library/ClrMameParser.swift`
- Modify: `Sources/RetromacCore/Library/DatParser.swift`, `Sources/RetromacCore/Library/DatStore.swift`
- Test: `Tests/RetromacCoreTests/ClrMameTests.swift`

**Interfaces:**
- Produces:
  - `DatFile` gains `var serials: [String: DatEntry]`, decoded with `decodeIfPresent ?? [:]` so 3a's JSON still loads.
  - `enum SerialKey { static func normalize(_ s: String) -> String; static func keys(for serial: String, system: SystemID) -> [String] }`.
    - `normalize` uppercases and drops everything except A–Z and 0–9: `"SLUS-00067"` → `"SLUS00067"`.
    - `keys` splits on `,` and returns the normalized form of each part. For `gc` and `wii` it also adds the 4-character ID after `DOL-` or `RVL-`: `"DL-DOL-GW7P-EUR"` → `["DLDOLGW7PEUR", "GW7P"]`.
  - `enum ClrMameParser { static func parse(_ data: Data) throws -> DatFile }`. A tokenizer handles `(`, `)`, quoted strings with `\"` escapes, and bare words.
    - The header `clrmamepro ( name "…" version "…" )` maps to the system.
    - Each `game ( name … serial … rom ( … sha1 … serial … ) )` adds `entries[sha1.lowercased()]` and `serials[key]` for every key from the game's and the ROM's serials.
  - `DatParser.systemFor(headerName:) throws -> SystemID`, shared by both formats. It matches the header name exactly after stripping trailing ` (…)` groups:

    | Header base name | System |
    |---|---|
    | `Nintendo - Nintendo Entertainment System` | nes |
    | `Nintendo - Super Nintendo Entertainment System` | snes |
    | `Sega - Mega Drive - Genesis` | genesis |
    | `Nintendo - Nintendo 64` | n64 (logiqx ByteSwapped/LittleEndian are still rejected) |
    | `Sony - PlayStation` | psx |
    | `Sony - PlayStation 2` | ps2 |
    | `Sega - Saturn` | saturn |
    | `Nintendo - GameCube` | gc |
    | `Nintendo - Wii` | wii |
    | `Microsoft - Xbox` | xbox |

  - `DatStore.importDats` sniffs the format: data starting (after whitespace) with `<` goes to `DatParser`, and `clrmamepro` goes to `ClrMameParser`.
  - `DatStore.lookup(_ system:, serial:) -> DatEntry?` tries each of `SerialKey.keys(for:system:)`.

- [ ] **Step 1: Write failing tests** using inline clrmamepro text:
  - `parsesNoIntroClrMame`: the NES header plus the `!Clik!` sample with two ROMs → two SHA-1 entries.
  - `parsesRedumpSerials`: PS1 game `serial "SLUS-00067"` → `serials["SLUS00067"]`.
  - `gameCubeGameIDKey`: `DL-DOL-GW7P-EUR` → lookup by `"GW7P"` hits.
  - `multiSerialSplit`: `"SLUS-00892, SLUS-00908"` → both keys.
  - `distinguishesPS1FromPS2AndPSP`: `Sony - PlayStation 2` → ps2, and `Sony - PlayStation Portable` → `unknownSystem`.
  - `escapedQuotes`.
  - `old3aJSONStillLoads`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit** `feat: clrmamepro DATs with serial index`

---

### Task 3: Download databases from libretro-database

**Files:**
- Create: `Sources/RetromacCore/Library/DatUpdater.swift`
- Modify: `Sources/retromac-tool/main.swift` (adds `update-dats [--home DIR]`)
- Test: `Tests/RetromacCoreTests/DatUpdaterTests.swift`

**Interfaces:**
- Produces:
  - `enum DatUpdater { static let base: URL; static let sources: [SystemID: String]; static func update(store: DatStore, downloader: any Downloader, runner: any CommandRunner) async -> [(SystemID, Result<DatFile, Error>)] }`
  - `sources` maps each system to its path under `metadat/`. Wii U and Switch have no entry.

    | System | Path |
    |---|---|
    | nes | `no-intro/Nintendo - Nintendo Entertainment System.dat` |
    | snes | `no-intro/Nintendo - Super Nintendo Entertainment System.dat` |
    | genesis | `no-intro/Sega - Mega Drive - Genesis.dat` |
    | n64 | `no-intro/Nintendo - Nintendo 64.dat` |
    | psx | `redump/Sony - PlayStation.dat` |
    | ps2 | `redump/Sony - PlayStation 2.dat` |
    | saturn | `redump/Sega - Saturn.dat` |
    | gc | `redump/Nintendo - GameCube.dat` |
    | wii | `redump/Nintendo - Wii.dat` |
    | xbox | `redump/Microsoft - Xbox.dat` |

  - Each source is downloaded to a temp file and imported on its own, so one failure never blocks the others, and a failed system keeps its previous JSON.
  - CLI `update-dats` prints `<system> <N> games` or `FAIL <system> <error>`, and exits 1 on any FAIL.

- [ ] **Step 1: Write failing tests** with `FixtureDownloader`, which serves clrmamepro fixtures at the exact `base + path` URLs:
  - `updatesEverySource`: all 10 served → 10 successes, and `load()` has 10 systems.
  - `partialFailureKeepsPreviousIndex`: an existing `psx.json`, and the PS1 URL is not served → the psx result is `.failure`, `psx.json` is unchanged, and the others are updated.
  - `urlsAreEncoded`: the URL for `Sony - PlayStation 2.dat` ends with `Sony%20-%20PlayStation%202.dat`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`, then a live check.** Run `swift run retromac-tool update-dats --home <scratchpad>`. Expected: 10 lines with game counts. Those DATs stay in the scratchpad and are never committed.
- [ ] **Step 5: Commit** `feat: download game databases from libretro-database`

---

### Task 4: Disc and modern-console sniffers

**Files:**
- Create: `Sources/RetromacCore/Library/DiscSniffer.swift`, `Sources/RetromacCore/Library/SectorReader.swift`
- Test: `Tests/RetromacCoreTests/DiscSnifferTests.swift`, `Tests/RetromacCoreTests/DiscBuilders.swift`

**Interfaces:**
- Produces:
  - `struct DiscID: Equatable, Sendable { var system: SystemID; var serial: String?; var title: String? }`
  - `enum DiscSniffer { static func sniff(_ url: URL) -> Result<DiscID, DiscSniffer.Unsupported>?; struct Unsupported: Error, Equatable { var reason: String }; static let extensions: Set<String> }`. `sniff` returns nil when nothing matches, `.failure` for recognized-but-unsupported containers, and `.success` otherwise. Every read goes through `SectorReader` (FileHandle seek and read), never `Data(contentsOf:)`.
  - `extensions` = `iso gcm bin cue img chd rvz wia wbfs gcz xiso wud wux wua rpx wuhb nsp nsz xci xcz pbp`
  - `struct SectorReader { init?(url: URL); func user(sector: Int) -> Data? }`. It detects the layout:
    - 2048-byte ISO.
    - Raw 2352 with sync `00 FF×10 00`: MODE1 user data starts at +16, and MODE2 user data starts at +24 when byte +15 is 2.

**Rules, applied in order:**
1. **`.cue`:** parse the first `FILE "…" BINARY` line with a `TRACK nn MODE…` entry, and sniff that `.bin` relative to the cue.
2. **CHD:** `"MComprHD"` at 0 → `.failure("CHD images can't be identified yet — drop the .cue/.bin or .iso instead")`.
3. **GCZ:** `01 C0 0B B1` at 0 → `.failure("GCZ images aren't supported — convert to RVZ with Dolphin")`.
4. **GameCube/Wii.** The disc header is at offset 0 for `.iso`/`.gcm`, at 0x58 for RVZ/WIA (magic `RVZ\x01` or `WIA\x01`), and at 0x200 for WBFS (magic `WBFS`).
   - Wii magic `5D 1C 9E A3` at header+0x18 → wii.
   - GameCube magic `C2 33 9F 3D` at header+0x1C → gc.
   - The serial is the 4 ASCII characters at header+0. The title is the 64 bytes at header+0x20.
5. **Xbox:** `"MICROSOFT*XBOX*MEDIA"` at 0x10000, or at 0x18300000 + 0x10000 for full Redump images.
   - Walk the XDVDFS root directory: its sector is the u32 at volume descriptor +0x14, its size the u32 at +0x18. Each entry is left u16, right u16, sector u32, size u32, attr u8, name length u8, then the name. Find `default.xbe`, ignoring case.
   - Read its header: magic `XBEH`, base address u32 at 0x104, certificate address u32 at 0x118.
   - The title ID is the u32 at cert+0x08. The serial is `"\(Character(id>>24))\(Character((id>>16)&0xFF))-\(String(format: "%03d", id & 0xFFFF))"`. The title is 40 UTF-16LE characters at cert+0x0C, trimmed.
6. **Saturn:** sector 0's user data starts with `"SEGA SEGASATURN "`. The serial is 10 bytes at 0x20, trimmed. The title is 112 bytes at 0x60, trimmed.
7. **PS1/PS2:** sector 16's user data has `CD001` at offset 1. Read the root directory record (extent at PVD+156+2, size at +10) and find `SYSTEM.CNF;1`.
   - A `BOOT2 =` line → ps2. A `BOOT =` line → psx.
   - The serial is the boot file's basename up to `;`, with `_` and `.` removed, then a hyphen inserted after the 4-letter prefix: `SLUS_000.67` → `SLUS-00067`.
   - With no `SYSTEM.CNF` but PVD system identifier `PLAYSTATION` → psx, with no serial.
8. **PBP:** `00 50 42 50` at 0 → psx, with no serial.
9. **Wii U:** `WUX0` at 0 (`.wux`); `WUHB` at 0 (`.wuhb`); ELF `7F 45 4C 46` with byte 7 = `0xCA` (`.rpx`); or the extension `.wud`/`.wua` → wiiu, with no serial or title.
10. **Switch:** `PFS0` at 0 (`.nsp`/`.nsz`), or `HEAD` at 0x100 (`.xci`/`.xcz`) → switch, with no serial or title.
11. Otherwise nil.

- [ ] **Step 1: Write failing tests.** `DiscBuilders.swift` makes sparse files and writes header bytes at offsets:
  - `isoImage(systemCNF: "BOOT2 = cdrom0:\\SLUS_200.62;1")`, plus a raw-2352 MODE2 variant
  - `saturnImage(serial: "T-4305G", title:)`
  - `gcmImage(id: "GW7P", wii: false)`, plus RVZ and WBFS wrappers
  - `xisoImage(titleID: 0x4541000D, title: "Test Game", redumpOffset: Bool)`
  - `nsp()`, `xci()`, `wux()`

  The tests assert the exact `DiscID` for each, and these in particular:
  - `ps1SerialFromRawBin` → `SLUS-00067`
  - `ps2FromBoot2`
  - `xboxSerialFromTitleID` → `EA-013`
  - `cueFollowsFirstDataTrack`
  - `chdIsUnsupported` / `gczIsUnsupported` with their exact reasons
  - `loneCartridgeBinIsNil` (a Genesis-style `.bin` → nil, so the 3a path handles it)
  - `neverReadsWholeFile`: a sparse 8 GiB `.iso` with a GameCube header finishes in under 1 s
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit** `feat: disc and console sniffers using header sectors`

---

### Task 5: Clean names for games not in a database

**Files:**
- Create: `Sources/RetromacCore/Library/NameCleaner.swift`
- Test: `Tests/RetromacCoreTests/NameCleanerTests.swift`

**Interfaces:**
- Produces: `enum NameCleaner { static func clean(_ stem: String, headerTitle: String?) -> String }`
  - Underscores become spaces, and whitespace is collapsed.
  - **Parenthesized GoodTools region codes become No-Intro words:**

    | Code | Becomes |
    |---|---|
    | (U) | USA |
    | (E) | Europe |
    | (J) | Japan |
    | (W) | World |
    | (UE) / (EU) | USA, Europe |
    | (JU) / (UJ) | USA, Japan |
    | (JUE) | World |
    | (F) | France |
    | (G) | Germany |
    | (S) | Spain |
    | (I) | Italy |
    | (K) | Korea |
    | (Ch) | China |
    | (B) | Brazil |
    | (A) | Australia |
    | (PD) | Public Domain |

    Other parenthesized groups are kept as-is.
  - **Bracketed GoodTools flags:**

    | Flag | Becomes |
    |---|---|
    | `[!]` | removed |
    | `[h…]` | `[Hack]` |
    | `[T+xxx…]` / `[T-xxx…]` | `[Translation xxx]`, keeping the 3-letter language code with its first letter capitalized |
    | `[b…]` | `[Bad Dump]` |
    | `[o…]` | `[Overdump]` |
    | `[a…]` | `[Alt]` |
    | `[f…]` | `[Fixed]` |
    | `[p…]` | `[Pirate]` |
    | `[t…]` | `[Trainer]` |

    Other bracketed flags are dropped.
  - When the cleaned name without its tags is 3 characters or fewer (`disc`, `game1`, a bare serial like `SLUS_200.62`) and `headerTitle` is non-nil, the title-cased header title replaces it, and the tags are kept.
  - The result goes through `RomSniffer.sanitize`.

- [ ] **Step 1: Write failing tests:**
  - `"Super Mario Bros 3 (U) (PRG 1) [h2]"` → `"Super Mario Bros 3 (USA) (PRG 1) [Hack]"`, which is Mike's real file.
  - `"Zelda_no_Densetsu (J) [T+Eng1.0_Translator] [!]"` → `"Zelda no Densetsu (Japan) [Translation Eng]"`.
  - `"Sonic (UE) [b1]"` → `"Sonic (USA, Europe) [Bad Dump]"`.
  - `("disc", headerTitle: "FINAL FANTASY VII")` → `"Final Fantasy Vii"`. The title-casing is simple, and the test pins it.
  - `"Already Clean (USA)"` stays unchanged.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit** `feat: clean names for games not in a database`

---

### Task 6: Importer for every console

**Files:**
- Modify: `Sources/RetromacCore/Library/Importer.swift`, `Sources/RetromacCore/Library/RomSniffer.swift` (only `romExtensions` union)
- Test: `Tests/RetromacCoreTests/ImporterDiscTests.swift`

**Interfaces:**
- Consumes: `DiscSniffer`, `DiscID`, `NameCleaner`, `DatStore.lookup(_:serial:)`, `SystemID.isCartridge`
- Produces:
  - `ImportCandidate` gains `var files: [(from: URL, to: URL, move: Bool)]` (internal), the copy plan for multi-file sets.
  - Behavior below; 3a's behavior for cartridge files is unchanged.

**Analyze rules (additions):**
- `.cue` files are handled before their `.bin`s. A `.bin` referenced by a cue in the same drop or archive is consumed by that cue, so it never becomes its own candidate.
- For each file whose extension is in `DiscSniffer.extensions`, call `DiscSniffer.sniff` **before** the 64 MiB guard:
  - `.success(id)`:
    - **Name:** if there's a serial, `DatStore.lookup(id.system, serial:)` gives `.identified(system, name: entry.name)`. Otherwise it's `.unverified(system)`, named by `NameCleaner.clean(stem, headerTitle: id.title)`.
    - **Destination:** `<lib>/<system>/<name>.<ext>`.
    - **Cue sets:** the `.cue` becomes `<name>.cue`. A single `.bin` becomes `<name>.bin`; multiple become `<name> (Track N).bin`, in cue order. The cue text is rewritten with the new `FILE` names and staged as a small file.
  - `.failure(reason)` → `.unidentified(reason:)`, with destination nil (not copied).
  - `nil` → fall through to 3a's cartridge path.
- **Duplicates for large files:** a destination that already exists with the **same size** counts as a duplicate. Within a drop, two items with the same `(system, serial)` count as duplicates.
- **Archives:**
  - The `tar -tvf` precheck allows members over 64 MiB only when every oversized member's extension is in `DiscSniffer.extensions`.
  - The total is capped at 16 GiB.
  - Extracted large files are planned as `move: true`.
- **Commit:**
  - Each entry in `files` is copied (or moved) to a temp name in the destination folder, then renamed into place.
  - Collisions get ` (2)` applied to every file in the set, with the cue rewritten to match.
  - Nothing is ever moved from outside the session dir.
- **Status note:** an identified or unverified game whose system isn't installable keeps its status. The UI adds the "arrives in a later update" note in Task 7.

- [ ] **Step 1: Write failing tests** with DiscBuilders and a temp library:
  - `ps2IsoIdentifiedBySerial`: a DAT with serial `SLUS-20062` → `.identified(.ps2, name: …)`, and destination `ps2/<name>.iso`.
  - `bigImageCopiedOnceNeverLoaded`: a sparse 6 GiB GameCube ISO → analyzed in under 1 s, and committed by copy.
  - `zippedCueBinSetIsFiledTogether`: a zip of `Game (U).cue` plus `Track 1.bin` and `Track 2.bin` (raw MODE2 PS1 header) → one candidate. After commit: `psx/<Name>.cue`, `psx/<Name> (Track 1).bin` and `psx/<Name> (Track 2).bin`, with the cue's FILE lines pointing to them and the extracted bins moved (the session dir is empty afterwards).
  - `chdReportedNotCopied`.
  - `switchNamedFromFilename`: `"Game Name [0100ABCD00010000][v0].nsp"` → `.unverified(.switch)`, destination `switch/Game Name.nsp`.
  - `cartridgeBehaviorUnchanged`: the 3a ImporterTests still pass.
  - `sameSerialTwiceIsDuplicate`.
- [ ] **Step 2: Run them.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit** `feat: importer files disc and console games, cue/bin sets, large-file moves`

---

### Task 7: Games step updates

**Files:**
- Modify: `Sources/retromac/GamesModel.swift`, `Sources/retromac/Views/GamesStep.swift`

**Interfaces:**
- Consumes: `DatUpdater.update`, `Manifest.bundled().installableSystems`, `SystemID.displayName`
- Produces: `GamesModel.updateDats() async`, plus `var datProgress: String?`

**UI changes:**
- **Game databases section:**
  - There's one row per system that has a DAT source, showing "<count> games · updated <date>", where the date is the JSON's modification date.
  - An **Update Game Databases** button downloads all of them, showing "Downloading 3 of 10…". Afterwards the rows reload, and failures are listed in red.
  - **Import DAT Files…** stays as a secondary button.
  - The caption becomes "Downloaded from libretro-database on GitHub. Games not in a database are still added, with cleaned-up names."
- **Candidate rows:** a game whose system isn't installable shows, in secondary text, "<System> emulator arrives in a later update — this game is filed and waiting." Installable but unselected systems keep the 3a note.
- **Busy state:** while `busy`, a **Cancel** button cancels the analysis `Task`. Analysis checks `Task.isCancelled` between files.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run `swift build && swift test`, then `scripts/bundle.sh` and `codesign --verify --strict build/retromac.app`.** Expected: success.
- [ ] **Step 3: Commit** `feat: one-click game databases and later-update notes in the Games step`

---

### Task 8: End-to-end on Mike's Mac

Confirm with Mike before Step 2: it downloads about 12 MB of DATs into `~/retromac/dats` and writes into his library.

- [ ] **Step 1: Open `build/retromac.app`, go to Games, and click Update Game Databases.** Expected: 10 rows with counts. Compare against `swift run retromac-tool update-dats --home <scratch>` from Task 3.
- [ ] **Step 2: Drop `~/Downloads/Super Mario Bros 3 (U) (PRG 1) [h2].zip`.** Expected: unverified, as `nes/Super Mario Bros 3 (USA) (PRG 1) [Hack].nes`. A copy filed during 3a's earlier test (if any) shows as a duplicate.
- [ ] **Step 3: Have Mike drop any disc or console images he legally owns, one or more systems.** Expected: each is identified by serial, or named from its file, and filed under its system with the "arrives in a later update" note where it applies. Check the file sizes in the library against the originals, and that the originals are unchanged (`shasum` for files under 1 GB, size and mtime for larger ones).
- [ ] **Step 4: Relaunch ES-DE.** Expected: the cartridge games are listed. Other systems' folders exist, but ES-DE doesn't show them until their emulators ship.
- [ ] **Step 5: Report the results with command output.**
