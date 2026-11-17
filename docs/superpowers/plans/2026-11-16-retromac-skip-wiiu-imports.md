# Skip Wii U Imports Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Wii U files are recognised and skipped on import, never copied.

**Architecture:** A new `ImportStatus.unsupported(SystemID)` is set in `Importer` when `DiscSniffer` returns `.wiiu`. It is counted as skipped and shown as skipped.

**Tech Stack:** Swift 6 SwiftPM, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-16-skip-wiiu-imports-design.md`

## Global Constraints
- **Row detail copy:** `"\(system.displayName) isn't supported"`.
- **Untouched:** Switch imports.
- **Never written:** the library, `_Unidentified` and the session folder get nothing for a Wii U file.

## Review Focus
1. **A Wii U file inside a zip** is skipped the same way, with nothing left staged. *(Task 1, `wiiUFilesAreSkippedNotCopied`)*
2. **A drop with a Wii U file and an NES ROM** imports the NES ROM and skips the Wii U file. *(same test)*

---

### Task 1: Skip Wii U on import

**Files:**
- Modify:
  - `Sources/RetromacCore/Library/Importer.swift`
  - `Sources/retromac/Views/LibraryView.swift`
  - `Sources/retromac-tool/main.swift`
- Test: `Tests/RetromacCoreTests/ImporterDiscTests.swift`

**Interfaces:** Produces `ImportStatus.unsupported(SystemID)`.

- [ ] **Step 1:** Write the failing test `wiiUFilesAreSkippedNotCopied`.
  - **Input:** a folder holding a `WUX0`-magic `game.wux`, an NES ROM, and a zip that contains a `WUHB`-magic `app.wuhb`.
  - **Analysis:** the `.wux` and the zipped `.wuhb` are both `.unsupported(.wiiu)` with a nil destination. `summary.skipped == 2`. `summary.bytesToCopy` covers the NES ROM only.
  - **After `commit`:** no `wiiu` folder and no `_Unidentified` folder exist under the library, and the NES ROM is filed.
- [ ] **Step 2:** Run `swift test --filter wiiUFilesAreSkipped`. Expected: compile failure, because `unsupported` doesn't exist yet.
- [ ] **Step 3:** Implement the case. Handle it in every switch on `ImportStatus`, including the app and the CLI.
- [ ] **Step 4:** Run `swift test`, then `swift build`. Expected: all pass.
- [ ] **Step 5:** Commit `feat: skip Wii U files on import`.
