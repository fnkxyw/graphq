#!/bin/bash
# Builds graphq with SwiftPM and wraps it into build/graphq.app
# (Info.plist with document types, resources, app icon, ad-hoc signature).
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build -c "$CONFIG" --product graphq
BIN="$(swift build -c "$CONFIG" --show-bin-path)"

APP="$ROOT/build/graphq.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN/graphq" "$APP/Contents/MacOS/graphq"
cp "$ROOT/Support/Info.plist" "$APP/Contents/Info.plist"
cp -R "$BIN/graphq_SketchRender.bundle" "$APP/Contents/Resources/"

# App icon is generated from code so the repo has no binary design assets.
ICON_CACHE="$ROOT/build/AppIcon.icns"
if [ ! -f "$ICON_CACHE" ] || [ "$ROOT/scripts/make-icon.swift" -nt "$ICON_CACHE" ]; then
    ICONSET="$ROOT/build/AppIcon.iconset"
    rm -rf "$ICONSET" && mkdir -p "$ICONSET"
    swift "$ROOT/scripts/make-icon.swift" "$ICONSET"
    iconutil -c icns "$ICONSET" -o "$ICON_CACHE"
fi
cp "$ICON_CACHE" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
# Make Launch Services pick up the document types right away.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
