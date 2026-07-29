#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ICONSET="$ROOT/build/AppIcon.iconset"
ICNS="$ROOT/Resources/AppIcon.icns"

rm -rf "$ICONSET"
mkdir -p "$ROOT/build"
swift run Puplet --dump-icon "$ICONSET"
iconutil --convert icns --output "$ICNS" "$ICONSET"

echo "Wrote ${ICNS#$ROOT/}"
