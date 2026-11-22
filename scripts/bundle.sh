#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Builds build/retromac.app: ad-hoc signed, or with RETROMAC_SIGN_IDENTITY (a Developer ID Application
# identity in the keychain) signed for notarization, with the hardened runtime and a secure timestamp.
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
    # Without a version this is a development build, which never offers to "update" itself to a release.
    /usr/libexec/PlistBuddy -c "Delete :RetromacDevelopmentBuild" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $RETROMAC_VERSION" "$agent/Contents/Info.plist"
fi
# Into Contents/Resources so Bundle.main finds them (SwiftPM's resource bundle would
# have to sit at the .app root, which breaks code signing).
cp Sources/RetromacCore/Resources/*.json "$app/Contents/Resources/"
# The icon: Assets.car for macOS 26's Liquid Glass and AppIcon.icns for earlier releases. actool ships with Xcode,
# not the Command Line Tools; without it the build has the generic icon (check-bundle.sh refuses that for a release).
if xcrun --find actool >/dev/null 2>&1; then
    icon="$(mktemp -d)"
    # An absolute path: actool can't open a relative one, and reports that with exit status 0.
    xcrun actool "$PWD/Support/AppIcon.icon" --compile "$icon" --app-icon AppIcon --platform macosx \
        --minimum-deployment-target 14.0 --output-partial-info-plist "$icon/partial.plist" >/dev/null
    [[ -s "$icon/Assets.car" && -s "$icon/AppIcon.icns" ]] || { echo "error: actool produced no icon" >&2; exit 1; }
    mkdir -p "$agent/Contents/Resources"
    for dest in "$app/Contents/Resources" "$agent/Contents/Resources"; do
        cp "$icon/Assets.car" "$icon/AppIcon.icns" "$dest/"
    done
    rm -rf "$icon"
else
    echo "warning: actool not found (install Xcode); building without the app icon" >&2
fi
# Inside out: the outer signature seals the nested app's.
identity="${RETROMAC_SIGN_IDENTITY:--}"
flags=(--force --sign "$identity")
[[ "$identity" != "-" ]] && flags+=(--options runtime --timestamp)
codesign "${flags[@]}" "$agent"
codesign "${flags[@]}" "$app"
echo "$app"
