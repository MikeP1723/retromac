# retromac: Mac Retro Emulation Installer (Design)

*Revised 2026-11-13. Personal tool, free and public on GitHub. Everything in the repo or installed by default must be GPL-compatible. Anything not marked as Mike's decision is Claude's call.*

## Intent

Get a Mac from nothing to "controller in hand, games on the TV" through one guided installer. Then keep it that way: ROMs dropped onto a network share appear in the library already identified and filed.

## Decided by Mike

- Personal tool, hosted for free public use on GitHub.
- Complies with GNU license terms (see Licensing).
- Name: **retromac**. Bundle ID: `petersoft.retromac`.
- An update process and wizard covers retromac itself, the emulators, cores, and other downloaded dependencies.
- No arcade.
- Scope is classic home consoles: NES, SNES, Genesis, N64, Saturn, PS1, PS2, Wii, Wii U, Switch, Switch 2, Xbox. Switch 2 and Switch are adjusted below, with the reasons given.

## Platform reality check (Claude, verified 2026-11-13)

**Target machine:** macOS 27.2.1 on arm64, with **Rosetta 2 not installed**. Apple has said macOS 27 is the last release with general-purpose Rosetta. Any x86-only emulator is therefore on borrowed time.

| Requested | Emulator | Native arm64 on macOS? | Status in design |
|---|---|---|---|
| Switch 2 | none viable | — | **Dropped.** No public emulator runs commercial Switch 2 games. Eden NX2, the main experimental attempt, was archived on 2026-11-02. |
| Switch | Ryubing (Ryujinx fork, MIT) | Yes | **Detect-and-configure only** (see below). Upstream is in maintenance mode. |
| Wii U | Cemu (MPL-2.0) | **No.** x86 under Rosetta. A Metal backend and native build are in progress. | **Rosetta-tier** (see below). |
| PS2 | PCSX2 (GPLv3+) | **Not officially.** x86 under Rosetta. The ARMSX2 fork ships macOS arm64. | **Rosetta-tier, official PCSX2** (Mike's decision). Switch to native when an official arm64 build ships. |
| Xbox | xemu (GPLv2) | Believed yes, verify at pin | Assumed to mean **original Xbox**. Xbox 360 (Xenia) has no macOS build. |

**Rosetta tier.** The manifest has an `arch` field. A native `arm64` build is always preferred. An `x86_64` entry is allowed only when marked `rosetta: true`. When one is selected, the wizard installs Rosetta (`softwareupdate --install-rosetta`, admin) and shows a plain warning: "This system depends on Rosetta, which Apple is phasing out after macOS 27." CI fails on any x86-only entry that isn't marked. On a later macOS where Rosetta is gone, these systems are hidden instead of failing at launch.

**Why Switch is detect-and-configure only.** Nintendo DMCAs Switch emulators and their forks on GitHub. Switch emulation also needs `prod.keys` and firmware dumped from the user's own console. Two rules keep the repo out of range:
- retromac **never downloads a Switch emulator**. It detects Ryubing if the user installed it, then configures display, controllers, and the game directory.
- retromac **never reads, hashes, copies, or names key or firmware files**, and the repo contains nothing about them. Ryubing's own first-run flow handles keys.

What would change my mind: if you're comfortable with the takedown risk to the whole repo. EmuDeck installed Switch emulators for years. Even then, keys stay out.

## Goals

1. A wizard that turns display, controller, and preference answers into working emulator configs, with no hand-editing of INI or CFG files.
2. Guided Bluetooth controller pairing and correct per-controller, per-emulator button mapping, including Nintendo-layout face buttons.
3. An optional SMB share as a ROM inbox, LAN-only, with its own credentials.
4. A background librarian that identifies, normalizes, and files games and BIOS files as they arrive.
5. Idempotent re-runs.

## Non-goals

- Bundling, mirroring, downloading, or linking to ROMs, BIOS files, firmware, or keys.
- Arcade, Switch 2, Xbox 360, PS3.
- Remote or internet access to the share.
- A custom launcher or scraper (ES-DE handles both).
- Mac App Store distribution, notarization, Sparkle, and silent auto-update. Updates always go through the update wizard.

## Anti-goals

- Silently overwriting existing emulator configs.
- A share reachable from outside the LAN, or one that reuses the user's login.
- Destroying or mis-filing source files.
- Asking anything the machine can detect.
- retromac redistributing any third-party binary.
- Any code path that handles console decryption keys.

## Systems

| System | Emulator | License | Library format | Identification | Needs user-supplied |
|---|---|---|---|---|---|
| NES | Mesen (libretro) | GPLv3 | .nes | No-Intro hash (headerless) | — |
| SNES | bsnes (libretro) | GPLv3 | .sfc | No-Intro hash (copier header stripped) | — |
| Genesis | BlastEm (libretro) | GPLv3 | .md | No-Intro hash | — |
| N64 | Mupen64Plus-Next (libretro) | GPLv2 | .z64 | No-Intro hash (byte order normalized) | — |
| Saturn | Beetle Saturn (libretro) | GPLv2 | .chd | Redump per-track | BIOS (required) |
| PS1 | Beetle PSX HW (libretro) | GPLv2 | .chd, .m3u | Redump per-track | BIOS (required) |
| PS2 | PCSX2 (standalone) | GPLv3+ | .chd | Redump | BIOS (required) |
| GameCube / Wii | Dolphin (standalone) | GPLv2+ | .rvz | Redump, then disc header game ID | — |
| Wii U | Cemu (standalone) | MPL-2.0 | .wua | Title ID from package metadata | Files only. Disc-image keys are out of scope, so encrypted .wud/.wux go to `_Unidentified`. |
| Xbox | xemu (standalone) | GPLv2 | .xiso | Redump if untrimmed, else XBE header title ID | MCPX boot ROM, flash BIOS, HDD image |
| Switch | Ryubing (detected only) | MIT | .nsp/.xci untouched | Title ID from **filename only** (metadata needs keys) | Everything, handled by Ryubing |

GameCube support comes for free with Dolphin, so it's included. All licenses are from memory, and each one is verified against upstream LICENSE files when its version is pinned.

## Licensing

- **retromac is GPL-3.0-or-later**, with SPDX headers, `LICENSE`, and `THIRD_PARTY_NOTICES.md`.
- **Vendored or linked code** must be GPLv3-compatible: libarchive (BSD-2), SDL_GameControllerDB (zlib), SQLite (public domain).
- **Runtime-installed components** come from official upstream URLs, pinned by sha256, and are never re-hosted. Not redistributing them keeps retromac out of GPL §6 source-offer obligations. The manifest lives in the repo.
- **Default emulators are FOSS only.** Non-commercial-licensed cores (Snes9x, Genesis Plus GX, PicoDrive) are never installed by default.
- **CI checks licenses:** an SPDX allowlist over `manifest.json` and Swift package dependencies.
- **Tools:** chdman (MAME, GPLv2+) and `dolphin-tool` (ships with Dolphin) are installed from upstream and never vendored.
- **No unrar** because of its license. libarchive's RAR reader is used, and its RAR5 support is partial.
- **No DATs in the repo.** The user imports No-Intro DATs, and Redump DATs are fetched on first run.
- **The README links to no ROM, BIOS, firmware, or key sources.**
- ⚠ **"Mac" in the name.** Apple's trademark guidelines discourage "Mac" in product names. The risk is low for a free GitHub project, but an Apple complaint is a possible forced rename.

## Architecture

```
retromac.app (SwiftUI, arm64, macOS 14+, ad-hoc signed)
├── Wizard UI ─────────────► profile.json  (single source of truth)
├── Config renderer: profile → RetroArch / ES-DE / Dolphin / PCSX2 / Cemu / xemu / Ryubing
├── Installer: manifest.json (in repo) → upstream download → sha256 → /Applications
├── Controller service: GameController.framework + IOBluetooth
├── Privileged ops: one-shot admin script (SMB, role account, Rosetta install)
└── Librarian (LaunchAgent in ~/Library/LaunchAgents)
      FSEvents on inbox → identify → normalize → file → notify ES-DE
Shared Swift package `RetromacCore`: profile model, renderers, identifiers, DAT index
```

- **No privileged daemon and no Sparkle.** Updates are covered in the Updates section below.
- **Distribution:** build from source, plus an unsigned release `.zip`. On macOS 15 and later the README must explain System Settings › Privacy & Security › Open Anyway.
- **TCC gotcha:** ad-hoc rebuilds change the cdhash and reset privacy grants. The default library is `~/retromac/` because it isn't TCC-protected. External drives work but re-prompt after updates.
- **Manifest entries** carry version, upstream URL, sha256, SPDX license, `arch`, an optional `rosetta: true`, and an optional `upstream` source used for bump automation.
- **The manifest itself** carries `manifestVersion`, which increments on every release, and `minAppVersion`.
- **Download host allowlist.** Download hosts must be on an allowlist compiled into the app: `buildbot.libretro.com`, `gitlab.com`, `github.com`, plus other official project domains as they're added. A tampered release manifest therefore can't redirect downloads anywhere else without an app update.

## The wizard

| Step | Detected | Asked |
|---|---|---|
| Display | Resolution, refresh rate, HDR, VRR | Screen size, seating distance; look: **Crisp pixels / CRT look / Smooth** |
| Audio | Output device | — |
| Systems | Installed emulators, Rosetta availability | Which systems to set up (Rosetta-tier systems are labeled) |
| Controllers | Connected pads | "Put your controller in pairing mode" |
| Players | Pad count | Confirm player order |
| Face buttons | — | Follow the position or the label on Nintendo-layout pads |
| Library | — | Location; enable share? |
| Launch | — | Boot into ES-DE at login; exit-to-desktop combo |

**Display rules** live in `display_rules.json`. Size and distance give an effective pixel density, which drives the following:
- Integer scaling and aspect policy, for 2D-era systems.
- Shader tier, for 2D-era systems.
- Internal resolution multiplier and widescreen hacks, offered for N64 and later (and off by default).
- Latency settings.
- VRR content-rate sync.

The 3D-era standalone emulators get their resolution scale from the rules table. For example, a 4K TV runs Dolphin at 4–5× and PCSX2 at 4×, capped by a per-chip performance table (M-series tier from `sysctl`).

## Controllers

**Pairing is guided.** The user still presses the pairing-mode buttons. `IOBluetoothDeviceInquiry` and `IOBluetoothDevicePair` sit behind a protocol, with a fallback that opens System Settings › Bluetooth.

**Identification** uses vendor and product ID plus `GCController.productCategory`. 8BitDo pads report a different identity in each mode. The wizard recommends one mode per model and detects a mismatch.

**Mapping.** Each controller has one canonical layout using the SDL GameController model. Translators emit:
- RetroArch autoconfig
- Dolphin `GCPadNew.ini` / `WiimoteNew.ini`
- PCSX2 pad config
- Cemu controller profiles
- xemu input config
- Ryubing input config
- ES-DE input config

Unknown pads fall back to SDL_GameControllerDB, then to on-screen capture.

**Wii and Wii U special cases.** The Wii defaults to an emulated Wiimote plus Nunchuk on a standard pad, with motion on the right stick and pointer on gyro where the pad has it (DualSense, Switch Pro). The Wii U GamePad screen is mapped to a Cemu separate-window or swap-screen hotkey. Real Wiimotes over Bluetooth passthrough are out of scope.

**Tech debt:** there are now **six standalone config formats**, up from two. This is the dominant maintenance cost and is why Switch and Wii U come last in the phasing.

## Network share

Set up once by the admin script:
- A sharing-only role account with a random password, stored in the Keychain and shown once.
- Only `~/retromac/Inbox` is shared read-write.
- SMB3 encryption and signing are required, and guest access is off.
- The firewall is verified on, with no UPnP or port forwarding.
- The share is advertised over Bonjour.
- Uninstall reverses all of it.

## Librarian

For each file:
1. **Settle.** Wait until size and mtime are stable.
2. **Unpack** archives via libarchive.
3. **Normalize:** strip the SNES copier header, convert N64 byte order, and hash NES without the iNES header.
4. **Identify** with the strategy for the system (see the Systems table). Disc systems match by Redump hash per track. Modern systems match by header or title ID.
5. **Convert:**
   - Saturn, PS1, and PS2 to CHD (chdman).
   - GameCube and Wii to RVZ (`dolphin-tool convert`).
   - Multi-disc games get an `.m3u`.
   - Wii U, Xbox, and Switch files are left in their formats.
6. **BIOS:** match against the known-BIOS hash table for Saturn, PS1, PS2, and Xbox (MCPX, flash), and copy each file to its emulator's directory. The app shows status per system.
7. **File** to `Library/<system>/<Canonical Name>.<ext>`, then rescan ES-DE.
8. **No match:** move to `_Unidentified/` with a reason sidecar. Encrypted Wii U disc images and anything that would need keys land here.

Files are copied, the hash is verified, and only then is the original removed. A SQLite journal lets a crashed ingest resume. Converting a 4 GB disc image to CHD or RVZ takes minutes, so conversions run through a bounded queue and show progress in the app.

## Updates

**There's one channel: GitHub Releases on `MikeP1723/retromac`.** Each release carries two assets:
- `retromac.zip`, the app.
- `manifest.json`, the bundled manifest plus a `retromac` self-entry (version, zip URL, sha256).

A manifest bump (a new RetroArch, a new core build, a new DAT source later) is therefore just a release. No separate update server exists.

**Update wizard (in-app):**
1. **Check.** The wizard runs on launch at most once every 24 hours, and on demand via *Check for Updates…* (⌘U).
2. **Validate the release manifest.** It fetches the latest release's `manifest.json` and runs the same policy as CI on it: license allowlist, arch rule, sha format, https, and host allowlist. Any violation rejects the whole manifest.
3. **Diff against what's installed.** `~/retromac/state.json` records the version, sha, and *managed* flag of each component retromac installed. The diff shows:
   - each component as installed → available
   - a red flag when the **license changed**
   - a warning when the new build **needs Rosetta**
   - a blocker when the app is older than `minAppVersion` ("update retromac first")
4. **Pick and apply.**
   - Updates are refused while RetroArch or any emulator is running.
   - Components are staged (downloaded and sha-verified) before anything is swapped.
   - The current version is moved to `~/retromac/previous/` (one generation is kept), and the new one is moved into place.
   - If anything fails mid-swap, the old version goes back.
   - Finally, configs are re-rendered and re-applied (with backups as usual), so new emulator versions get any renderer changes.
5. **Rollback.** Each component has a *Revert* action that swaps `previous/` back. Config backups restore the same way as in the main wizard.

**Unmanaged apps.** These are apps that were already installed before retromac (for example, your own RetroArch). They show up with an **Adopt** option. Adopting moves the existing copy to `previous/`, and from then on retromac manages it. Without adopting, retromac never replaces them.

**Self-update.**
1. Download `retromac.zip` and verify its sha against the release manifest.
2. Check that the bundle ID is `petersoft.retromac` and that the version matches.
3. Quit.
4. A small detached script waits for the process to exit, moves the old app to `previous/`, and relaunches the new one.

Downloads through `URLSession` aren't quarantined, so Open Anyway isn't needed again. TCC grants do reset, as noted under Architecture.

**Keeping pins current (maintainer side).**
- A weekly GitHub Action runs `retromac-tool check-upstream`.
  - It queries each component's `upstream` source (GitHub releases, GitLab releases, or the libretro stable index).
  - It downloads newer builds, computes their shas, bumps `manifestVersion`, and opens a PR.
  - The PR has a checklist covering the license (unchanged?), the arch, and the release notes.
- **Gotcha:** PRs opened with `GITHUB_TOKEN` don't trigger other workflows. The bump job therefore runs `swift test` and `verify-manifest` itself before opening the PR.
- Merging the PR and tagging `vX.Y.Z` runs the release workflow, which builds, zips, writes the release manifest, and publishes.

**Trust model.** A release manifest is exactly as trusted as Mike's GitHub account, which is the same trust the app binary already depends on. The compiled-in host allowlist and license policy limit the damage from a bad manifest.

## Phasing

1. **Spine:**
   - Installer for RetroArch and ES-DE.
   - Display wizard and renderer.
   - RetroArch autoconfig for Xbox, DualSense, and Switch Pro pads.
   - License and arch CI.
   - Systems: NES, SNES, Genesis, N64.
2. **Updates:** release pipeline, update wizard, self-update, rollback, upstream-bump Action.
3. **Librarian:** cartridge systems, then Saturn and PS1 with CHD. Redump DAT refresh joins the update wizard.
4. **Share.**
5. **Standalones, native first:** Dolphin (GameCube/Wii), xemu, then PS2.
6. **Rosetta tier and detect-only:** Cemu, then the Ryubing integration.
7. **Polish:** guided BT pairing, boot-to-ES-DE, player order, audio output.

## Testing

- Golden-file tests for every renderer.
- Identifier tests use homebrew and public-domain ROMs plus synthetic fixtures, with a hand-written DAT. No commercial content, BIOS, firmware, keys, or No-Intro DATs in the repo or CI.
- License, SPDX, and arch CI.
- Pairing and mapping are checked by hand against physical controllers.

## Left to the builder

- DAT index schema.
- Settle timing.
- Conversion concurrency.
- The per-chip performance table values.
- Wizard visual design.

## Resolved decisions (Mike, 2026-11-13)

1. **Switch is detect-and-configure only.** retromac never downloads a Switch emulator and never handles keys or firmware.
2. **PS2 uses official PCSX2 under Rosetta** until an official arm64 build ships. ARMSX2 stays a possible one-line manifest swap later.
