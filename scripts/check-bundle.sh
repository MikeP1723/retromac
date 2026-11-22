#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Fails unless build/retromac.app is a release build of the given version: a development build never
# self-updates, so shipping one would strand every user on it.
set -euo pipefail
cd "$(dirname "$0")/.."
version="$1"
app=build/retromac.app
for plist in "$app/Contents/Info.plist" "$app/Contents/Library/LoginItems/retromac-console.app/Contents/Info.plist"; do
    if /usr/libexec/PlistBuddy -c "Print :RetromacDevelopmentBuild" "$plist" >/dev/null 2>&1; then
        echo "error: $plist is marked as a development build" >&2
        exit 1
    fi
    actual="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$plist")"
    if [[ "$actual" != "$version" ]]; then
        echo "error: $plist has version $actual, expected $version" >&2
        exit 1
    fi
done
for resources in "$app/Contents/Resources" "$app/Contents/Library/LoginItems/retromac-console.app/Contents/Resources"; do
    for file in Assets.car AppIcon.icns; do
        if [[ ! -s "$resources/$file" ]]; then
            echo "error: $resources/$file is missing (build with Xcode's actool)" >&2
            exit 1
        fi
    done
done
codesign --verify --deep --strict "$app"
echo "$app is release $version"
