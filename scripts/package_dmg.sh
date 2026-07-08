#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
APP="$ROOT/dist/FocusWallpaper.app"
STAGING="$ROOT/dist/dmg"
DMG="$ROOT/dist/FocusWallpaper.dmg"
VOLUME_NAME="Focus Wallpaper"

if [ "${1:-}" != "--skip-build" ]; then
    "$ROOT/scripts/package_app.sh" >/dev/null
fi

if [ ! -d "$APP" ]; then
    echo "Missing app bundle: $APP" >&2
    echo "Run scripts/package_app.sh first or omit --skip-build." >&2
    exit 1
fi

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"

cp -R "$APP" "$STAGING/FocusWallpaper.app"
cp "$ROOT/README.md" "$STAGING/README.md"

if [ -d /Applications ]; then
    ln -s /Applications "$STAGING/Applications"
fi

hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG"

echo "$DMG"
