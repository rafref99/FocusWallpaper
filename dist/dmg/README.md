# Focus Wallpaper

Focus Wallpaper 1.1.0 is a macOS menu bar app that changes your desktop wallpaper when Focus is active and restores your normal wallpaper when Focus ends.

The app supports direct Focus automations with URL actions and an optional Automatic Sync shortcut for polling Focus state in the background.

## Build

```sh
chmod +x scripts/package_app.sh
scripts/package_app.sh
```

The app bundle is created at:

```text
dist/FocusWallpaper.app
```

With Xcode installed, you can open `Package.swift` to inspect or build the Swift source. Use `scripts/package_app.sh` for the final app bundle because it adds the app icon, `Info.plist`, bundled resources, and code signature.

To create a distributable DMG:

```sh
scripts/package_dmg.sh
```

The DMG is created at:

```text
dist/FocusWallpaper.dmg
```

Use `scripts/package_dmg.sh --skip-build` if `dist/FocusWallpaper.app` already exists. The static showcase page is `index.html`, and its download links point to the generated DMG.

## App Setup

![Focus Wallpaper control window](pics/app.png)

1. Open `dist/FocusWallpaper.app`.
2. On first run, use the Home section to choose a Focus wallpaper.
3. Optionally choose `Use Current as Normal` or `Choose Normal Wallpaper...`.
4. Use Settings to enable Automatic Sync or Start at Login.
5. Use About to inspect the app version, developer, build date, bundle ID, URL scheme, app path, and log path.

The control window uses a left navigation rail for Home, Settings, and About. If you close the window, open it again from the Focus Wallpaper menu bar icon.

If no normal wallpaper is set, the app captures the current wallpaper before applying the Focus wallpaper and restores that captured wallpaper when Focus ends.

## Menu Bar

![Focus Wallpaper menu bar controls](pics/menubar.png)

The menu bar menu is intentionally compact. It includes:

- App name
- Focus mode state
- Show Control Window
- Start at Login
- Set Focus On and Set Focus Off when Automatic Sync is off
- Quit

The menu bar icon changes for idle, Focus active, and sync-error states.

## Shortcut Setup

Open Focus Wallpaper once after moving the app so macOS registers its URL scheme.

Create two Shortcuts automations:

- Focus turns on: open `focuswallpaper://on`
- Focus turns off: open `focuswallpaper://off`

These URL triggers keep the shortcut working even if the app is moved.

## Automatic Sync

If you prefer polling with one shortcut, create a shortcut named exactly `Focus Wallpaper Sync`:

```text
Get Current Focus
If Current Focus has any value
    Text on
Otherwise
    Text off
End If
```

![Focus Wallpaper Sync shortcut](pics/shortcut.png)

Do not use `Open URLs` inside this polling shortcut. The LaunchAgent reads the shortcut output and calls Focus Wallpaper in the background, which avoids stealing keyboard focus while you type.

Automatic Sync intervals are:

- Every second
- Every 5 seconds
- Every 10 seconds, the default
- Every minute

Automatic Sync is controlled from the app. Disabling it stops and removes the sync LaunchAgent. Quitting Focus Wallpaper also stops the sync LaunchAgent, and the app starts it again the next time Focus Wallpaper opens if Automatic Sync was enabled.

Use `Open Shortcut Template` to open the bundled setup recipe, `Test Shortcut` to check that `Focus Wallpaper Sync` returns `on` or `off` without changing your wallpaper, and `Repair Sync` after moving or rebuilding the app to rewrite and reload the LaunchAgent with the current app path and interval settings.

## Current Scope

Focus Wallpaper currently tracks whether Focus is active or inactive. Separate wallpaper choices for individual Focus modes are planned in `todo.md`; the likely implementation path is to use Shortcuts to pass the current Focus mode name to the app.
