# Third-party notices

## Vendored code

Phase 1 vendors no third-party code. retromac links only Apple system frameworks.

## Components downloaded at runtime

retromac downloads the following from their official upstream locations and verifies each by SHA-256. It does not redistribute them. Licenses are as each upstream project declares them.

Ryubing (Nintendo Switch) is installed by the user; retromac neither downloads nor redistributes it.

| Component | Version | License | Source |
|---|---|---|---|
| RetroArch (Metal, universal) | 1.22.2 | GPL-3.0-or-later | https://buildbot.libretro.com/stable/1.22.2/apple/osx/universal/RetroArch_Metal.dmg |
| ES-DE (arm64) | 3.5.0 | MIT | https://gitlab.com/es-de/emulationstation-de/-/releases |
| Dolphin (universal) | 2609 | GPL-2.0-or-later | https://dl.dolphin-emu.org/releases/2609/ |
| xemu (universal) | 0.8.139 | GPL-2.0 | https://github.com/xemu-project/xemu/releases/tag/v0.8.139 |
| xemu HDD image | 1.0 | Copyright-free formatted image | https://github.com/xemu-project/xemu-hdd-image/releases/tag/1.0 |
| PCSX2 (Qt) | 2.8.2 | GPL-3.0 | https://github.com/PCSX2/pcsx2/releases/tag/v2.8.2 |
| Mesen libretro core | 0.9.9 | GPL-3.0-or-later | https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/ |
| bsnes libretro core | 115 | GPL-3.0-only | https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/ |
| BlastEm libretro core | v0.6.3-pre | GPL-3.0-or-later | https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/ |
| Mupen64Plus-Next libretro core | 1.0 | GPL-2.0-or-later | https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/ |
| PCSX-ReARMed libretro core | r24 | GPL-2.0 | https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/ |
| Beetle Saturn libretro core | v0.9.45.1 | GPL-2.0 | https://buildbot.libretro.com/nightly/apple/osx/arm64/latest/ |

libretro publishes macOS cores only at a rolling `latest/` location, so cores are fetched over HTTPS from buildbot.libretro.com without a pinned checksum (the same trust RetroArch's own core downloader uses); the checksum of what was installed is recorded locally.

## Shader presets referenced (shipped with RetroArch, not by retromac)

| Preset | License |
|---|---|
| crt/crt-guest-advanced.slangp | GPL-2.0-or-later |
| crt/crt-easymode.slangp | GPL (unversioned; any version) |
| pixel-art-scaling/sharp-bilinear-simple.slangp | Public domain |
