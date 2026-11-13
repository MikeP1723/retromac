# retromac Phase 1 (Spine) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A SwiftUI app plus a CLI that install RetroArch, ES-DE, and FOSS cores for NES, SNES, Genesis, and N64 from pinned upstream URLs, then render display-aware and controller-aware configs from a single `profile.json`, backing up and never clobbering user config.

**Architecture:** All logic lives in the `RetromacCore` SwiftPM library: profile model, manifest and license policy, config merge, backup, display rules, controller autoconfig, renderer, applier, and installer. Two thin executables sit on top. `retromac` is the SwiftUI wizard. `retromac-tool` is a CLI used to pin the manifest and run headless end-to-end applies. The renderer is a pure function from `(Profile, Manifest, DisplayRules, Paths)` to `[RenderedFile]`. Only the `Applier` and `Installer` touch disk.

**Tech Stack:** Swift 6 (tools-version 6.0), SwiftPM, SwiftUI, GameController.framework, CryptoKit, Swift Testing (`import Testing`). There are **zero third-party packages.** System tools: `/usr/bin/hdiutil`, `/usr/bin/tar` (bsdtar: zip and 7z), `/usr/bin/ditto`, `/usr/bin/codesign`.

**Spec:** `docs/superpowers/specs/2026-11-13-retromac-design.md`. This plan covers the spec's **Phase 1 (Spine)** only. Phases 2–6 (librarian, share, standalones, Rosetta/detect-only, polish) each get their own plan.

**Deferred from the spec's Phase 1 wizard to Phase 6 (Polish):** player-order confirmation, audio output selection, boot-to-ES-DE, and guided BT pairing. Phase 1 only *detects* controllers that are already paired.

## Global Constraints

- Platform: macOS 14.0 minimum deployment, **arm64 only**, ad-hoc signed. Package `swift-tools-version:6.0`.
- Zero third-party Swift package dependencies in Phase 1. CI enforces this through `scripts/allowed-deps.txt`, which is empty.
- Every Swift source file starts with `// SPDX-License-Identifier: GPL-3.0-or-later`.
- The repo license is GPL-3.0-or-later. `LICENSE` is the verbatim text from `https://www.gnu.org/licenses/gpl-3.0.txt`.
- Runtime-installed component SPDX allowlist: `GPL-2.0-only, GPL-2.0-or-later, GPL-3.0-only, GPL-3.0-or-later, LGPL-2.1-or-later, LGPL-3.0-or-later, AGPL-3.0-only, AGPL-3.0-or-later, MPL-2.0, MIT, BSD-2-Clause, BSD-3-Clause, Zlib, Apache-2.0`.
- Vendored or linked allowlist (GPLv3-compatible only): the runtime list minus `GPL-2.0-only`. Phase 1 vendors nothing.
- Manifest arch rule: `arm64` or `universal`. `x86_64` is allowed only with `"rosetta": true`.
- All third-party binaries are downloaded from **official upstream URLs** and verified by sha256. Nothing is re-hosted.
- The repo, tests, and README contain no ROM, BIOS, firmware, key, or No-Intro/Redump DAT content or links. Fixtures are synthetic bytes.
- retromac state lives at `~/retromac/` (`profile.json`, `state.json`, `backups/`, `Library/`).
- Every write to an existing file is preceded by a timestamped backup. Writes are refused while RetroArch or ES-DE is running.
- Product name in UI and identifiers: `retromac` (lowercase). Bundle ID: `local.retromac`.
- Generated whole files start with a "Managed by retromac — edits will be overwritten" comment in the file's comment syntax.

## Review Focus

1. **Applying while RetroArch or ES-DE is running.** Both rewrite their config on exit and would silently undo the apply. Expected: apply refuses with `ApplyError.appRunning`, and no file is touched. The test is in Task 5.
2. **User's existing `retroarch.cfg`** with comments, blank lines, unquoted values, CRLF line endings, or duplicate keys. Expected: every non-owned byte is preserved. An owned key is replaced at its first occurrence, and later duplicates of that key are removed. The test is in Task 2.
3. **Interrupted or corrupted download** (sha mismatch, truncated file). Expected: nothing is installed or extracted, temp files are removed, and a re-run starts clean. The test is in Task 6.
4. **Paths containing spaces.** `Application Support` always contains one. Expected: the global shader preset `#reference` and every generated path are correctly quoted. The test is in Task 5.
5. **Re-running apply with an unchanged profile.** Expected: zero files are rewritten, no backup snapshot is created, and the report lists everything as unchanged. The test is in Task 5.

---

### Task 1: Package scaffold, manifest model, license/arch policy, CI

**Files:**
- Create: `Package.swift`, `LICENSE`, `README.md`, `THIRD_PARTY_NOTICES.md`, `.gitignore`
- Create: `Sources/RetromacCore/Model/SystemID.swift`, `Sources/RetromacCore/Manifest/Manifest.swift`, `Sources/RetromacCore/Manifest/ManifestPolicy.swift`, `Sources/RetromacCore/Support/Resources.swift`, `Sources/RetromacCore/Support/Paths.swift`
- Create: `Sources/retromac/main.swift` (placeholder `print("retromac")`, replaced in Task 8), `Sources/retromac-tool/main.swift` (placeholder, replaced in Task 7)
- Create: `.github/workflows/ci.yml`, `scripts/check-deps.sh`, `scripts/allowed-deps.txt` (empty)
- Test: `Tests/RetromacCoreTests/ManifestPolicyTests.swift`, `Tests/RetromacCoreTests/PathsTests.swift`

**Interfaces:**
- Produces:
  - `enum SystemID: String, Codable, CaseIterable, Sendable { case nes, snes, genesis, n64 }`
  - `enum Arch: String, Codable, Sendable { case arm64, universal, x86_64 }`
  - `struct AppEntry: Codable, Equatable, Sendable { id: String; version: String; url: URL; sha256: String; license: String; arch: Arch; rosetta: Bool; appName: String; bundleID: String }` (`appName` is e.g. `"RetroArch.app"`. Format is always dmg.)
  - `struct CoreEntry: Codable, Equatable, Sendable { id: String; system: SystemID; libraryName: String; file: String; url: URL; sha256: String; license: String; arch: Arch; rosetta: Bool }` (`file` is the dylib name inside the archive. Archive format comes from the URL extension, `.zip` or `.7z`.)
  - `struct Manifest: Codable, Equatable, Sendable { schemaVersion: Int; apps: [AppEntry]; cores: [CoreEntry]; static func bundled() throws -> Manifest; func core(for: SystemID) -> CoreEntry? }`
  - `enum LicensePolicy { static let runtimeAllowed: Set<String>; static let vendoredAllowed: Set<String> }`
  - `enum ManifestPolicy { static func violations(_ m: Manifest) -> [String] }` (empty means compliant)
  - `enum Resources { static func url(_ name: String, ext: String) -> URL? }` checks `Bundle.main` first, then `Bundle.module`. **Gotcha:** SwiftPM's `Bundle.module` looks for `retromac_RetromacCore.bundle` at the `.app` *root*, which breaks codesign. The app bundle copies the JSON resources into `Contents/Resources` directly (Task 8), so `Bundle.main` must be tried first.
  - `struct Paths: Sendable { init(home: URL, applications: URL = URL(filePath: "/Applications")) }` with `retromacRoot` (`~/retromac`), `profile`, `state`, `backups`, `defaultLibraryRoot` (`~/retromac/Library`), `retroarchSupport` (`~/Library/Application Support/RetroArch`), `retroarchConfig` (`…/config/retroarch.cfg`), `retroarchCores` (`…/cores`), `retroarchAutoconfigMFi` (`…/autoconfig/mfi`), `func coreOverride(libraryName: String) -> URL` (`…/config/<name>/<name>.cfg`), `globalShaderPreset` (`…/config/global.slangp`), `retroarchShadersSlang` (`…/shaders/shaders_slang`), `esdeSettings` (`~/ES-DE/settings/es_settings.xml`), `esdeCustomSystems` (`~/ES-DE/custom_systems/es_systems.xml`), `applications`. Task 7 verifies the RetroArch and ES-DE paths against a real install. If any differ, that task changes them here.

- [ ] **Step 1: Write `Package.swift`.** Products: library `RetromacCore`, executables `retromac` and `retromac-tool`, both depending on `RetromacCore`. Test target `RetromacCoreTests`. `RetromacCore` resources: `.copy("Resources")`, with the directory created holding a `.gitkeep`. Platforms: `.macOS(.v14)`.

- [ ] **Step 2: Write the failing tests**

```swift
@Test func compliantManifestHasNoViolations() {
    #expect(ManifestPolicy.violations(.fixture()).isEmpty)
}
@Test func rejectsNonFreeLicense() {
    var m = Manifest.fixture(); m.cores[0].license = "LicenseRef-NonCommercial"
    #expect(ManifestPolicy.violations(m) == ["mesen: license LicenseRef-NonCommercial not in runtime allowlist"])
}
@Test func rejectsUnmarkedX86() {
    var m = Manifest.fixture(); m.apps[0].arch = .x86_64
    #expect(ManifestPolicy.violations(m) == ["retroarch: x86_64 requires rosetta: true"])
}
@Test func allowsMarkedX86() {
    var m = Manifest.fixture(); m.apps[0].arch = .x86_64; m.apps[0].rosetta = true
    #expect(ManifestPolicy.violations(m).isEmpty)
}
@Test func rejectsBadSha() {
    var m = Manifest.fixture(); m.cores[0].sha256 = "UNPINNED"
    #expect(ManifestPolicy.violations(m) == ["mesen: sha256 must be 64 lowercase hex chars"])
}
@Test func rejectsNonHTTPS() {
    var m = Manifest.fixture(); m.apps[0].url = URL(string: "http://example.org/a.dmg")!
    #expect(ManifestPolicy.violations(m) == ["retroarch: url must be https"])
}
@Test func vendoredAllowlistExcludesGPL2Only() {
    #expect(!LicensePolicy.vendoredAllowed.contains("GPL-2.0-only"))
    #expect(LicensePolicy.runtimeAllowed.contains("GPL-2.0-only"))
}
@Test func pathsResolveUnderHome() {
    let p = Paths(home: URL(filePath: "/tmp/h"))
    #expect(p.retroarchConfig.path == "/tmp/h/Library/Application Support/RetroArch/config/retroarch.cfg")
    #expect(p.coreOverride(libraryName: "Mesen").path == "/tmp/h/Library/Application Support/RetroArch/config/Mesen/Mesen.cfg")
    #expect(p.esdeCustomSystems.path == "/tmp/h/ES-DE/custom_systems/es_systems.xml")
}
```

`Manifest.fixture()` lives in `Tests/RetromacCoreTests/Fixtures.swift`. It contains one app `retroarch` (`universal`, `GPL-3.0-or-later`, `https://example.org/RetroArch.dmg`, sha of 64 `a`s, appName `RetroArch.app`, bundleID `com.libretro.dist.RetroArch`), one app `esde` (`arm64`, `MIT`, appName `ES-DE.app`, bundleID `org.es-de.frontend`), and one core per system: `mesen` / `Mesen` / `mesen_libretro.dylib`, `bsnes` / `bsnes` / `bsnes_libretro.dylib`, `blastem` / `BlastEm` / `blastem_libretro.dylib`, `mupen64plus_next` / `Mupen64Plus-Next` / `mupen64plus_next_libretro.dylib`. Every core is `arm64`, `GPL-3.0-or-later`, with zip URLs on `https://example.org/`. Later tasks reuse it.

- [ ] **Step 3: Run `swift test`.** Expected: FAIL to compile (types undefined).

- [ ] **Step 4: Implement the Produces types.** Violation strings are exactly `"<id>: <reason>"` as asserted. Run checks in the order license, arch, sha, url, and report all violations. `bundled()` decodes `Resources.url("manifest", ext: "json")` and throws `CocoaError(.fileNoSuchFile)` if it's missing. That's expected until Task 7.

- [ ] **Step 5: Run `swift test`.** Expected: all pass.

- [ ] **Step 6: Write the repo scaffolding.**
  - `LICENSE`: GPLv3 text, fetched with `curl -fsSL https://www.gnu.org/licenses/gpl-3.0.txt -o LICENSE`.
  - `README.md` sections:
    - What it is, in one paragraph.
    - Build: `swift build`, `scripts/bundle.sh`.
    - "Opening an unsigned app": macOS 15+ → System Settings › Privacy & Security › **Open Anyway**.
    - License.
    - "retromac does not provide games, BIOS, firmware, or keys".
    - No links to any ROM sources.
  - `THIRD_PARTY_NOTICES.md`: "Phase 1 vendors no third-party code". It also lists the runtime-downloaded components with their upstream URLs and licenses, filled in Task 7.
  - `.gitignore`: `.build/`, `build/`, `.swiftpm/`.

- [ ] **Step 7: Write `scripts/check-deps.sh`** (`set -euo pipefail`). It runs `swift package show-dependencies --format flatlist`. It exits 1, listing the offenders, if any dependency name is missing from `scripts/allowed-deps.txt`. Run it. Expected: exit 0, no output.

- [ ] **Step 8: Write `.github/workflows/ci.yml`.** On push and pull_request, run `macos-latest` with checkout, `swift test`, and `scripts/check-deps.sh`.

- [ ] **Step 9: Commit:** `git add -A && git commit -m "feat: package scaffold, manifest model, license and arch policy"`

---

### Task 2: RetroArch config merge, ES-DE settings merge, backups

**Files:**
- Create: `Sources/RetromacCore/Config/RetroArchConfig.swift`, `Sources/RetromacCore/Config/ESDESettings.swift`, `Sources/RetromacCore/Config/BackupStore.swift`
- Test: `Tests/RetromacCoreTests/RetroArchConfigTests.swift`, `Tests/RetromacCoreTests/ESDESettingsTests.swift`, `Tests/RetromacCoreTests/BackupStoreTests.swift`

**Interfaces:**
- Produces:
  - `enum RetroArchConfig { static func merge(existing: String, owned: [String: String]) -> String }`. Owned values are written as `key = "value"`. New keys are appended in sorted order, each followed by `\n`.
  - `enum ESDESettings { static func merge(existing: String?, romDirectory: String) -> String }`
  - `struct BackupStore { init(root: URL, home: URL, now: () -> Date = Date.init); func snapshot(_ files: [URL]) throws -> URL?; func restore(_ snapshot: URL) throws; func list() throws -> [URL] }`
    - `snapshot` copies each *existing* file to `root/<yyyyMMdd-HHmmss>/<path relative to home>`. It returns nil if no listed file exists.
    - `list` is sorted newest first.
    - `restore` copies every file in the snapshot back to `home/<relative path>`, overwriting.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func replacesOwnedKeyPreservingEverythingElse() {
    let input = "# user comment\nvideo_fullscreen = \"false\"\n\nmenu_driver = \"ozone\"\n"
    #expect(RetroArchConfig.merge(existing: input, owned: ["video_fullscreen": "true"])
        == "# user comment\nvideo_fullscreen = \"true\"\n\nmenu_driver = \"ozone\"\n")
}
@Test func appendsMissingKeysSorted() {
    #expect(RetroArchConfig.merge(existing: "a = \"1\"\n", owned: ["z": "2", "m": "3"])
        == "a = \"1\"\nm = \"3\"\nz = \"2\"\n")
}
@Test func handlesUnquotedAndCRLFAndDuplicates() {
    let input = "video_fullscreen = false\r\nx = \"1\"\r\nvideo_fullscreen = \"false\"\r\n"
    #expect(RetroArchConfig.merge(existing: input, owned: ["video_fullscreen": "true"])
        == "video_fullscreen = \"true\"\r\nx = \"1\"\r\n")
}
@Test func emptyExistingProducesOwnedOnly() {
    #expect(RetroArchConfig.merge(existing: "", owned: ["a": "1"]) == "a = \"1\"\n")
}
@Test func doesNotMatchKeyPrefix() {
    #expect(RetroArchConfig.merge(existing: "video_fullscreen_x = \"1\"\n", owned: ["video_fullscreen": "true"])
        == "video_fullscreen_x = \"1\"\nvideo_fullscreen = \"true\"\n")
}
@Test func esdeReplacesROMDirectoryLine() {
    let input = "<?xml version=\"1.0\"?>\n<bool name=\"X\" value=\"true\" />\n<string name=\"ROMDirectory\" value=\"/old\" />\n"
    #expect(ESDESettings.merge(existing: input, romDirectory: "/Users/me/retromac/Library")
        == "<?xml version=\"1.0\"?>\n<bool name=\"X\" value=\"true\" />\n<string name=\"ROMDirectory\" value=\"/Users/me/retromac/Library\" />\n")
}
@Test func esdeCreatesFileWhenMissing() {
    #expect(ESDESettings.merge(existing: nil, romDirectory: "/a b/&c")
        == "<?xml version=\"1.0\"?>\n<string name=\"ROMDirectory\" value=\"/a b/&amp;c\" />\n")
}
@Test func snapshotAndRestoreRoundTrip() throws { /* temp home; write home/x/a.cfg = "1"; snapshot → non-nil; overwrite with "2"; restore → "1" */ }
@Test func snapshotOfNoExistingFilesIsNil() throws { /* temp home; snapshot([home/missing]) == nil; backups dir has no subdirectories */ }
```

- [ ] **Step 2: Run `swift test`.** Expected: FAIL (types undefined).

- [ ] **Step 3: Implement.**
  - `RetroArchConfig.merge`:
    - Line-based. Detect the line terminator: `\r\n` if present, else `\n`.
    - A line matches key `k` when its text before the first `=`, trimmed, equals `k`.
    - Replace the first match, drop later matches for that key, and append missing keys sorted.
    - Ensure a trailing terminator.
  - `ESDESettings.merge`:
    - Line-based. **Gotcha:** `es_settings.xml` has no single root element, so `XMLDocument` rejects it.
    - Match on the line containing `name="ROMDirectory"`. Replace it, or append it if absent.
    - XML-escape the value (`&` `<` `>` `"`).
    - Missing file: header `<?xml version="1.0"?>` plus the line.

- [ ] **Step 4: Run `swift test`.** Expected: all pass.

- [ ] **Step 5: Commit:** `git commit -am "feat: config merge for RetroArch and ES-DE, backup store"` (add new files first)

---

### Task 3: Display profile, optics, display rules

**Files:**
- Create: `Sources/RetromacCore/Model/Profile.swift`, `Sources/RetromacCore/Model/Controller.swift`, `Sources/RetromacCore/Display/Optics.swift`, `Sources/RetromacCore/Display/DisplayRules.swift`, `Sources/RetromacCore/Resources/display_rules.json`
- Test: `Tests/RetromacCoreTests/DisplayTests.swift`

**Interfaces:**
- Consumes: `SystemID`, `Resources` (Task 1)
- Produces:
  - `enum Look: String, Codable, CaseIterable, Sendable { case crisp, crt, smooth }`
  - `enum FacePolicy: String, Codable, CaseIterable, Sendable { case position, label }`
  - `struct DisplayProfile: Codable, Equatable, Sendable { var widthPx: Int; var heightPx: Int; var refreshHz: Double; var hdr: Bool; var vrr: Bool; var diagonalInches: Double; var distanceInches: Double }`
  - `struct Profile: Codable, Equatable, Sendable { var display: DisplayProfile; var look: Look; var systems: Set<SystemID>; var controllers: [ControllerProfile]; var facePolicy: FacePolicy; var libraryRoot: URL; static func load(from: URL) throws -> Profile; func save(to: URL) throws }`. `save` writes pretty-printed, sorted-keys JSON atomically and creates the parent directory.
  - In `Sources/RetromacCore/Model/Controller.swift`: `enum ControllerKind: String, Codable, Sendable { case xbox, playstation, nintendo, generic; init(productCategory: String) }`. Matching is case-insensitive substring: "xbox" → xbox; "dualsense" or "dualshock" → playstation; "switch pro" or "pro controller" → nintendo; anything else → generic.
  - Also in that file: `struct ControllerProfile: Codable, Equatable, Sendable { var deviceName: String; var kind: ControllerKind }` (`deviceName` is `GCController.vendorName`).
  - `enum Optics { static func pixelsPerDegree(_ d: DisplayProfile) -> Double }`. With `a = widthPx/heightPx`, physical width `w = diag·a/√(a²+1)`, `fov = 2·atan(w/2 / distance)` in degrees, and `ppd = widthPx / fov`.
  - `struct ShaderPreset: Codable, Equatable, Sendable { var path: String; var license: String }` (`path` is relative to `shaders_slang/`)
  - `struct ShaderTier: Codable, Equatable, Sendable { var minHeightPx: Int; var maxPPD: Double?; var preset: ShaderPreset }`
  - `struct DisplayRules: Codable, Equatable, Sendable { var crtTiers: [ShaderTier]; var smoothPreset: ShaderPreset; var runAheadSystems: Set<SystemID>; static func bundled() throws -> DisplayRules; func shaderPreset(for: DisplayProfile, look: Look) -> ShaderPreset? }`
    - crisp → nil.
    - smooth → `smoothPreset`.
    - crt → the first tier where `heightPx >= minHeightPx` and (`maxPPD == nil` or `ppd <= maxPPD`), else nil.

`display_rules.json` exact content:
```json
{
  "crtTiers": [
    { "minHeightPx": 2160, "maxPPD": 100, "preset": { "path": "crt/crt-guest-advanced.slangp", "license": "GPL-2.0-or-later" } },
    { "minHeightPx": 1080, "maxPPD": null, "preset": { "path": "crt/crt-easymode.slangp", "license": "GPL-2.0-or-later" } }
  ],
  "smoothPreset": { "path": "interpolation/sharp-bilinear-simple.slangp", "license": "GPL-2.0-or-later" },
  "runAheadSystems": ["nes", "snes", "genesis"]
}
```
Task 7 verifies that the paths exist and that the licenses match the shader file headers.

- [ ] **Step 1: Write the failing tests**

```swift
let tv65_4k = DisplayProfile(widthPx: 3840, heightPx: 2160, refreshHz: 120, hdr: true, vrr: true, diagonalInches: 65, distanceInches: 72)
let tv55_4k_far = DisplayProfile(widthPx: 3840, heightPx: 2160, refreshHz: 60, hdr: false, vrr: false, diagonalInches: 55, distanceInches: 120)
let tv55_1080 = DisplayProfile(widthPx: 1920, heightPx: 1080, refreshHz: 60, hdr: false, vrr: false, diagonalInches: 55, distanceInches: 96)
let monitor720 = DisplayProfile(widthPx: 1280, heightPx: 720, refreshHz: 60, hdr: false, vrr: false, diagonalInches: 24, distanceInches: 30)

@Test func ppdMatchesHandCalculation() {
    #expect(abs(Optics.pixelsPerDegree(tv65_4k) - 89.4) < 0.1)
    #expect(abs(Optics.pixelsPerDegree(tv55_4k_far) - 170.0) < 0.1)
}
@Test func crtTierSelection() throws {
    let r = try DisplayRules.bundled()
    #expect(r.shaderPreset(for: tv65_4k, look: .crt)?.path == "crt/crt-guest-advanced.slangp")
    #expect(r.shaderPreset(for: tv55_4k_far, look: .crt)?.path == "crt/crt-easymode.slangp")
    #expect(r.shaderPreset(for: tv55_1080, look: .crt)?.path == "crt/crt-easymode.slangp")
    #expect(r.shaderPreset(for: monitor720, look: .crt) == nil)
}
@Test func crispHasNoShaderSmoothAlwaysDoes() throws {
    let r = try DisplayRules.bundled()
    #expect(r.shaderPreset(for: tv65_4k, look: .crisp) == nil)
    #expect(r.shaderPreset(for: monitor720, look: .smooth)?.path == "interpolation/sharp-bilinear-simple.slangp")
}
@Test func everyPresetLicenseIsVendorCompatible() throws {
    let r = try DisplayRules.bundled()
    for p in r.crtTiers.map(\.preset) + [r.smoothPreset] { #expect(LicensePolicy.vendoredAllowed.contains(p.license)) }
}
@Test func profileRoundTrips() throws { /* save to temp, load, == original */ }
@Test func classifiesKnownCategories() {
    #expect(ControllerKind(productCategory: "Xbox One") == .xbox)
    #expect(ControllerKind(productCategory: "DualSense") == .playstation)
    #expect(ControllerKind(productCategory: "Switch Pro Controller") == .nintendo)
    #expect(ControllerKind(productCategory: "8BitDo Something") == .generic)
}
```

- [ ] **Step 2: Run `swift test`.** Expected: FAIL.
- [ ] **Step 3: Implement the Produces types and add `display_rules.json`.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: display profile, optics, and display rules"`

---

### Task 4: RetroArch MFi autoconfig

**Files:**
- Create: `Sources/RetromacCore/Controllers/MFiButton.swift`, `Sources/RetromacCore/Controllers/AutoconfigRenderer.swift`
- Test: `Tests/RetromacCoreTests/AutoconfigTests.swift`

**Interfaces:**
- Consumes: `FacePolicy`, `ControllerProfile`, `ControllerKind` (Task 3)
- Produces:
  - `enum MFiButton: Int { case south = 0, west = 1, select = 2, start = 3, up = 4, down = 5, left = 6, right = 7, east = 8, north = 9, l1 = 10, r1 = 11, l2 = 12, r2 = 13, l3 = 14, r3 = 15 }`. These are RetroArch's mfi driver bit indices. Task 7 verifies them against `input/drivers_joypad/mfi_joypad.m` at the pinned RetroArch tag.
  - `enum AutoconfigRenderer { static func render(_ c: ControllerProfile, policy: FacePolicy) -> String; static func fileName(for c: ControllerProfile) -> String }`. `fileName` is `deviceName` with `/` and `:` replaced by `_`, plus `.cfg`.

**Face mapping rule (from the spec):**
- `position` and every non-Xbox kind: RetroPad A←east, B←south, X←north, Y←west.
- `label` on `.xbox`: A←south, B←east, X←west, Y←north.

Fixed lines in every file:
- `input_driver = "mfi"`
- `input_device` and `input_device_display_name` = deviceName
- d-pad, select/start, l/r/l2/r2/l3/r3 from `MFiButton`
- `input_enable_hotkey_btn = "2"` and `input_exit_emulator_btn = "3"` (Select+Start exits back to ES-DE)
- Analog: `input_l_x_plus_axis = "+0"`, `input_l_x_minus_axis = "-0"`, `input_l_y_plus_axis = "+1"`, `input_l_y_minus_axis = "-1"`, `input_r_x_plus_axis = "+2"`, `input_r_x_minus_axis = "-2"`, `input_r_y_plus_axis = "+3"`, `input_r_y_minus_axis = "-3"`. Task 7 verifies these too.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func positionPolicyMapsByPosition() {
    let s = AutoconfigRenderer.render(.init(deviceName: "Xbox Wireless Controller", kind: .xbox), policy: .position)
    #expect(s.contains("input_a_btn = \"8\"")); #expect(s.contains("input_b_btn = \"0\""))
    #expect(s.contains("input_x_btn = \"9\"")); #expect(s.contains("input_y_btn = \"1\""))
}
@Test func labelPolicySwapsOnlyXbox() {
    let x = AutoconfigRenderer.render(.init(deviceName: "Xbox Wireless Controller", kind: .xbox), policy: .label)
    #expect(x.contains("input_a_btn = \"0\"")); #expect(x.contains("input_b_btn = \"8\""))
    #expect(x.contains("input_x_btn = \"1\"")); #expect(x.contains("input_y_btn = \"9\""))
    let n = AutoconfigRenderer.render(.init(deviceName: "Pro Controller", kind: .nintendo), policy: .label)
    #expect(n.contains("input_a_btn = \"8\""))
}
@Test func headerDriverAndHotkeys() {
    let s = AutoconfigRenderer.render(.init(deviceName: "DualSense Wireless Controller", kind: .playstation), policy: .position)
    #expect(s.hasPrefix("# Managed by retromac — edits will be overwritten\n"))
    #expect(s.contains("input_driver = \"mfi\"")); #expect(s.contains("input_device = \"DualSense Wireless Controller\""))
    #expect(s.contains("input_enable_hotkey_btn = \"2\"")); #expect(s.contains("input_exit_emulator_btn = \"3\""))
}
@Test func fileNameSanitized() {
    #expect(AutoconfigRenderer.fileName(for: .init(deviceName: "Pad: A/B", kind: .generic)) == "Pad_ A_B.cfg")
}
```

- [ ] **Step 2: Run `swift test`.** Expected: FAIL.
- [ ] **Step 3: Implement the Produces types.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: controller classification and mfi autoconfig"`

---

### Task 5: Profile renderer and applier

**Files:**
- Create: `Sources/RetromacCore/Render/ProfileRenderer.swift`, `Sources/RetromacCore/Render/ESDESystems.swift`, `Sources/RetromacCore/Apply/Applier.swift`
- Test: `Tests/RetromacCoreTests/RendererTests.swift`, `Tests/RetromacCoreTests/ApplierTests.swift`

**Interfaces:**
- Consumes: `Manifest`, `Paths`, `Resources` (Task 1). `RetroArchConfig`, `ESDESettings`, `BackupStore` (Task 2). `Profile`, `DisplayRules` (Task 3). `AutoconfigRenderer` (Task 4).
- Produces:
  - `struct RenderedFile: Equatable, Sendable { enum Kind: Equatable, Sendable { case retroarchKeys([String: String]); case esdeSettings(romDirectory: String); case whole(String); case directory }; var url: URL; var kind: Kind }`
  - `enum ProfileRenderer { static func render(_ p: Profile, manifest: Manifest, rules: DisplayRules, paths: Paths) -> [RenderedFile] }`
  - `struct ApplyReport: Equatable, Sendable { var written: [URL]; var unchanged: [URL]; var backup: URL? }`
  - `enum ApplyError: Error, Equatable { case appRunning(String) }`
  - `struct Applier { init(paths: Paths, bundleIDs: [String], isRunning: @escaping (String) -> Bool); func apply(_ files: [RenderedFile]) throws -> ApplyReport }`. Callers pass `manifest.apps.map(\.bundleID)`.

**Render output:**
1. `paths.retroarchConfig` → `.retroarchKeys` with these keys:
   - `video_fullscreen`=`true`
   - `video_refresh_rate`=`String(format: "%.6f", refreshHz)`
   - `vrr_runloop_enable`=`vrr`
   - `video_frame_delay_auto`=`true`
   - `video_scale_integer`=`look != .smooth`
   - `video_aspect_ratio_auto`=`true`
   - `video_shader_enable`=`preset != nil`
   - `input_joypad_driver`=`mfi`
   - `input_autodetect_enable`=`true`
2. If there's a preset: `paths.globalShaderPreset` → `.whole("# Managed by retromac — edits will be overwritten\n#reference \"<retroarchShadersSlang>/<preset.path>\"\n")`.
3. For each selected system in `rules.runAheadSystems` that has a core: `paths.coreOverride(libraryName:)` → `.whole` with the header plus `run_ahead_enabled = "true"`, `run_ahead_frames = "1"`, `run_ahead_secondary_instance = "true"`.
4. For each controller: `paths.retroarchAutoconfigMFi/<fileName>` → `.whole(AutoconfigRenderer.render…)`.
5. `paths.esdeSettings` → `.esdeSettings(romDirectory: p.libraryRoot.path)`.
6. `paths.esdeCustomSystems` → `.whole(ESDESystems.xml(for: p.systems, manifest:))`.
7. For each selected system: `p.libraryRoot/<system.rawValue>` → `.directory`.

The result is sorted by `url.path` so output is deterministic.

**`ESDESystems.xml(for:manifest:) -> String`** produces `<!-- Managed by retromac … -->` followed by `<systemList>`, with one `<system>` per selected system in `SystemID.allCases` order. Each one has `name`, `fullname`, `path` = `%ROMPATH%/<name>`, `extension`, `command label="<libraryName>"` = `%EMULATOR_RETROARCH% -L %CORE_RETROARCH%/<core.file> %ROM%`, `platform`, and `theme`. All values come from this table:

| name | fullname | extensions | platform/theme |
|---|---|---|---|
| nes | Nintendo Entertainment System | `.nes .NES .zip .ZIP` | nes |
| snes | Super Nintendo Entertainment System | `.sfc .SFC .smc .SMC .zip .ZIP` | snes |
| genesis | Sega Genesis | `.md .MD .gen .GEN .bin .BIN .smd .SMD .zip .ZIP` | genesis |
| n64 | Nintendo 64 | `.z64 .Z64 .n64 .N64 .v64 .V64 .zip .ZIP` | n64 |

**Applier algorithm:**
1. If `isRunning` returns true for any bundle ID, throw `appRunning(<id>)` before any I/O.
2. Compute each file's final content: merge for `.retroarchKeys`/`.esdeSettings` against the existing content (or empty/nil); use the given text for `.whole`.
3. A file whose final content equals what's on disk goes in `unchanged`. A `.directory` that already exists goes in `unchanged`.
4. Snapshot the existing files among the *changed* ones through `BackupStore(root: paths.backups, home:)`.
5. Write the changed files atomically, creating parent directories.

- [ ] **Step 1: Write the failing tests**

```swift
@Test func rendersRetroArchKeysForCrtOn4K() { /* profile tv65_4k, .crt, all systems → retroarchKeys["video_shader_enable"]=="true", ["vrr_runloop_enable"]=="true", ["video_refresh_rate"]=="120.000000", ["video_scale_integer"]=="true" */ }
@Test func smoothDisablesIntegerScaling() { /* .smooth → video_scale_integer == "false" */ }
@Test func runAheadOnlyForCheapCores() { /* overrides exist for Mesen, bsnes, BlastEm; none for Mupen64Plus-Next */ }
@Test func noControllersMeansNoAutoconfig() { /* controllers: [] → no file under retroarchAutoconfigMFi; render still includes retroarch.cfg */ }
@Test func shaderReferenceQuotesPathWithSpaces() {
    /* home "/tmp/my home"; .crt + tv65_4k → global preset content contains
       "#reference \"/tmp/my home/Library/Application Support/RetroArch/shaders/shaders_slang/crt/crt-guest-advanced.slangp\"" */
}
@Test func esdeSystemsOnlySelected() { /* systems [.nes, .n64] → xml contains "<name>nes</name>" and "<name>n64</name>", not "snes"; command contains "%CORE_RETROARCH%/mesen_libretro.dylib %ROM%" */ }
@Test func renderIsDeterministic() { /* render twice → equal arrays, sorted by path */ }

@Test func applyRefusesWhileAppRunning() throws {
    /* temp home with existing retroarch.cfg "x"; isRunning: { $0 == "org.es-de.frontend" }
       → throws ApplyError.appRunning("org.es-de.frontend"); retroarch.cfg still "x"; backups dir absent */
}
@Test func applyBacksUpThenWrites() throws { /* existing retroarch.cfg with "menu_driver = \"ozone\"\n" → after apply contains menu_driver line + owned keys; report.backup != nil and contains the old file */ }
@Test func reapplyIsNoOp() throws { /* apply twice with same files → second report.written.isEmpty, backup == nil */ }
```

- [ ] **Step 2: Run `swift test`.** Expected: FAIL.
- [ ] **Step 3: Implement the Produces types.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: profile renderer and applier with backups and running-app guard"`

---

### Task 6: Installer

**Files:**
- Create: `Sources/RetromacCore/Install/Downloader.swift`, `Sources/RetromacCore/Install/CommandRunner.swift`, `Sources/RetromacCore/Install/SHA256File.swift`, `Sources/RetromacCore/Install/Installer.swift`
- Test: `Tests/RetromacCoreTests/InstallerTests.swift`

**Interfaces:**
- Consumes: `Manifest`, `AppEntry`, `CoreEntry`, `Paths`, `SystemID` (Task 1)
- Produces:
  - `protocol Downloader: Sendable { func download(_ url: URL, to dest: URL) async throws }` and `struct URLSessionDownloader: Downloader`. It uses `URLSession.shared.download(from:)` and moves the result to `dest`. `file://` URLs work, and tests rely on that.
  - `protocol CommandRunner: Sendable { @discardableResult func run(_ executable: String, _ args: [String]) throws -> String }` and `struct ProcessRunner: CommandRunner`. A non-zero exit throws `InstallError.commandFailed(executable, status, stderr)`.
  - `enum SHA256File { static func hex(of: URL) throws -> String }`. Streams in 1 MiB chunks with CryptoKit.
  - `enum InstallError: Error, Equatable { case checksumMismatch(id: String, expected: String, actual: String); case commandFailed(String, Int32, String); case appNotFoundInImage(String); case fileNotFoundInArchive(String) }`
  - `struct InstallReport: Equatable, Sendable { var installed: [String]; var skipped: [String]; var warnings: [String] }`
  - `struct Installer { init(manifest: Manifest, paths: Paths, downloader: Downloader, runner: CommandRunner); func install(systems: Set<SystemID>) async throws -> InstallReport }`

**Behavior:**
- **Apps:**
  - If `paths.applications/<appName>` exists, the app is `skipped`. If its `CFBundleShortVersionString` differs from `version`, append the warning `"<id>: installed <v>, manifest pins <version>; leaving installed copy"`. The app is never replaced.
  - Otherwise: download to a temp dir, then verify sha.
  - Mount with `hdiutil attach -nobrowse -readonly -mountpoint <tmp>/mnt <dmg>`.
  - Run `ditto <mnt>/<appName> <applications>/<appName>`.
  - `hdiutil detach <mnt>` runs in a `defer`.
- **Cores**, for selected systems only:
  - Skip when `state.json` (`{"cores": {id: sha256}}`) already records this sha and the dylib exists.
  - Otherwise: download, verify sha, run `/usr/bin/tar -xf <archive> -C <tmp>/x`, and find `<file>` recursively. If it's missing, throw `fileNotFoundInArchive`.
  - Move it to `paths.retroarchCores/<file>`, then record the sha in `state.json`.
- The temp dir (`FileManager.default.url(for: .itemReplacementDirectory, …)`) is removed in a `defer` on every path. Nothing is written to `applications` or `retroarchCores` before the sha is verified.
- No quarantine stripping is needed: `URLSession` downloads in a non-sandboxed app don't carry `com.apple.quarantine`. Task 9 verifies this with `xattr`.

- [ ] **Step 1: Write the failing tests.** These use real `ProcessRunner` and `URLSessionDownloader` against `file://` fixtures built in the test:
  - **Core zip fixture:** write `fake_libretro.dylib` (bytes `"core"`) and zip it with `/usr/bin/tar -a -cf core.zip fake_libretro.dylib`.
  - **App dmg fixture:** make a folder containing `Fake.app/Contents/Info.plist` with `CFBundleShortVersionString` `1.0`, then run `hdiutil create -srcfolder <dir> -format UDZO fake.dmg`.

```swift
@Test func installsCoreAfterVerifyingSha() async throws { /* manifest core url=file://core.zip sha=actual → dylib exists in cores dir; report.installed == ["mesen"]; state.json records sha */ }
@Test func shaMismatchInstallsNothing() async throws {
    /* sha = 64 "0" → throws checksumMismatch(id: "mesen", expected: "000…", actual: <real>);
       cores dir has no fake_libretro.dylib; state.json absent */
}
@Test func secondRunSkipsInstalledCore() async throws { /* install twice → second report.skipped == ["mesen"] */ }
@Test func missingFileInArchiveThrows() async throws { /* core.file = "other.dylib" → fileNotFoundInArchive("other.dylib") */ }
@Test func installsAppFromDmg() async throws { /* applications = temp dir; app entry Fake.app → temp/Fake.app/Contents/Info.plist exists; no volume left mounted (`hdiutil info` output doesn't contain mountpoint) */ }
@Test func existingAppIsNeverReplaced() async throws { /* pre-create temp/Fake.app with version 0.9 → skipped == ["fake"], warnings == ["fake: installed 0.9, manifest pins 1.0; leaving installed copy"], file unchanged */ }
@Test func onlySelectedSystemsInstalled() async throws { /* systems [.nes] with cores for nes+snes → only mesen installed */ }
```

- [ ] **Step 2: Run `swift test --filter InstallerTests`.** Expected: FAIL.
- [ ] **Step 3: Implement the Produces types.**
- [ ] **Step 4: Run `swift test`.** Expected: all pass. The dmg tests take a few seconds.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: installer with sha256 verification, dmg and archive handling"`

---

### Task 7: `retromac-tool`, pinned manifest, real-world verification of assumed values

This task touches the network and installs real apps under a **throwaway home and applications directory**. It never touches the real `~` or `/Applications`.

**Files:**
- Modify: `Sources/retromac-tool/main.swift`
- Create: `Sources/RetromacCore/Resources/manifest.json`
- Modify (only if verification finds a mismatch): `Sources/RetromacCore/Support/Paths.swift`, `Sources/RetromacCore/Controllers/MFiButton.swift`, `Sources/RetromacCore/Controllers/AutoconfigRenderer.swift` (axes), `Sources/RetromacCore/Resources/display_rules.json`, `Sources/RetromacCore/Render/ProfileRenderer.swift` (key names)
- Modify: `THIRD_PARTY_NOTICES.md`
- Test: `Tests/RetromacCoreTests/BundledManifestTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces the CLI (manual argument parsing, no ArgumentParser):
  - `retromac-tool verify-manifest`: downloads every manifest URL to temp, prints `ok <id>` or `MISMATCH <id> expected=<> actual=<>`, and exits 1 on any mismatch or policy violation.
  - `retromac-tool install --systems nes,snes,genesis,n64 [--home DIR] [--applications DIR]`
  - `retromac-tool apply --profile FILE [--home DIR]`: renders and applies, then prints the report. It uses `NSRunningApplication` for `isRunning`.

- [ ] **Step 1: Write the failing test**

```swift
@Test func bundledManifestIsCompliant() throws {
    let m = try Manifest.bundled()
    #expect(ManifestPolicy.violations(m).isEmpty)
    #expect(Set(m.cores.map(\.system)) == Set(SystemID.allCases))
    #expect(Set(m.apps.map(\.id)) == ["retroarch", "esde"])
}
```

- [ ] **Step 2: Run `swift test --filter BundledManifestTests`.** Expected: FAIL (no manifest.json).

- [ ] **Step 3: Resolve immutable upstream URLs.**
  - **RetroArch:** latest stable macOS dmg under `https://buildbot.libretro.com/stable/<ver>/apple/osx/universal/`.
  - **ES-DE:** latest arm64 dmg from the official ES-DE releases on GitLab (`gitlab.com/es-de/emulationstation-de`).
  - **Cores:** `mesen`, `bsnes`, `blastem`, `mupen64plus_next` for macOS arm64. Prefer a versioned `stable/<ver>/…` path matching the RetroArch version.
  - **Stop and report to Mike instead of proceeding if:**
    - only a mutable `nightly/…/latest/` URL exists for any core, or
    - `blastem` has no macOS arm64 build.
  - Never ship an unpinned URL.

- [ ] **Step 4: Compute and record each entry.** Get the sha with `curl -fsSL <url> -o f && shasum -a 256 f`. Verify each license from the upstream LICENSE/COPYING file (cores: the `license` field in the core's `.info` file plus the repo LICENSE). Record the real SPDX ID. Read `libraryName` from the `.info` file's `corename`. Write `manifest.json` with `schemaVersion: 1`.

- [ ] **Step 5: Run `swift test` and `swift run retromac-tool verify-manifest`.** Expected: all tests pass, and every entry prints `ok`.

- [ ] **Step 6: Throwaway install.** Run `swift run retromac-tool install --systems nes,snes,genesis,n64 --home /tmp/rm-home --applications /tmp/rm-apps`. Expected: the report lists 2 apps and 4 cores installed. Running `file /tmp/rm-home/Library/Application\ Support/RetroArch/cores/*.dylib` shows `arm64` for every core.

- [ ] **Step 7: Verify each assumed value against the pinned upstream.** Record the evidence (file path + line, or command output) in the commit message. Fix the code and its test if anything differs.
  - (a) `CFBundleIdentifier` of both installed apps equals the manifest `bundleID`.
  - (b) RetroArch on macOS uses `~/Library/Application Support/RetroArch/{config,cores,autoconfig,shaders}`. Check the macOS default paths in RetroArch's `frontend/drivers/platform_darwin.m` at the pinned tag.
  - (c) The shaders live at `shaders/shaders_slang` (in the app bundle or the support dir). Fix `Paths.retroarchShadersSlang` to the real location. The three preset paths in `display_rules.json` exist there, and each preset's shader header license matches the recorded SPDX.
  - (d) The global preset location is the one RetroArch auto-loads (`config/global.slangp`), per `gfx/video_shader_parse.c`.
  - (e) Every owned key in Task 5 exists in `configuration.c`.
  - (f) The `MFiButton` indices and axis numbers match `input/drivers_joypad/mfi_joypad.m`, and the mfi device name matches `GCController.vendorName`.
  - (g) ES-DE on macOS reads `~/ES-DE/settings/es_settings.xml` and `~/ES-DE/custom_systems/es_systems.xml`, and its find rules resolve `%EMULATOR_RETROARCH%` to `/Applications/RetroArch.app` and `%CORE_RETROARCH%` to the cores dir. Check ES-DE's `resources/systems/macos/es_find_rules.xml`.

- [ ] **Step 8: Fill in `THIRD_PARTY_NOTICES.md`** with the runtime components, their upstream URLs, and licenses. Then commit: `git add -A && git commit -m "feat: retromac-tool and pinned manifest" -m "<verification evidence>"`

---

### Task 8: SwiftUI wizard and app bundle

**Files:**
- Modify: `Sources/retromac/main.swift` → delete. Create `Sources/retromac/RetromacApp.swift` (`@main`)
- Create: `Sources/retromac/WizardModel.swift`, `Sources/retromac/Detect/DisplayDetector.swift`, `Sources/retromac/Detect/ControllerDetector.swift`, `Sources/retromac/Detect/RunningApps.swift`
- Create: `Sources/retromac/Views/DisplayStep.swift`, `SystemsStep.swift`, `ControllersStep.swift`, `LibraryStep.swift`, `ApplyStep.swift`
- Create: `Support/Info.plist`, `scripts/bundle.sh`

**Interfaces:**
- Consumes: `Profile`, `DisplayProfile`, `Look`, `FacePolicy`, `ControllerProfile`, `ControllerKind(productCategory:)`, `Manifest.bundled()`, `DisplayRules.bundled()`, `Paths`, `Installer`, `ProfileRenderer`, `Applier`, `BackupStore`
- Produces:
  - `enum DisplayDetector { @MainActor static func detect() -> DisplayProfile }`. It uses `NSScreen.main`:
    - pixel size = `frame.size × backingScaleFactor`
    - `refreshHz` = `maximumFramesPerSecond`
    - `hdr` = `maximumPotentialExtendedDynamicRangeColorComponentValue > 1`
    - `vrr` = `minimumRefreshInterval != maximumRefreshInterval`
    - defaults: diagonal 55, distance 96
  - `enum ControllerDetector { static func detect() -> [ControllerProfile] }`. It maps `GCController.controllers()`, skipping controllers without `extendedGamepad`. It refreshes on `.GCControllerDidConnect` and `.GCControllerDidDisconnect`.
  - `enum RunningApps { static func isRunning(_ bundleID: String) -> Bool }`, via `NSRunningApplication.runningApplications(withBundleIdentifier:)`.
  - `@Observable @MainActor final class WizardModel`:
    - Holds `profile: Profile`, `step: Step` (`display, systems, controllers, library, apply`), and `log: [String]`.
    - Loads `paths.profile` if present. Otherwise it builds the profile from the detectors with look `.crisp`, all systems, policy `.position`, and library `paths.defaultLibraryRoot`.
    - `func installAndApply() async`: save the profile, then `Installer.install`, then `Applier.apply(ProfileRenderer.render…)`. Each report line goes into `log`. `ApplyError.appRunning` shows "Quit <app> and try again".
    - `func restore(_ snapshot: URL) throws`.

**Views (one per step, Back/Next navigation):**
- **Display:** shows the detected values read-only. Numeric fields for diagonal and distance in inches. A segmented picker for Look (Crisp pixels / CRT look / Smooth). Below the picker, a live line showing the chosen shader (or "none") from `DisplayRules.shaderPreset`.
- **Systems:** four toggles.
- **Controllers:** the detected list ("No controllers found — pair one in System Settings › Bluetooth, then it appears here" when empty), plus a face-button picker ("Match button position" / "Match button label (Xbox pads)").
- **Library:** path plus a "Choose…" `NSOpenPanel`.
- **Apply:** an "Install & Apply" button, a scrolling log, and a "Restore previous config" menu listing `BackupStore.list()`.

**`scripts/bundle.sh`** (`set -euo pipefail`):
1. `swift build -c release --arch arm64 --product retromac`
2. Create `build/retromac.app/Contents/{MacOS,Resources}`.
3. Copy the binary, `Support/Info.plist`, and `Sources/RetromacCore/Resources/*.json` into `Contents/Resources`.
4. `codesign --force --sign - build/retromac.app`

`Info.plist`: `CFBundleIdentifier` `local.retromac`, `CFBundleExecutable` `retromac`, `CFBundleName` `retromac`, `CFBundlePackageType` `APPL`, `LSMinimumSystemVersion` `14.0`, `CFBundleShortVersionString` `0.1.0`.

- [ ] **Step 1: Implement the Produces types and views.**
- [ ] **Step 2: Run `swift build` and `swift test`.** Expected: build succeeds, all tests pass.
- [ ] **Step 3: Run `scripts/bundle.sh && codesign --verify --strict build/retromac.app`.** Expected: exit 0.
- [ ] **Step 4: Run `open build/retromac.app`.** Walk all five steps without pressing Install. Expected:
  - The detected resolution matches System Settings › Displays.
  - Changing Look updates the shader line.
  - A paired controller appears, and it appears or disappears on connect/disconnect.
- [ ] **Step 5: Commit:** `git add -A && git commit -m "feat: SwiftUI wizard and app bundle script"`

---

### Task 9: End-to-end on the real machine

This task changes the real `/Applications`, `~/Library/Application Support/RetroArch`, and `~/ES-DE`. **Confirm with Mike before Step 2.**

- [ ] **Step 1: Pre-check.** Run `ls /Applications | grep -Ei 'retroarch|es-de'; ls ~/Library/Application\ Support/RetroArch ~/ES-DE 2>&1`. Report the output to Mike, including any existing installs that will be left in place and any configs that will be backed up.
- [ ] **Step 2: In `build/retromac.app`, choose the CRT look and all systems, then Install & Apply.** Expected:
  - The log shows apps and cores installed (or skipped with warnings) and a backup path when configs existed.
  - `xattr -l /Applications/RetroArch.app` shows no `com.apple.quarantine`.
- [ ] **Step 3: Press Install & Apply again.** Expected: everything is reported unchanged and no new backup is listed.
- [ ] **Step 4: Copy a freely licensed homebrew NES ROM that Mike supplies into `~/retromac/Library/nes/`, then launch ES-DE.** Expected:
  - NES shows the game, and launching it opens RetroArch fullscreen with the Mesen core and the CRT shader visible.
  - The controller drives the game.
  - Select+Start returns to ES-DE.
- [ ] **Step 5: Leave ES-DE open and press Install & Apply.** Expected: "Quit ES-DE and try again", and no files change (check mtimes with `stat`).
- [ ] **Step 6: Use Restore previous config with the snapshot from Step 2.** Expected: the original configs are restored byte-identical (`diff` against the backup copy).
- [ ] **Step 7: Report the results to Mike with command output. Commit any fixes made along the way.**
