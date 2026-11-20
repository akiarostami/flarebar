#!/bin/bash
# Regenerates Resources/AppIcon.icns from the mark drawn in Sources/Flarebar/BrandIcon.swift.
# Run it after changing the mark; the result is committed, so builds do not need it.
set -euo pipefail
cd "$(dirname "$0")/.."
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
swiftc -O -o "$WORK/make-icon" Sources/Flarebar/BrandIcon.swift scripts/icon/main.swift
"$WORK/make-icon" "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
