# retromac Phase 3a (Importer and Games step) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users drag ROM files, folders or archives onto a new **Games** wizard step. retromac identifies each game against user-imported No-Intro DATs and copies it into the library under its canonical name. Phase 3a covers the four cartridge systems: NES, SNES, Genesis and N64.

**Architecture:** Everything lives in `RetromacCore`, so Phase 3c's inbox watcher can reuse it unchanged:
- `DatParser` and `DatStore` turn No-Intro logiqx XML into a small per-system JSON index.
- `RomSniffer` detects the system from header bytes and produces normalized bytes plus match hashes.
- `Importer` analyzes the dropped items without writing anything, then copies them on request.

The CLI and the wizard are thin shells over these. Originals the user drops are never modified, moved or deleted.

**Tech Stack:** Swift 6 and SwiftPM, as in Phases 1–2. Foundation `XMLParser`, CryptoKit `Insecure.SHA1`, `/usr/bin/tar` for archives, and SwiftUI `dropDestination`. **No new dependencies.**

**Spec:** `docs/superpowers/specs/2026-11-13-retromac-design.md`. See "Librarian", and Resolved decisions 4–5. Phase 3b (disc systems, Redump, BIOS, CHD) and 3c (inbox watcher) get their own plans.

## Decisions made in this plan (Claude's calls, left to the builder by the spec)

- **The DAT index is JSON, not SQLite.** No-Intro DATs for the four systems total about 12k entries, so a dictionary keyed by SHA-1 is enough. The spec's SQLite ingest journal belongs to 3c.
- **Some games are filed without a DAT match.** A system detected confidently from the header, with no DAT match (or no DAT imported), is filed as *unverified* in `Library/<system>/` under a cleaned-up original filename. It's still playable, and ES-DE shows it. `_Unidentified/` is only for files that look like ROMs (by extension) but whose system can't be detected. Anything else (`.txt`, `.jpg`, `.DS_Store`) is listed as "not a game file" and isn't copied.
- **Matching uses two hashes.** Candidates are matched against the SHA-1 of the normalized bytes **and** of the original bytes. That way both No-Intro's headerless and headered NES DATs work.

## Global Constraints

- Phase 1/2 constraints still apply: macOS 14+ arm64, zero third-party packages, SPDX headers, and no ROM, BIOS or DAT content in the repo or tests. Fixtures are synthetic bytes with hand-made headers.
- **Dropped originals are read-only to retromac.** Never move, rename or modify them. Archives are extracted only into a session temp dir.
- Library layout: `<libraryRoot>/<system.rawValue>/<Name>.<ext>`, plus `<libraryRoot>/_Unidentified/<file>` with a `<file>.txt` sidecar giving the reason.
- Output extensions: nes → `.nes`; snes → `.sfc` (copier header stripped); genesis → `.md`; n64 → `.z64` (big-endian).
- Filename sanitizing: replace `/` and `:` with `-`, trim whitespace, strip leading dots, and cap at 200 UTF-8 bytes before the extension.
- Files over **64 MiB** are never read into memory in 3a. They're reported as "too large for a cartridge system".
- The DAT store lives at `~/retromac/dats/<system>.json`.

## Review Focus

1. **A dropped multi-GB file** (ISO, video). Expected: skipped from its size alone, never loaded. The test is in Task 3.
2. **The same game dropped twice, or already in the library.** Expected: reported as a duplicate, with no second copy. The test is in Task 3.
3. **DAT names or filenames with `/`, `:`, leading dots or extreme length.** Expected: sanitized, never an escape from the system folder. The tests are in Tasks 2 and 3.
4. **An archive holding several ROMs, nested folders, or a corrupt archive.** Expected: each ROM is handled; a corrupt archive becomes one failed item and the other items still proceed. The test is in Task 3.
5. **The wrong DAT variant.** Expected: an N64 ByteSwapped or LittleEndian DAT is rejected with "use the BigEndian DAT", and a headered NES DAT still matches. The test is in Task 1.

---

### Task 1: DAT parsing and store

**Files:**
- Create: `Sources/RetromacCore/Library/DatParser.swift`, `Sources/RetromacCore/Library/DatStore.swift`
- Modify: `Sources/RetromacCore/Support/Paths.swift` (add `dats`)
- Test: `Tests/RetromacCoreTests/DatTests.swift`

**Interfaces:**
- Produces:
  - `struct DatEntry: Codable, Equatable, Sendable { var name: String }`. `name` is the No-Intro game name, e.g. `"Super Mario Bros. 3 (USA) (Rev 1)"`.
  - `struct DatFile: Codable, Equatable, Sendable { var system: SystemID; var source: String; var version: String; var entries: [String: DatEntry] }`. Keys are lowercase SHA-1. `source` is the header `<name>`; `version` is the header `<version>`, or `""`.
  - `enum DatError: Error, Equatable { case unknownSystem(String); case unsupportedVariant(String); case notADat }`
  - `enum DatParser { static func parse(_ data: Data) throws -> DatFile }`. This is a streaming `XMLParser` over logiqx. It reads `<header><name>` and `<version>`, plus each `<game name>` and its `<rom sha1>`. ROMs without `sha1` are skipped.
  - System mapping is by header name prefix:
    - `"Nintendo - Nintendo Entertainment System"` → nes
    - `"Nintendo - Super Nintendo Entertainment System"` → snes
    - `"Sega - Mega Drive - Genesis"` → genesis
    - `"Nintendo - Nintendo 64"` → n64, but a name containing `(ByteSwapped)` or `(LittleEndian)` throws `unsupportedVariant("use the BigEndian DAT")`.
    - Anything else throws `unknownSystem(<name>)`.
  - `Paths.dats` = `~/retromac/dats`.
  - `struct DatStore { init(paths: Paths); func importDats(_ urls: [URL], runner: any CommandRunner) throws -> [DatFile]; func load() -> [SystemID: DatFile]; func lookup(_ system: SystemID, sha1: [String]) -> DatEntry? }`
    - Each URL is a `.dat`/`.xml` file, or a `.zip` whose `.dat` entries are extracted with `/usr/bin/tar` into a temp dir and parsed.
    - Each parsed DAT **replaces** `<system>.json`, written atomically.
    - `lookup` returns the first hash that hits.

- [ ] **Step 1: Write the failing tests.** The fixtures are inline logiqx strings, built by a helper `datXML(header: String, games: [(name: String, sha1: String)]) -> Data`.

```swift
@Test func parsesNoIntroNES() throws {
    let dat = try DatParser.parse(datXML(header: "Nintendo - Nintendo Entertainment System (Headerless)",
                                         games: [("Alpha (USA)", "AA11"), ("Beta (Japan)", "bb22")]))
    #expect(dat.system == .nes)
    #expect(dat.entries == ["aa11": DatEntry(name: "Alpha (USA)"), "bb22": DatEntry(name: "Beta (Japan)")])
}
@Test func mapsAllFourSystems() throws {
    for (header, system) in [("Nintendo - Super Nintendo Entertainment System", SystemID.snes),
                             ("Sega - Mega Drive - Genesis", .genesis), ("Nintendo - Nintendo 64 (BigEndian)", .n64)] {
        #expect(try DatParser.parse(datXML(header: header, games: [])).system == system)
    }
}
@Test func rejectsByteSwappedN64() {
    #expect(throws: DatError.unsupportedVariant("use the BigEndian DAT")) {
        try DatParser.parse(datXML(header: "Nintendo - Nintendo 64 (ByteSwapped)", games: []))
    }
}
@Test func rejectsUnknownSystem() {
    #expect(throws: DatError.unknownSystem("Atari - 2600")) { try DatParser.parse(datXML(header: "Atari - 2600", games: [])) }
}
@Test func rejectsNonDat() { #expect(throws: DatError.notADat) { try DatParser.parse(Data("hello".utf8)) } }
@Test func importsDatAndZipAndReplaces() throws {
    /* write nes.dat (1 game) → importDats → load()[.nes].entries.count == 1;
       zip a second nes.dat (2 games) with tar -a → importDats → count == 2 (replaced, not merged);
       lookup(.nes, sha1: ["zz", "bb22"]) == DatEntry(name: "Beta (Japan)") */
}
```

- [ ] **Step 2: Run `swift test --filter DatTests`.** Expected: FAIL (types undefined).
- [ ] **Step 3: Implement the Produces types.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: No-Intro DAT parser and store"`

---

### Task 2: ROM detection and normalization

**Files:**
- Create: `Sources/RetromacCore/Library/RomSniffer.swift`
- Test: `Tests/RetromacCoreTests/RomSnifferTests.swift`

**Interfaces:**
- Produces:
  - `struct Sniffed: Equatable, Sendable { var system: SystemID; var normalized: Data; var hashes: [String]; var headerTitle: String?; var ext: String }`.
    - `hashes` is `[sha1(normalized), sha1(original)]`, deduplicated and lowercase.
    - `normalized` is the bytes written to the library.
    - `ext` is the output extension (see Global Constraints).
  - `enum RomSniffer { static func sniff(_ data: Data) -> Sniffed?; static let romExtensions: Set<String>; static func sanitize(_ name: String) -> String }`. `romExtensions` = `nes sfc smc md gen bin smd z64 n64 v64`.

**Detection rules, checked in this order:**
1. **NES:** bytes 0–3 are `4E 45 53 1A`. `normalized` = the original bytes, because emulators need the header. The hashes are SHA-1 of the bytes after the 16-byte header, and of the full file.
2. **N64:** the first 4 bytes are:
   - `80 37 12 40` (z64): as-is.
   - `37 80 40 12` (v64): swap each byte pair.
   - `40 12 37 80` (n64): reverse each 4-byte word.

   `normalized` = the z64 bytes. The title is bytes 0x20–0x33 of the z64.
3. **Genesis:** bytes 0x100–0x103 are `"SEGA"`. The title is the overseas name at 0x150 (48 bytes), or the domestic name at 0x120 if the overseas one is blank.
4. **SNES:**
   - If `size % 1024 == 512`, drop the first 512 bytes first.
   - Then accept if the LoROM header (base 0x7FC0) or the HiROM header (0xFFC0) has `checksum ^ complement == 0xFFFF`. Those are little-endian u16 values at base+0x1E and base+0x1C.
   - `normalized` = the bytes without the copier header. The title is the 21 bytes at the base.
5. Otherwise, nil.

Titles are ASCII, with control characters removed and whitespace trimmed. An empty title becomes nil.

- [ ] **Step 1: Write the failing tests.** These use synthetic builders `nesROM()`, `snesROM(copier: Bool, hiROM: Bool, title:)`, `genesisROM(overseas:domestic:)` and `n64ROM(order: .z64/.v64/.n64, title:)`.

```swift
@Test func detectsNESAndHashesHeaderless() {
    let rom = nesROM(prg: Data(repeating: 1, count: 16384))
    let s = try #require(RomSniffer.sniff(rom))
    #expect(s.system == .nes && s.ext == "nes" && s.normalized == rom)
    #expect(s.hashes == [sha1hex(rom.dropFirst(16)), sha1hex(rom)])
}
@Test func n64ByteOrdersNormalizeToSameZ64() {
    let z = n64ROM(order: .z64, title: "MARIO"), v = n64ROM(order: .v64, title: "MARIO"), n = n64ROM(order: .n64, title: "MARIO")
    let sz = RomSniffer.sniff(z)!, sv = RomSniffer.sniff(v)!, sn = RomSniffer.sniff(n)!
    #expect(sv.normalized == sz.normalized && sn.normalized == sz.normalized)
    #expect(sz.ext == "z64" && sv.headerTitle == "MARIO")
}
@Test func detectsGenesisOverseasTitle() { /* overseas "SONIC THE HEDGEHOG" → title "SONIC THE HEDGEHOG", ext "md"; blank overseas → domestic used */ }
@Test func snesCopierHeaderStrippedAndChecksumValidated() {
    /* snesROM(copier: true, hiROM: false, title: "SUPER GAME") → system .snes, normalized.count == raw - 512, title "SUPER GAME", ext "sfc";
       hiROM variant detected; corrupt complement → nil */
}
@Test func unknownBytesAreNil() { #expect(RomSniffer.sniff(Data(repeating: 0, count: 4096)) == nil) }
@Test func sanitizesNames() {
    #expect(RomSniffer.sanitize("  ../Evil: Name/Part  ") == "-Evil- Name-Part")
    #expect(RomSniffer.sanitize(String(repeating: "é", count: 300)).utf8.count <= 200)
}
```

- [ ] **Step 2: Run `swift test --filter RomSnifferTests`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: cartridge ROM detection and normalization"`

---

### Task 3: Importer

**Files:**
- Create: `Sources/RetromacCore/Library/Importer.swift`
- Test: `Tests/RetromacCoreTests/ImporterTests.swift`

**Interfaces:**
- Consumes: `DatStore`, `RomSniffer`, `Paths`, `CommandRunner`, `SystemID`
- Produces:
  - `enum ImportStatus: Equatable, Sendable { case identified(SystemID, name: String); case unverified(SystemID); case duplicate(SystemID); case unidentified(reason: String); case notAGame; case failed(String) }`
  - `struct ImportCandidate: Identifiable, Equatable, Sendable { let id: UUID; var source: String; var status: ImportStatus; var destination: URL? }`. `source` is the display path, `archive.zip › inner.nes` for archive members. `destination` is nil for `notAGame` and `failed`.
  - `final class ImportSession: Sendable`. It owns a temp dir and holds each candidate's normalized bytes on disk. `deinit` removes the temp dir.
  - `struct Importer { init(libraryRoot: URL, dats: DatStore, runner: any CommandRunner); func analyze(_ urls: [URL]) -> (ImportSession, [ImportCandidate]); func commit(_ session: ImportSession, _ candidates: [ImportCandidate]) throws -> [ImportCandidate] }`
    - `analyze` writes **nothing** under `libraryRoot`.
    - `commit` copies `identified`, `unverified` and `unidentified` candidates. `unidentified` ones also get a `.txt` sidecar. It returns the candidates with their final destinations, after resolving collisions at commit time.

**Analyze rules:**
- Directories are walked recursively. Hidden files and package contents are skipped.
- `.zip` and `.7z` are extracted with `/usr/bin/tar -xf` into the session dir, and each extracted file is processed as if dropped. An extraction error becomes one `failed("couldn't open archive: <stderr first line>")` for that archive.
- Files over 64 MiB become `unidentified(reason: "too large for a cartridge system")` if their extension is in `romExtensions`. Otherwise they're `notAGame`. Either way, they're never read.
- `RomSniffer.sniff` returns nil:
  - extension in `romExtensions` → `unidentified(reason: "not a recognized NES, SNES, Genesis or N64 image")`
  - otherwise → `notAGame`
- On a sniff hit:
  - **DAT lookup hit:** `identified(system, name: entry.name)`, destination `<lib>/<system>/<sanitize(name)>.<ext>`.
  - **Miss:** `unverified(system)`, destination `<lib>/<system>/<sanitize(source filename stem)>.<ext>`.
- **Duplicates:**
  - A destination that already exists with an equal SHA-1 of its contents becomes `duplicate(system)`.
  - Two dropped items with the same normalized SHA-1 count as one: the second becomes `duplicate`.
- **Collisions:** a destination that exists with **different** content gets ` (2)`, ` (3)`… before the extension.

- [ ] **Step 1: Write the failing tests.** These use the Task 1 and Task 2 builders and a temp library.

```swift
@Test func identifiesFromDatAndCommits() throws { /* DAT maps sha1(headerless nes) → "Alpha (USA)"; analyze([file]) → .identified(.nes, name: "Alpha (USA)"), destination lib/nes/Alpha (USA).nes; library untouched until commit; after commit file bytes == original */ }
@Test func unverifiedWithoutDat() throws { /* no DATs; "my game!.sfc" with copier header → .unverified(.snes), destination lib/snes/my game!.sfc with 512 bytes fewer */ }
@Test func n64V64IsWrittenAsZ64() throws { /* "x.v64" → destination ends ".z64", committed bytes == z64 normalized */ }
@Test func archiveMembersAreImported() throws { /* zip containing a/one.nes and b/two.md → two candidates, sources "pack.zip › a/one.nes" etc. */ }
@Test func corruptArchiveFailsAloneOthersProceed() throws { /* bad.zip (random bytes) + good.nes → [.failed(…), .identified/.unverified] */ }
@Test func duplicatesAreNotCopiedTwice() throws { /* same rom dropped twice → second .duplicate; commit; analyze again → .duplicate */ }
@Test func differentContentSameNameGetsSuffix() throws { /* existing lib/nes/Alpha (USA).nes with other bytes → committed as "Alpha (USA) (2).nes" */ }
@Test func largeFilesAreSkippedUnread() throws { /* sparse 100 MiB "movie.mp4" (FileHandle.truncate) → .notAGame; sparse "huge.bin" → .unidentified(reason: "too large for a cartridge system") */ }
@Test func nonGameAndUnrecognizedFiles() throws { /* readme.txt → .notAGame (no destination); garbage "x.nes" → .unidentified; commit writes lib/_Unidentified/x.nes and x.nes.txt containing the reason */ }
@Test func originalsAreNeverModified() throws { /* record sha + mtime of every dropped file before analyze/commit; equal after */ }
@Test func datNameIsSanitized() throws { /* DAT name "Evil: ../Name" → destination lib/nes/Evil- ..-Name.nes stays inside lib/nes */ }
```

- [ ] **Step 2: Run `swift test --filter ImporterTests`.** Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: importer with analyze-then-commit, archives, duplicates and sidecars"`

---

### Task 4: CLI commands

**Files:**
- Modify: `Sources/retromac-tool/main.swift`

**Interfaces:**
- Produces:
  - `retromac-tool import-dat FILE... [--home DIR]`. It prints one line per DAT: `<system> <source> <version> <N> games`, or `FAIL <file> <error>`. It exits 1 on any FAIL.
  - `retromac-tool import-games PATH... [--home DIR] [--library DIR] [--dry-run]`.
    - It analyzes, then prints one line per candidate: `identified <system> <name>`, `unverified <system> <dest filename>`, `duplicate <system> <dest filename>`, `unidentified <reason> <source>`, `skip <source>` or `FAIL <source> <reason>`.
    - Without `--dry-run`, it commits. The library defaults to `profile.libraryRoot` when `~/retromac/profile.json` exists, else `paths.defaultLibraryRoot`.

- [ ] **Step 1: Implement both commands.**
- [ ] **Step 2: Smoke test with synthetic files in the scratchpad.** Write a fake NES ROM and a two-game DAT with `printf`/`python3`. Run `swift run retromac-tool import-dat <dat> --home <tmp>`, then `import-games <rom> --home <tmp> --dry-run`. Expected: `nes … 2 games`, then `identified nes <name>`, and nothing written. Run again without `--dry-run`. Expected: the file exists at `<tmp>/retromac/Library/nes/<name>.nes`.
- [ ] **Step 3: Commit:** `git add -A && git commit -m "feat: import-dat and import-games commands"`

---

### Task 5: Games wizard step

**Files:**
- Create: `Sources/retromac/Views/GamesStep.swift`, `Sources/retromac/GamesModel.swift`
- Modify: `Sources/retromac/WizardModel.swift` (add `.games` after `.apply`, titled "Games"), `Sources/retromac/RetromacApp.swift` (footer: Next on `.apply` goes to `.games`; Done and Open ES-DE move to `.games`)

**Interfaces:**
- Consumes: `DatStore`, `Importer`, `ImportCandidate`, `ImportStatus`, `RomSniffer.romExtensions`, `WizardModel.profile.libraryRoot`, `WizardModel.profile.systems`
- Produces: `@Observable @MainActor final class GamesModel` with:
  - `var dats: [SystemID: DatFile]`
  - `var candidates: [ImportCandidate]`
  - `var busy: Bool`
  - `var message: String?`
  - `func importDats(_ urls: [URL])`
  - `func analyze(_ urls: [URL]) async`, which runs `Importer.analyze` off the main actor
  - `func commit() async`
  - `func clear()`

**GamesStep layout:**
- **Game databases.** One row per system: "NES — No-Intro 2026-10-01 · 4,213 games", or "Not imported". There's an **Import DAT Files…** button (an `NSOpenPanel` that allows multiple `.dat`, `.xml` and `.zip` files). A caption reads: "Download the No-Intro DATs for these systems from DAT-o-MATIC (datomatic.no-intro.org), then import them here. Without them, games are still added, but under their file names." Import errors show inline.
- **Drop zone.** A dashed rounded rectangle, 140 pt tall, reading "Drop games, folders or .zip files here". It uses `.dropDestination(for: URL.self)` and highlights while targeted. A **Choose Files…** button sits beside it, as an `NSOpenPanel` for files and directories with multiple selection.
- **Candidate list.** Each row shows a status icon, the source and the result text:
  - **identified:** a green check, then "→ NES · Alpha (USA)"
  - **unverified:** a yellow dot, then "→ NES · <file> (not in database)"
  - **duplicate:** gray, "already in library"
  - **unidentified:** orange, "→ _Unidentified (<reason>)"
  - **notAGame:** gray, "not a game file"
  - **failed:** red, with the reason

  If an identified or unverified game's system isn't in `profile.systems`, the row also says "<System> isn't set up — enable it on the Systems step". The import itself still goes ahead.
- **Actions:**
  - **Add N Games**, where N counts the identified, unverified and unidentified candidates. It commits, then replaces the list with the results and says "Added N games. They appear in ES-DE the next time it starts."
  - **Clear**.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Run `swift build && swift test`.** Expected: success.
- [ ] **Step 3: Run `scripts/bundle.sh`, then `codesign --verify --strict build/retromac.app`.** Expected: exit 0.
- [ ] **Step 4: Commit:** `git add -A && git commit -m "feat: Games step with DAT import and drag-and-drop"`

---

### Task 6: End-to-end on Mike's Mac

These steps write into Mike's real library. Each one is reversible by deleting the imported files, and **dropped originals are never touched**. Confirm with Mike before Step 2.

- [ ] **Step 1: Mike downloads the No-Intro DATs for NES, SNES, Genesis and N64 from DAT-o-MATIC.** Claude doesn't fetch them, per the spec.
- [ ] **Step 2: In `build/retromac.app` › Games, import the DATs.** Expected: four rows with game counts.
- [ ] **Step 3: Drop `~/Downloads/Super Mario Bros 3 (U) (PRG 1) [h2].zip`.** Expected: it's a hacked dump (`[h2]`), so it should read **unverified** with no DAT match. Add it. Expected: `~/retromac/Library/nes/Super Mario Bros 3 (U) (PRG 1) [h2].nes` exists, and the zip in Downloads is unchanged (`shasum` before and after).
- [ ] **Step 4: Drop a clean, legally owned dump if Mike has one.** Expected: **identified** under its No-Intro name.
- [ ] **Step 5: Relaunch ES-DE.** Expected: the imported games are listed under their systems.
- [ ] **Step 6: Report the results to Mike with command output.**
