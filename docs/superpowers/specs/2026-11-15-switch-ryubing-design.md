# Nintendo Switch through Ryubing (guided, advanced)

## Intent

Round out retromac's console list for other users with the Nintendo Switch. The master spec (2026-11-13) fixed the legal line: retromac **never downloads a Switch emulator** and **never reads, hashes, copies or names key or firmware files**. Ryubing (the maintained Ryujinx fork, MIT) is detected if the user installed it, then configured so Switch games launch from ES-DE like every other console.

Switch is the one console where a user must work inside an emulator app: keys and firmware can only go in through Ryubing's own window. So retromac guides the user through it and labels it plainly as **for advanced users, with manual setup**.

## Decided (Mike, 2026-11-15)

- **Ryubing first.** Cemu (Wii U) is a separate, later project.
- **Guided setup.** A Switch card in retromac walks through three steps:
  1. **Install Ryubing.** retromac links to ryubing.org and ticks the step itself once `/Applications/Ryujinx.app` exists.
  2. **Add keys and firmware.** A button opens Ryubing, with one sentence on what to do there. retromac can't verify this step, so the user ticks it.
  3. **Done.** Switch joins ES-DE.

  Until step 2 is ticked, Switch stays out of ES-DE, so nobody sees games that can't start.
- **Approach B.**
  - Display settings go on the command line in ES-DE's launch command.
  - A few owned keys are merged into Ryubing's `Config.json`, for what the command line can't set.
  - Ryubing keeps its default data folder.
- **An advanced-user warning wherever Switch is offered.** The copy says it needs Ryubing installed by the user and keys and firmware from the user's own Switch, set up inside Ryubing, and that retromac can't do those steps.

## Facts this design rests on (Ryubing 1.3.3, recon 2026-11-15)

**Distribution.** Releases are on Forgejo at git.ryujinx.app (ryubing/ryujinx). The macOS build is `ryujinx-<v>-macos_universal.app.tar.gz` and is native arm64. The bundle is `Ryujinx.app` (`org.ryujinx.Ryujinx`), with executable `Contents/MacOS/Ryujinx`. Its Info.plist version string is a placeholder ("1.2"), so the version can't be read from the bundle.

**Data folder.** It defaults to `~/Library/Application Support/Ryujinx`. A `portable` folder next to the app overrides it; `--root-data-dir` also changes it, and retromac won't use that. Settings live in `Config.json` in that folder, with `"version": 70` at 1.3.3. Ryubing creates the file on its first run.

**Command line** (`src/Ryujinx/Utilities/CommandLineState.cs`): `-f/--fullscreen`, `--docked-mode`/`--handheld-mode`, `--hide-cursor <mode>`, `--hide-updates`, `-g/--graphics-backend`, `-r/--root-data-dir`, `-p/--profile`, `-i/--application-id`. There are no options for input or for the exit confirmation.

**Config fields** (`src/Ryujinx/Systems/Configuration/ConfigurationFileFormat.cs`) include `GameDirs`, `ShowConfirmExit`, `StartFullscreen`, `HideCursor`, `InputConfig` (a list) and `UpdateCheckerType`. The JSON key spellings have to be confirmed against a real `Config.json`; see the spike.

**ES-DE.** The bundled `switch` system lists `.nca .nro .nso .nsp .xci`, with command `%EMULATOR_RYUJINX% %ROM%`. Its `RYUJINX` find rule is the static path `/Applications/Ryujinx.app/Contents/MacOS/Ryujinx`.

**retromac already:**
- has `SystemID.switch`
- sniffs NSP (`PFS0`) and XCI (`HEAD` at 0x100) files
- files them into `<library>/switch/`

## Spike results (2026-11-15, Ryubing 1.3.3 on macOS 27.2.1, M4 Pro)

**Signing.** The release is ad-hoc signed with no Team ID, and `spctl` rejects it, because it isn't notarized. Downloaded through a browser, its first launch is blocked. The user allows it in **System Settings › Privacy & Security › Open Anyway**, and step 1's copy says so.

**First run.**
- `Config.json` is written immediately, at `"version": 70`, with 94 keys.
- Ryubing shows **"RYU-0001: Keys not found"** until keys are installed. Step 2's copy names this message, so the user knows it's expected.

**Owned keys**, as spelled in the file:
- `show_confirm_exit`: bool, default `true`
- `game_dirs`: list of strings, default `[]`
- `update_checker_type`: `"Off"`, `"PromptAtStartup"` (default) or `"CheckInBackground"`

**Already correct by default, so not owned:**
- `docked_mode: true`
- `hide_cursor: 1` (on idle)
- `start_fullscreen: false`, which is overridden per launch by `--fullscreen`

**Exit confirmation.** It's shown only while a game is running: `MainWindow.OnClosing` checks `AppHost != null`. Quitting Ryubing with no game open gave no prompt, as expected. That makes `show_confirm_exit = false` essential for ES-DE launches.

**`--hide-cursor`** takes `never`, `onidle` or `always`, and ignores anything else. Not needed: the default is already on idle.

**Controllers aren't bound by retromac.**
- Ryubing stored a Pro Controller as `{"backend": "GamepadSDL2", "id": "0-00000003-057e-0000-0920-000001006803", "controller_type": "ProController", "player_index": "Player1", ...}`.
- The `0-` is the connection order. The rest is SDL's GUID, which encodes the connection type (`0003` here; Bluetooth is typically `0005`), the driver and the version.
- retromac can't predict those, and a wrong id leaves player 1 with no controller.
- **So:** retromac never writes `input_config`. Step 2's copy covers controller setup in Ryubing (Options › Settings › Input › Player 1).

**Not verified (no Switch game available):**
- ⌘Q / Console Mode quit with a game running and `show_confirm_exit` off
- launch from ES-DE with `--fullscreen --docked-mode --hide-updates`

The first tester who owns a Switch game checks these. The plan lists them as manual checks.

## Goals

- **Advanced-user warning.** Switch appears in the Systems step with the warning, unticked by default. Ticking it shows the Switch setup card.
- **Once all three steps are done:**
  - ES-DE lists `<library>/switch` and launches games in Ryubing full screen, docked, with no update prompt.
  - Quitting a game returns to ES-DE with no "are you sure?" dialog.
  - Ryubing's own window lists the same games folder.
- **Controllers.** The user sets up the controller in Ryubing, as part of step 2 (see Spike results).
- **Everything else stays the same:**
  - Network libraries work, read-only.
  - Applying settings is refused while Ryubing is open.
  - Every written file is backed up first.

## Non-goals

- Downloading, installing or updating Ryubing.
- Detecting, checking or mentioning key or firmware files, including indirectly (no file names in code, copy or tests).
- Ryubing installed anywhere except `/Applications`, or in a portable setup.
- Cemu and the Wii U.
- Title metadata or naming beyond the existing filename-only rule.

## Anti-goals (a failure even if it works)

- Switch shows in ES-DE with games that can't start because setup isn't finished.
- retromac reads, writes or names anything in Ryubing's `system/` or key areas.
- A user who never asked for Switch sees Ryubing prompts, an admin prompt, or a changed Ryubing config.
- A Ryubing update changes `Config.json` and retromac corrupts it. When it doesn't recognise the format, it writes nothing.

## Approaches

| Approach | Trade-off | Outcome |
|---|---|---|
| A. Command line only; never write Ryubing's files | Nothing to break across Ryubing versions, but quitting shows the confirmation dialog and the controller is whatever the user set | Rejected: breaks the console feel |
| **B. Command line for display, plus owned keys merged into `Config.json`** | Full console behaviour; depends on the config format (version 70), so a renamed key silently stops applying | **Chosen** |
| C. B plus a retromac-owned data folder (`--root-data-dir`) | Self-contained, but keys and firmware would sit under retromac's folder, which migrations move. Opening Ryubing from Applications would show a different, empty setup | Rejected: close to the key line, and confusing |

## Design

**Detection.**
- Ryubing counts as installed when `/Applications/Ryujinx.app/Contents/MacOS/Ryujinx` exists. That is the same path ES-DE's find rule uses.
- It counts as configurable when `~/Library/Application Support/Ryujinx/Config.json` exists, parses as JSON, and has a `version` retromac knows. The known versions are a fixed set, starting with `{70}`.

**Profile.**
- Switch selection uses the existing `systems` set.
- The step 2 tick is saved in the profile, for example `switchKeysConfirmed: Bool`. Older profiles must decode without it.

**Systems step.**
- Switch is listed even though no emulator is downloaded for it. It is never pre-selected.
- It carries the warning, in an orange caption like the Rosetta one.
- Proposed copy: *"For advanced users. Needs Ryubing, which you install yourself, and keys and firmware from your own Switch, set up inside Ryubing. retromac can't do those steps for you."*

**Switch setup card.** It appears where the user manages systems after setup and repeats the warning.
1. **Install Ryubing:** a "Get Ryubing" link to ryubing.org, with this copy: *"Move Ryujinx.app to Applications. The first time you open it, macOS blocks it; allow it in System Settings › Privacy & Security › Open Anyway."* The step ticks itself when the app is found, checked when the card appears and when retromac comes to the front.
2. **Set up Ryubing:** an "Open Ryubing" button and a "Done" button, enabled only after step 1. Proposed copy: *"Ryubing will say 'Keys not found' until you add them. In Ryubing, use the File menu to install your keys and firmware, then set up your controller under Options › Settings › Input › Player 1. Quit Ryubing and click Done."*
3. **Ready:** "Switch games now show in Play."

**When Switch is live.** `RyubingRenderer` (following `XemuRenderer`) emits anything only when all four hold:
- `.switch` is selected
- Ryubing is installed
- step 2 is confirmed
- `Config.json` is configurable (exists and has a known version)

*(Builder-check call.)* Configurability gates ES-DE too. Otherwise a Ryubing update would silently bring back the exit dialog. The card shows why Switch isn't live yet, in one of two states:
- **No `Config.json`:** "Open Ryubing once, then click Done again."
- **Unknown version:** "Ryubing was updated; retromac can't set it up until retromac updates too."

**Rendering:**
- **ES-DE.** An `ESDESystems` entry for `switch`:
  - path `<library>/switch`, with the bundled extension list
  - command `%EMULATOR_RYUJINX% --fullscreen --docked-mode --hide-updates %ROM%`
  - added to `standalones`, so the stale-entry cleanup recognises its command
  - plus a find rule for `RYUJINX` pointing at `/Applications/Ryujinx.app/Contents/MacOS/Ryujinx`
- **`Config.json`.** A new `RenderedFile` kind that merges owned top-level JSON keys into an existing file and keeps everything else as it was. It needs its own merge type and tests, like `IniConfig` and `TomlConfig`. It writes only when the file exists and its `version` is known; otherwise it emits nothing. The owned keys:
  - the exit confirmation, off
  - the games folders: `<library>/switch` added if it's missing, never removing a user's own folders
  - the update check, off
- **Not configured yet:** while Switch is selected but not configured, ES-DE gets no Switch entry, and the stale-entry cleanup removes any older one.

**Running apps.** *(Builder-check call.)* `Ryujinx.app` blocks Apply only while Switch is selected, so a user who never chose Switch is never told to quit Ryubing. `Applier` takes its blocking list from the caller, so the caller adds Ryujinx when the profile has Switch. The Migrator and Updater don't need it, because neither touches Ryubing's files. Console Mode's quit combo (`ESDESystems.emulatorApps`) includes Ryujinx for everyone, which is harmless.

**"Done" applies.** *(Builder-check call.)* Clicking Done saves the step 2 tick and re-applies at once, the same way adding a BIOS in Games does.
- **If Ryubing is still open:** the apply is refused, the tick is kept, and the card says "Quit Ryubing, then click Done." retromac never quits Ryubing itself.
- **"Ready":** step 3 shows only after an apply that made Switch live.

**Deselecting and moving the library.** *(Builder-check call.)*
- **Deselecting Switch:** retromac leaves Ryubing's settings as they are, because it's the user's own app. ES-DE's Switch entry goes, through the stale-entry cleanup.
- **The games-folder entry:** retromac records the one it added in the profile. On a library change it swaps that entry for the new one. It never touches folders the user added.

**Network library.** Same rules as other systems. ES-DE's path and `GameDirs` point at the share. Nothing writes to the share.

## Spike

Run on 2026-11-15; see Spike results above. The Ryubing app, its data folder, logs and preferences were removed afterwards.

## Left to the builder

- Where the setup card lives, matching the existing screens: Settings or Systems after setup.
- Whether step 1's tick re-checks on app activation or by polling.
- Names of the new types and the profile field.
- Exact merge semantics for the games-folder list, within the rule "add ours, never drop theirs".
