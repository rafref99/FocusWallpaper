#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LABEL="local.focus-wallpaper-sync"
SOURCE="$ROOT/Resources/$LABEL.plist"
DESTINATION="$HOME/Library/LaunchAgents/$LABEL.plist"
INTERVAL_SECONDS="${1:-10}"
THROTTLE_SECONDS="$INTERVAL_SECONDS"
APP="$ROOT/dist/FocusWallpaper.app"
HELPER="$APP/Contents/Resources/focus-wallpaper-sync.sh"
BINARY="$APP/Contents/MacOS/FocusWallpaper"

if [ "$THROTTLE_SECONDS" -gt 10 ]; then
    THROTTLE_SECONDS=10
fi

if [ ! -x "$HELPER" ] || [ ! -x "$BINARY" ]; then
    echo "Build the app first: scripts/package_app.sh" >&2
    exit 1
fi

mkdir -p "$HOME/Library/LaunchAgents"
cp "$SOURCE" "$DESTINATION"
/usr/libexec/PlistBuddy -c "Set :StartInterval $INTERVAL_SECONDS" "$DESTINATION"
/usr/libexec/PlistBuddy -c "Set :ThrottleInterval $THROTTLE_SECONDS" "$DESTINATION"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:1 $HELPER" "$DESTINATION"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:2 $BINARY" "$DESTINATION"

launchctl bootout "gui/$(id -u)" "$DESTINATION" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$DESTINATION"
launchctl enable "gui/$(id -u)/$LABEL"
launchctl kickstart -k "gui/$(id -u)/$LABEL"

echo "Installed $LABEL"
echo "Plist: $DESTINATION"
echo "Interval: ${INTERVAL_SECONDS}s"
echo "Logs:"
echo "  /tmp/FocusWallpaperSync.out.log"
echo "  /tmp/FocusWallpaperSync.err.log"
