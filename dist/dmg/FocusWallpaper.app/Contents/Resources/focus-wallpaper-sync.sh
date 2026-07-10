#!/bin/sh
set -eu

SHORTCUT_NAME="Focus Wallpaper Sync"
APP_BINARY="${1:-}"
STANDARD_OUT_LOG="/tmp/FocusWallpaperSync.out.log"
STANDARD_ERROR_LOG="/tmp/FocusWallpaperSync.err.log"

# launchd appends to these files. Keep only the current run so one-second
# polling cannot grow the logs indefinitely.
: > "$STANDARD_OUT_LOG"
: > "$STANDARD_ERROR_LOG"

if [ -z "$APP_BINARY" ] || [ ! -x "$APP_BINARY" ]; then
    echo "FocusWallpaper sync: app binary is missing or not executable: $APP_BINARY" >&2
    exit 1
fi

OUTPUT=$(/usr/bin/shortcuts run "$SHORTCUT_NAME" 2>&1) || {
    STATUS=$?
    echo "FocusWallpaper sync: shortcut failed with exit code $STATUS" >&2
    echo "$OUTPUT" >&2
    exit "$STATUS"
}

ACTION=$(printf "%s" "$OUTPUT" \
    | tr "[:upper:]" "[:lower:]" \
    | tr -d "\r" \
    | awk 'NF { value = $NF } END { print value }')

case "$ACTION" in
    on|focused|focus|true|yes|1)
        "$APP_BINARY" on
        ;;
    off|none|false|no|0)
        "$APP_BINARY" off
        ;;
    *)
        echo "FocusWallpaper sync: shortcut must output 'on' or 'off'; got: $OUTPUT" >&2
        exit 2
        ;;
esac
