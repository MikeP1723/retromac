# Skip Wii U imports (short design)

**Why.** Wii U is de-scoped. Cemu's last release, 2.6 from February 2025, is Intel-only, and its native builds can't be downloaded without a GitHub login. Today a Wii U file is copied into `<library>/wiiu` with "arrives in a later update" next to it. These images are often 20 GB or more, so that copy is wasted.

**Goal.** Recognise Wii U files and leave them alone.
- Nothing is copied, moved or filed to `_Unidentified`.
- Their row says "Wii U isn't supported", with the grey skip icon.
- The summary counts them as skipped.

**Non-goals.**
- Removing Wii U from `SystemID` or from the sniffer. Keeping recognition stops misfiling and lets Wii U come back in one line.
- Touching existing `wiiu` folders.
- Changing anything for Switch.

**Approaches.**
- **Skip (picked):** add an `ImportStatus.unsupported(SystemID)` result, set when the disc sniffer says `.wiiu`.
- **File them to `_Unidentified`:** rejected. It still copies the big files and implies retromac might identify them later.

**Design.**
- **`Importer`:** a sniffed `.wiiu` disc becomes `.unsupported(.wiiu)` instead of going through `planDisc`.
- **Summary:** `unsupported` counts toward `skipped`, and `bytesToCopy` is 0.
- **`LibraryView`:** shows the `minus.circle` icon in secondary colour, and the detail text "`<System>` isn't supported".
- **CLI:** prints `skip <source> (<system> isn't supported)`.

Approved by Mike, 2026-11-16.
