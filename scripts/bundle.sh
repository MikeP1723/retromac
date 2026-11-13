#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds build/retromac.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --product retromac
bin="$(swift build -c release --arch arm64 --show-bin-path)/retromac"

app=build/retromac.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin" "$app/Contents/MacOS/retromac"
cp Support/Info.plist "$app/Contents/Info.plist"
# Into Contents/Resources so Bundle.main finds them (SwiftPM's resource bundle would
# have to sit at the .app root, which breaks code signing).
cp Sources/RetromacCore/Resources/*.json "$app/Contents/Resources/"
codesign --force --sign - "$app"
echo "$app"
