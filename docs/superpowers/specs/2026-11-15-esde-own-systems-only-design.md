# ES-DE lists only retromac's consoles

## Intent

ES-DE shows any of its ~200 built-in consoles that has a folder in the library. A `dreamcast` folder on Mike's share appeared as a console whose every game fails ("core not found"); a non-technical user would hit the same wall with any folder retromac doesn't support. Probing those ~200 folders over SMB also cost 21 s of a 44.5 s start-up.

## Decided (Mike, 2026-11-15)

- ES-DE's `ROMDirectory` becomes an empty folder retromac owns (`ES-DE/roms`, created on Apply).
- Each retromac system in `custom_systems/es_systems.xml` gets an absolute `<path>`: `<libraryRoot>/<system>`, XML-escaped.
- Same rule for local and network libraries.

Measured on a scratch copy against Mike's share: Dreamcast gone, built-in probing 21 s → 0 s, start-up 44.5 s → 25.6 s.

## Approaches

| Approach | Trade-off | Outcome |
|---|---|---|
| Empty `ROMDirectory` + absolute system paths | Two rendered values change | **Chosen** |
| Override all ~200 bundled systems in custom_systems | Breaks when ES-DE adds a system | Rejected |
| Folder of symlinks to supported consoles | More moving parts, same result | Rejected |

## Non-goals

- The remaining ~18 s listing `psx` over SMB.
- `Migrator` step 6 still writes the library into `ROMDirectory`; the Apply that follows migration replaces it.
