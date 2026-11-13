#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Fails if the package depends on anything not listed in scripts/allowed-deps.txt.
set -euo pipefail
cd "$(dirname "$0")/.."
deps=$(swift package show-dependencies --format flatlist)
offenders=()
while IFS= read -r dep; do
    [[ -z "$dep" ]] && continue
    grep -qxF "$dep" scripts/allowed-deps.txt || offenders+=("$dep")
done <<< "$deps"
if (( ${#offenders[@]} > 0 )); then
    echo "Dependencies not in scripts/allowed-deps.txt:"
    printf '  %s\n' "${offenders[@]}"
    exit 1
fi
