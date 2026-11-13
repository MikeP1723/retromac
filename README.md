# retromac

retromac is a guided installer and configurator for retro game emulation on Apple Silicon Macs. It installs RetroArch, ES-DE, and free/open-source emulator cores from their official upstream releases, then generates display-aware and controller-aware configuration from a short wizard, so the Mac is ready to play on a TV without hand-editing config files. Existing configuration is always backed up before it is changed.

## Build

```sh
swift build
swift test
scripts/bundle.sh        # produces build/retromac.app (ad-hoc signed)
```

Requires macOS 14+ on Apple Silicon and a Swift 6 toolchain (Xcode or Command Line Tools).

## Opening an unsigned app

retromac is not notarized. On macOS 15 and later, the first launch is blocked; open
**System Settings › Privacy & Security**, scroll to the message about retromac, and click **Open Anyway**.

## What retromac does not provide

retromac does not provide games, BIOS files, firmware, or keys. You supply your own legally obtained dumps.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
