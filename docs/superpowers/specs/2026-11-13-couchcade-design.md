# Couchcade — Mac Retro Emulation Installer (Design)

*Working name. Revised 2026-11-13. This is a personal tool, published free on GitHub, and everything in the repo or installed by default must be GPL-compatible. Anything not marked as Mike's decision is Claude's call.*

## Intent

Couchcade takes a Mac from nothing to "controller in hand, games on the TV" with one guided installer. It then keeps the setup working: ROMs dropped onto a network share appear in the library already identified and filed, with no further setup.

Existing tools each cover a piece. RetroArch has the cores and ES-DE has the couch UI, but nothing ties display-aware configuration, controller onboarding, and library ingest into one flow.

## Decided by Mike

- It's a personal tool, hosted for free public use on GitHub.
- It must comply with GNU license terms (see the Licensing section below for how that's applied).

## Goals

1. A wizard that turns answers about the display, controllers, and preferences into working emulator configs, with no hand-editing of INI or CFG files.
2. Guided Bluetooth controller pairing and correct per-controller, per-emulator button mapping, including Nintendo face-button layouts.
3. An optional, LAN-only SMB share with its own credentials, used as a ROM inbox.
4. A background "librarian" that identifies, normalizes, and files ROMs and BIOS files as they arrive.
5. Idempotent re-runs. A new TV or controller means re-running one wizard step, which re-renders the configs.

## Non-goals

- Bundling, mirroring, downloading, or linking to ROMs or BIOS files.
- Remote or internet access to the share.
- Switch, PS3, and Wii U emulation.
- A custom game launcher or metadata scraper. ES-DE handles both.
- Mac App Store distribution, Developer ID notarization, and in-app auto-update.

## Anti-goals (failure even if it technically works)

- Silently overwriting existing emulator configs. Every write is backed up and scoped to keys or files Couchcade owns.
- A share reachable from outside the LAN, or one that reuses the user's macOS login.
- Destroying or mis-filing source files during ingest.
- Asking anything the machine can detect.
- Couchcade redistributing a third-party binary. That would trigger GPL source-provision obligations and is the easiest way to fall out of compliance.

## Licensing

**Couchcade's own license is GPL-3.0-or-later.** Couchcade only downloads emulators and writes their configs, without linking them, so this is mere aggregation and GPL isn't strictly forced. GPLv3+ is still the simplest choice that stays compatible with every component below. Each source file gets an SPDX header, and the repo carries `LICENSE` and `THIRD_PARTY_NOTICES.md`.

**Third-party code falls into three tiers.**

| Tier | Rule | Examples |
|---|---|---|
| Vendored in the repo or linked into Couchcade | GPLv3-compatible licenses only, with the notice kept | libarchive (BSD-2), SDL_GameControllerDB (zlib), SQLite (public domain) |
| Installed by Couchcade at runtime | Downloaded from the **official upstream URL** with sha256 pinned, never re-hosted. Default selections must be FOSS. | RetroArch (GPLv3), ES-DE (MIT), Dolphin (GPLv2+), PCSX2 (GPLv3+) |
| Referenced but not shipped | Couchcade points at files the upstream install already provides | RetroArch slang shaders, libretro autoconfig |

**Never redistributing third-party binaries** is what keeps the project out of GPL §6 source-offer obligations. For the same reason, the manifest lives in the GitHub repo or release assets, not on a separate mirror.

**Default libretro core set, FOSS only.** Several popular cores are licensed *non-commercial*, not GPL. Couchcade never installs those by default. Users can still add them through RetroArch's own updater, which is outside Couchcade.

| System | Default core | License | Non-free core avoided |
|---|---|---|---|
| NES | Mesen | GPLv3 | — |
| SNES | bsnes | GPLv3 | Snes9x (non-commercial) |
| GB/GBC | Gambatte | GPLv2 | — |
| GBA | mGBA | MPL-2.0 | — |
| Genesis/MD | BlastEm | GPLv3 | Genesis Plus GX, PicoDrive (non-commercial) |
| N64 | Mupen64Plus-Next | GPLv2 | — |
| PS1 | Beetle PSX HW | GPLv2 | — |
| Saturn | Beetle Saturn | GPLv2 | — |
| PC Engine | Beetle PCE | GPLv2 | — |
| Dreamcast | Flycast | GPLv2 | — |
| Atari 2600 | Stella | GPLv2 | — |
| Arcade | MAME (current) | GPLv2+ | FBNeo, MAME 2003-Plus (non-commercial) |
| GC/Wii | Dolphin (standalone) | GPLv2+ | — |
| PS2 | PCSX2 (standalone) | GPLv3+ | — |

⚠ These licenses are from memory. Each manifest entry carries an SPDX `license` field, which is verified against upstream's LICENSE when a version is pinned. CI fails on any SPDX identifier outside the allowlist (GPL-2.0+, GPL-3.0+, LGPL, MPL-2.0, MIT, BSD, zlib, Apache-2.0 for tools only).

**Licensing side effects to know about:**
- **Arcade becomes harder.** Current MAME requires current-version romsets, so older sets will mostly land in `_Unidentified` with a "romset version mismatch" reason. This is the price of excluding FBNeo.
- **No RAR support through unrar.** The unrar license isn't GPL-compatible. libarchive's own RAR reader (BSD) is used instead, and RAR5 support there is partial. Unreadable archives go to `_Unidentified`.
- **chdman** comes from MAME (GPLv2+). It's installed from upstream (MAME release or Homebrew `rom-tools`) and never vendored.
- **DATs are data, not code, but No-Intro's redistribution terms are unclear.** The app never ships DATs. The user imports No-Intro DATs, and Redump DATs are fetched from redump.org on first run.
- **The README must not link to ROM or BIOS sources.** This avoids giving GitHub a DMCA pretext.

## Architecture

```
Couchcade.app (SwiftUI, Apple Silicon, macOS 14+, ad-hoc signed)
├── Wizard UI ─────────────► profile.json  (single source of truth)
├── Config renderer: profile.json → RetroArch / ES-DE / Dolphin / PCSX2 configs
├── Installer: manifest.json (in repo) → upstream download → sha256 verify → /Applications
├── Controller service: GameController.framework + IOBluetooth
├── Privileged ops: one-shot admin script (osascript "with administrator privileges")
│     SMB share, sharing-only user, firewall check
└── Librarian (LaunchAgent plist in ~/Library/LaunchAgents)
      FSEvents on inbox → identify → normalize → file → notify ES-DE
Shared Swift package `CouchcadeCore`: profile model, renderers, identifier, DAT index
```

Changes from the first draft, driven by personal use and having no Developer ID:
- **No SMAppService privileged daemon.** It needs proper team signing, and the privileged work is one-time setup anyway, so an admin-prompted script that runs once is the simpler choice.
- **No Sparkle.** On launch, the app checks the GitHub Releases API and shows a "new version" link.
- **Distribution is build-from-source first, with an unsigned release `.zip` second.** Gotcha: macOS 15 and later removed the right-click → Open bypass. The README has to walk users through System Settings › Privacy & Security › Open Anyway.
- **TCC gotcha:** ad-hoc signed binaries get a new cdhash on every rebuild, which resets privacy grants such as removable-volume access. The default library is `~/Couchcade/`, which isn't TCC-protected (unlike Desktop or Documents). An external drive works but re-prompts after each update.

**Installer manifest.** Components are pinned, not "latest", because upstream config formats drift. Each entry has a version, the official URL, sha256, SPDX license, and config schema version. Quarantine is stripped only after the checksum is verified.

## The wizard

The wizard asks only for things it can't detect.

| Step | Detected | Asked |
|---|---|---|
| Display | Resolution, refresh rate, HDR, VRR | Screen size, seating distance; look: **Crisp pixels / CRT look / Smooth** |
| Audio | Output device | — |
| Controllers | Connected pads | "Put your controller in pairing mode" |
| Players | Pad count | Confirm player order |
| Face buttons | — | Follow button position or button label on Nintendo-layout pads |
| Library | — | Location; enable share? |
| Launch | — | Boot into ES-DE at login; exit-to-desktop combo |

**Display profile to settings.** Size and distance give the effective pixel density. That density, together with the look preference, drives:
- integer scaling and per-system aspect policy
- shader tier (full CRT only for large 4K screens at short distance; light scanlines or none on smaller screens; sharp-bilinear for Smooth)
- latency settings (run-ahead on cheap cores, auto frame delay, and a Game Mode reminder)
- VRR content-rate sync, which matters for PAL games and arcade refresh rates

The rules live in `display_rules.json`. Shader presets are referenced by path inside the user's RetroArch install, not vendored. A preset is only selected when its license is GPL-compatible, and most of slang-shaders is GPL.

## Controllers: pairing and mapping

**Pairing is guided, not fully automatic.** The user still has to physically put the pad into pairing mode. `IOBluetoothDeviceInquiry` finds it, `IOBluetoothDevicePair` pairs it, and the wizard shows instructions per model. IOBluetooth is old and lightly maintained, so it sits behind a protocol, with a fallback that opens System Settings › Bluetooth.

**Identification** uses vendor/product ID plus `GCController.productCategory`. 8BitDo pads change identity with their mode, so the wizard recommends one mode per model and detects when a pad is in the wrong one.

**Mapping.** Each physical controller gets one canonical layout using the SDL GameController model. Translators turn it into RetroArch autoconfig keyed by vendor/product ID, Dolphin `GCPadNew.ini`, PCSX2 pad sections, and ES-DE input config. Unknown pads fall back to the vendored SDL_GameControllerDB, then to an on-screen button capture.

**Tech debt:** these translators are the long-term maintenance cost. Every standalone emulator adds a config format that drifts, which is why v1 has only two.

## Network share

Set up once through the admin script:
- Create a **sharing-only role account** with a random password, stored in the Keychain and shown once.
- Share **only** `~/Couchcade/Inbox` read-write via `sharing -a`. Optionally share `Library` read-only.
- Enable SMB with SMB3 encryption and signing required, and guest access off.
- Verify the firewall is on. Never configure UPnP or port forwarding.
- Advertise over Bonjour.
- Uninstall reverses all of the above.

## Librarian

For each file:
1. **Settle.** Wait until size and mtime are stable for N seconds, since SMB writes arrive in chunks.
2. **Unpack** zip, 7z, and RAR via libarchive. Arcade sets stay zipped.
3. **Normalize before hashing.** Strip the SNES copier header, convert N64 `.v64`/`.n64` to `.z64`, and hash NES files without the iNES header.
4. **Hash** (CRC32, SHA1) and match against the DAT index (logiqx XML → SQLite). Disc images are matched per track.
5. **Discs.** Convert to CHD where the core supports it, and write `.m3u` playlists for multi-disc games.
6. **BIOS.** Match against a known-BIOS hash table and copy to the right `system/` directory. The app shows status per system.
7. **File** to `Library/<system>/<Canonical Name>.<ext>` and trigger an ES-DE rescan.
8. **No match** goes to `Library/_Unidentified/` with a sidecar file explaining why. Nothing is guessed silently.

For safety, files are copied, the hash is verified, and only then is the inbox original removed. A SQLite ingest journal makes crash recovery resumable.

## Config rendering rules

- Renderers are pure functions of profile and manifest that produce files.
- Couchcade owns specific RetroArch keys and per-core overrides, and leaves every other setting alone.
- Every write is preceded by a timestamped backup, and restoring one is a single click.

## Phasing

1. **Spine:** the installer for RetroArch and ES-DE, the display wizard, the renderer, RetroArch autoconfig for Xbox, DualSense, and Switch Pro, and the license CI check.
2. **Librarian:** local inbox, cartridge systems first, then discs and CHD.
3. **Share:** admin script, role account, SMB.
4. **Standalones:** Dolphin, then PCSX2.
5. **Polish:** guided BT pairing, boot-to-ES-DE, GitHub release check.

## Testing

- Golden-file tests for renderers across display-rule combinations.
- Identifier tests use homebrew and public-domain ROMs plus synthetic fixtures. No commercial ROMs, BIOS files, or No-Intro DATs in the repo or in CI. A tiny hand-written DAT covers the homebrew fixtures.
- License CI: SPDX allowlist check over `manifest.json` and Swift package dependencies.
- Pairing and mapping are verified by hand against physical controllers.

## Left to the builder

- DAT index schema, settle timing, and CHD conversion concurrency.
- Wizard visual design.
- Exact SPDX allowlist wording.

## Remaining open decision

- **Default arcade core.** As written, the FOSS-only default means current MAME, and most older romsets won't run. What would change this is if arcade matters to you. Then the alternative is installing FBNeo only after an explicit opt-in screen that says plainly it's non-commercial licensed. That's still compliant, because Couchcade never redistributes it.
