# retromac

retromac is a guided installer and configurator for retro game emulation on Apple Silicon Macs. It installs RetroArch, ES-DE, and free/open-source emulator cores from their official upstream releases, then generates display-aware and controller-aware configuration from a short wizard, so the Mac is ready to play on a TV without hand-editing config files. Existing configuration is always backed up before it is changed.

## Consoles

| Console | Emulator |
|---|---|
| NES, Super Nintendo, Genesis, Nintendo 64 | RetroArch (Mesen, bsnes, BlastEm, Mupen64Plus-Next) |
| PlayStation, Sega Saturn | RetroArch (PCSX-ReARMed, Beetle Saturn) |
| GameCube, Wii | Dolphin |
| PlayStation 2 | PCSX2 (runs under Rosetta; macOS asks once to install it) |
| Xbox | xemu |
| Nintendo Switch | Ryubing, installed by you (advanced, see below) |

Saturn, PlayStation 2 and Xbox need BIOS files you supply, and PlayStation is more compatible with one; retromac
lists which ones are missing.

### Nintendo Switch

Switch is for advanced users. retromac never downloads Ryubing. You install it yourself and finish Ryubing's
own setup, then tick Switch in retromac; once you confirm that setup is done, retromac adds your library's
`switch` folder to Ryubing and lists Switch games in ES-DE.

### Not supported

Wii U isn't supported: Cemu has no native Apple Silicon release. Wii U games dropped into the library are
skipped, not copied.

## Build

```sh
swift build
swift test
scripts/bundle.sh        # produces build/retromac.app (ad-hoc signed)
```

Requires macOS 14+ on Apple Silicon and a Swift 6 toolchain (Xcode or Command Line Tools).

## What retromac does not provide

retromac does not provide games, BIOS files, firmware, or keys. You supply your own legally obtained dumps.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
