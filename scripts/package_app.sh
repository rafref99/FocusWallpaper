#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CACHE="$ROOT/.build-cache"
SPM="$CACHE/swiftpm"
APP="$ROOT/dist/FocusWallpaper.app"
VERSION_FILE="$ROOT/VERSION"

if [ ! -f "$VERSION_FILE" ]; then
    echo "Missing version file: $VERSION_FILE" >&2
    exit 1
fi

APP_VERSION=$(tr -d '[:space:]' < "$VERSION_FILE")
if ! printf '%s\n' "$APP_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "VERSION must contain a semantic version such as 1.2.3." >&2
    exit 2
fi

mkdir -p "$CACHE/clang" "$CACHE/swift" "$SPM/cache" "$SPM/configuration" "$SPM/security"

cd "$ROOT"

CLANG_MODULE_CACHE_PATH="$CACHE/clang" swift build \
    --cache-path "$SPM/cache" \
    --config-path "$SPM/configuration" \
    --security-path "$SPM/security" \
    --manifest-cache local \
    --disable-sandbox \
    --configuration release \
    --scratch-path "$ROOT/.build" \
    -Xswiftc -module-cache-path \
    -Xswiftc "$CACHE/swift"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/.build/release/FocusWallpaper" "$APP/Contents/MacOS/FocusWallpaper"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $APP_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $APP_VERSION" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
cp "$ROOT/Resources/focus-wallpaper-sync.sh" "$APP/Contents/Resources/focus-wallpaper-sync.sh"
cp "$ROOT/Resources/Focus Wallpaper Sync Template.txt" "$APP/Contents/Resources/Focus Wallpaper Sync Template.txt"
chmod +x "$APP/Contents/MacOS/FocusWallpaper"
chmod +x "$APP/Contents/Resources/focus-wallpaper-sync.sh"

if command -v codesign >/dev/null 2>&1; then
    codesign --force --sign - "$APP" >/dev/null
fi

echo "$APP (version $APP_VERSION)"
