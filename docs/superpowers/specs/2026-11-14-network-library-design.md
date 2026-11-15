# Network library: play from a server share, read-only

## Intent

Mike keeps terabytes of ROMs on a server. He wants retromac to play them straight from the server's shared folder, without copying anything to the Mac. It's a more advanced feature, so it's an **opt-in option, never the default**. New users and the setup wizard's defaults are unchanged.

## Goals

- **Pointing at the share:** in Settings, the user gives retromac a network share, and retromac uses it as the game library. ES-DE, RetroArch, Dolphin, PCSX2 and xemu all read games from it.
- **Connecting:** retromac connects the share by itself when it opens, and before ES-DE starts (Play and Console Mode). Nobody has to mount it in Finder first.
- **When the share is unreachable:** retromac says so plainly and offers to reconnect.
- **Turning it off:** the local library returns, untouched.

## Non-goals

- Mixing sources per console, with some consoles on the server and others local (approach B, not chosen).
- Copying, syncing or caching games from the server.
- Shrinking (CHD), organizing or importing games on the server.

## Anti-goals: a failure even if it technically works

- **retromac never changes the share.** It never writes, moves, renames or deletes anything there: no `.cue` files, no `Game.m3u` folders, no console folders, no imports, no conversions. That holds even though the share may be writable.
- **No silent fallback when the share is missing.** Today, if the library folder doesn't exist when retromac opens, `WizardModel` quietly resets it to the local library. That must not happen for a network library. The user would see an empty ES-DE and not know why.
- **retromac stores no server passwords.** macOS's own network-mount login (with "Remember this password in my keychain") handles credentials. retromac only stores the share's address.

## Decided (Mike, 2026-11-14)

- **Layout:** one folder per console on the share. Mike will arrange it.
- **Read-only:** retromac treats the share as read-only.
- **Approach A:** the share replaces the library while the option is on. retromac mounts it itself.
- **An advanced option**, off by default.

## Approaches considered

| | Approach | Trade-off | Outcome |
|---|---|---|---|
| A | **Switch the library to the share.** retromac mounts it, and every emulator reads from it. A read-only flag turns off every write. The local library is kept, unused. | While it's on, the share is the whole library, so Add Games is unavailable. | **Chosen:** it matches "the whole collection is on the server, used read-only", and it handles the share being offline. |
| B | Per-console overlay: consoles with a folder on the share come from the server, the rest stay local. | A confusing mixed state, for example a SNES game added locally that never appears because `snes` lives on the share. More code. | Not chosen. |
| C | The user mounts in Finder and picks `/Volumes/…`. | Least code, but an unmounted share means an empty ES-DE with no explanation. | Not chosen. |

## Constraints (from the code as it is)

- **Path:** `Profile.libraryRoot` is the single library path. ES-DE's `ROMDirectory`, `es_systems` (`%ROMPATH%/<system>`), Dolphin's `ISOPath0/1` and xemu's `games_dir` are all derived from it. PCSX2's `GameList/RecursivePaths` will be too once Phase 6 merges; that branch isn't on `main` yet.
- **Folder names:** console folders must use ES-DE's names, which are `SystemID` raw values. The expected-name list shown on Connect comes from `SystemID.allCases` (today `nes`, `snes`, `genesis`, `n64`, `psx`, `ps2`, `saturn`, `gc`, `wii`, `xbox`, `wiiu`, `switch`). There's no renaming layer.
- **What writes into the library today, all of it off for a network library:**
  - `ProfileRenderer` emits `.directory` files that create console folders.
  - `DiscSets.organizeLibrary` runs on every Apply.
  - `Importer.commit` (Add Games and folder import).
  - `ChdTool` (Shrink disc games).
  - `AppModel.showGamesInFinder` creates the library folder.
  - `GamesModel.refreshConvertible()` calls `ChdTool.removeLeftovers(in:)`, which deletes `.retromac-*.chd` files on every refresh, not only during Shrink.
  - The `retromac-tool` CLI imports into the profile's `libraryRoot`. It refuses while a network library is set.
- **Silent fallbacks to turn off:** `WizardModel.loadProfile` resets a missing `libraryRoot` to the local library, and `Migrator` step 5 does the same during a legacy migration. Neither may fire while `networkLibrary` is set.
- **Where saves and metadata live:** game saves are already local: RetroArch `savefile_directory`, Dolphin, PCSX2 and xemu all keep their own data folders. ES-DE's gamelists and media live in retromac's own ES-DE folder, not beside the ROMs. So the emulators and ES-DE don't write to the share either.
- **Multi-disc games:** on a read-only share, multi-disc PS1/Saturn games and bare `.bin` images play only if the share already holds their `.m3u`/`.cue` (the layout retromac writes locally: a `Game.m3u/` folder containing `Game.m3u` and the discs). The Library screen says so.
- **ES-DE start-up:** ES-DE scans the ROM folders at start-up. Over SMB, with a large collection, start-up will be slower. The builder should measure it on Mike's share during end-to-end testing and decide whether ES-DE needs a setting change. That's left open here.

## Design

1. **Profile:**
   - `Profile.networkLibrary: NetworkLibrary?`. When it's nil, nothing changes.
   - `NetworkLibrary` holds `url`, a `smb://` (or `nfs://`/`afp://`) URL that may include a sub-folder (`smb://nas/media/roms`), plus `localLibrary: URL`, the local library to restore when the option is turned off.
2. **Mounting:**
   - A `NetworkShare` type in RetromacCore mounts `url` with macOS's NetFS framework (`NetFSMountURLSync`). It allows macOS's standard login UI, so the system prompts for credentials and can remember them in the Keychain.
   - It returns the mount point, for example `/Volumes/media`, plus the sub-path.
   - It's idempotent: if the share is already mounted, it returns the existing mount point.
   - `libraryRoot` becomes the mounted folder.
3. **Library screen, under an "Advanced: network library" disclosure** *(Claude's call)*. "Settings" in this app is the setup wizard, and adding a step would put the option in every first-run walk-through. The Library screen is where the library's location already shows (storage readout, Show Games in Finder).
   - **Turning it on:**
     - A text field for the share address, then **Connect**. retromac mounts the share and lists which console folders it found, by ES-DE name, next to the expected names.
     - **Use this library** then switches `libraryRoot` and re-applies *(Claude's call: `WizardModel.applyConfigs()`, which renders and applies without running the Installer)*. If ES-DE or an emulator is open, it shows the usual "Quit X and try again" and changes nothing.
   - **Turning it off:** restores `localLibrary` and re-applies.
   - The section carries copy about the read-only behaviour and the `.m3u`/`.cue` requirement.
4. **Before ES-DE starts:**
   - `AppModel.play` mounts first, and only then posts Console Mode's play notification and opens ES-DE. If mounting fails, Play shows "Your network library isn't connected", with **Try again**, and neither notifies the agent nor starts ES-DE.
   - The Console Mode agent's own `launchESDE` (at login and after a wake) also mounts first. If mounting fails, it opens retromac's home screen instead of ES-DE, and the home screen shows the "isn't connected" banner with **Reconnect**. That keeps ES-DE from opening on an empty library *(Claude's call)*.
5. **On launch:**
   - `WizardModel` tries to mount instead of resetting `libraryRoot`.
   - If mounting fails, the home screen shows an "isn't connected" banner with **Reconnect**.
   - The library path is never changed automatically.
6. **Read-only everywhere:** while `networkLibrary` is set:
   - **Library screen:** Add Games, folder import and drag-and-drop are disabled, with the reason shown. Shrink disc games is hidden.
   - **Apply:** no `.directory` files are rendered, and `DiscSets.organizeLibrary` doesn't run.
   - **Show Games in Finder:** opens the mounted folder without creating anything.
   - **Library stats:** game counts only. Summing sizes across terabytes over SMB is skipped.
7. **The Applier's backups** cover only retromac's own config files, which are unchanged by this.

## Left to the builder

- How to present the mount-point and sub-path split, and how to handle a share that's mounted under a different `/Volumes` name (e.g. `media-1`).
- Whether NFS/AFP are allowed or only SMB. SMB is the stated case.
- Whether ES-DE start-up over SMB needs any ES-DE setting change, decided after measuring.
- Test strategy for NetFS. Expected: behind a protocol, with a fake in tests, plus one manual end-to-end test against Mike's server.
