#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds build/retromac.app (ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --product retromac
swift build -c release --arch arm64 --product retromac-console
bindir="$(swift build -c release --arch arm64 --show-bin-path)"

app=build/retromac.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bindir/retromac" "$app/Contents/MacOS/retromac"
# Console Mode's agent is its own app with its own bundle ID: run from Contents/MacOS it would register
# as retromac itself, and opening retromac would only reach the windowless agent.
agent="$app/Contents/Library/LoginItems/retromac-console.app"
mkdir -p "$agent/Contents/MacOS"
cp "$bindir/retromac-console" "$agent/Contents/MacOS/retromac-console"
cp Support/ConsoleInfo.plist "$agent/Contents/Info.plist"
cp Support/Info.plist "$app/Contents/Info.plist"
if [[ -n "${RETROMAC_VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RETROMAC_VERSION" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RETROMAC_VERSION" "$agent/Contents/Info.plist"
fi
# Into Contents/Resources so Bundle.main finds them (SwiftPM's resource bundle would
# have to sit at the .app root, which breaks code signing).
cp Sources/RetromacCore/Resources/*.json "$app/Contents/Resources/"
# Inside out: the outer signature seals the nested app's.
codesign --force --sign - "$agent"
codesign --force --sign - "$app"
echo "$app"
