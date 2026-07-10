# Focus Wallpaper

Focus Wallpaper is a lightweight macOS menu bar app that applies a dedicated desktop wallpaper while Focus is active and restores the previous or configured normal wallpaper when Focus ends.

![Focus Wallpaper control window](pics/app.png)

## Highlights

- Event-driven switching through `focuswallpaper://on` and `focuswallpaper://off`
- Optional Automatic Sync through an Apple Shortcut and per-user LaunchAgent
- Independent Focus and normal wallpaper presets, including multi-display snapshots
- Start at Login support through `SMAppService` on macOS 13 and newer
- Local-only configuration, wallpaper storage, and diagnostics
- Menu bar controls plus a compact Home, Settings, and About window

Current release: see [`VERSION`](VERSION) · Minimum supported system: **macOS 12 Monterey**

## Installation

1. Download `FocusWallpaper.dmg` from the project site or the [`dist` directory](dist/FocusWallpaper.dmg).
2. Open the disk image and drag **Focus Wallpaper** to **Applications**.
3. Open the app once so macOS registers its URL scheme.
4. Choose a Focus wallpaper from the Home section.
5. Optionally choose a normal wallpaper or capture the current desktop as the normal preset.

The packaging script applies an ad-hoc signature. It does not notarize the app; a public release intended for broad distribution should use a Developer ID certificate and Apple's notarization service.

## Configure Focus switching

Focus Wallpaper supports two workflows. Direct automations are event-driven and are the recommended option for most users. Automatic Sync is useful when a polling workflow is preferable.

### Option 1: direct Focus automations

Create two personal automations in Shortcuts:

| Trigger | Action |
| --- | --- |
| Focus turns on | Open `focuswallpaper://on` |
| Focus turns off | Open `focuswallpaper://off` |

These URLs continue to work after the app is moved because macOS resolves the registered URL scheme rather than a fixed executable path.

### Option 2: Automatic Sync

Create a shortcut named exactly `Focus Wallpaper Sync` with these actions:

```text
Get Current Focus
If Current Focus has any value
    Text on
Otherwise
    Text off
End If
```

![Focus Wallpaper Sync shortcut](pics/shortcut.png)

The shortcut must return text only; do not add an **Open URLs** action. In the app's Settings section, use **Test Shortcut**, choose an interval, and enable **Automatic Sync**. Available intervals are 1, 5, 10, and 60 seconds.

Automatic Sync installs `~/Library/LaunchAgents/local.focus-wallpaper-sync.plist`. The helper runs the shortcut and invokes the app's command-line mode without bringing the control window to the foreground. Use **Repair Sync** after moving or rebuilding the app.

## How wallpaper restoration works

The app uses the first available restoration source in this order:

1. A normal wallpaper image selected by the user
2. A saved multi-display normal wallpaper snapshot
3. The desktop snapshot captured immediately before Focus Wallpaper was applied

Focus state changes are debounced, so polling does not reapply the same wallpaper when the state has not changed. Manual **Apply Focus Now** remains available when an intentional refresh is needed.

## Build from source

Requirements:

- macOS 12 or newer
- Xcode or the Xcode Command Line Tools with a Swift 6-compatible SDK
- The built-in `codesign` and `hdiutil` tools for packaging

Build the signed app bundle:

```sh
scripts/package_app.sh
```

The result is written to `dist/FocusWallpaper.app`.

The release number is defined once in [`VERSION`](VERSION). Change that file before packaging; the build validates the value and injects it into both `CFBundleShortVersionString` and `CFBundleVersion`. The project site reads the same file at runtime.

Build the compressed disk image:

```sh
scripts/package_dmg.sh
```

The result is written to `dist/FocusWallpaper.dmg`. Pass `--skip-build` to package an existing app bundle.

If more than one Xcode installation is present, select a matching toolchain explicitly:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/package_app.sh
```

The executable also exposes commands used by Automatic Sync:

```sh
dist/FocusWallpaper.app/Contents/MacOS/FocusWallpaper on
dist/FocusWallpaper.app/Contents/MacOS/FocusWallpaper off
dist/FocusWallpaper.app/Contents/MacOS/FocusWallpaper status
```

## Project structure

| Path | Purpose |
| --- | --- |
| `Sources/FocusWallpaper/main.swift` | AppKit menu bar app, wallpaper state, URL/CLI handling, and sync management |
| `Resources/` | App metadata, icon assets, sync helper, LaunchAgent template, and Shortcut recipe |
| `scripts/package_app.sh` | Release build and `.app` bundle assembly |
| `scripts/package_dmg.sh` | DMG staging and creation |
| `scripts/*_focus_sync_agent.sh` | Development-time LaunchAgent install and removal helpers |
| `index.html` and `pics/` | Static project site and screenshots |
| `todo.md` | Prioritized product and engineering roadmap |

## Troubleshooting

- **The Shortcut test fails:** confirm the shortcut is named exactly `Focus Wallpaper Sync`, returns `on` or `off`, and runs successfully in the Shortcuts app first.
- **Automatic Sync stopped after a move or rebuild:** open Settings and choose **Repair Sync** so the LaunchAgent receives the current app path.
- **The wallpaper does not restore:** configure a normal preset or use **Use Current as Normal** before applying the Focus wallpaper.
- **Start at Login needs approval:** allow Focus Wallpaper under **System Settings → General → Login Items**.
- **The build reports an SDK/compiler mismatch:** select an Xcode installation whose Swift compiler matches its macOS SDK, using `xcode-select` or `DEVELOPER_DIR`.
- **More diagnostics are needed:** the app log is `~/Library/Logs/FocusWallpaper.log`; current Automatic Sync output is in `/tmp/FocusWallpaperSync.out.log` and `/tmp/FocusWallpaperSync.err.log`.

## Current limitations

- The app tracks active versus inactive Focus state; it does not yet assign wallpapers to individual named Focus modes.
- Named mode detection is expected to rely on Shortcuts because the public Focus Status API does not expose the active mode name to this workflow.
- The repository does not yet include automated tests or a notarized release pipeline. Both are prioritized in [`todo.md`](todo.md).

## Privacy

Focus Wallpaper has no account, analytics, or network service. Imported images are copied to `~/Library/Application Support/FocusWallpaper`, preferences use macOS `UserDefaults`, and diagnostic logs remain on the Mac.

## License

Focus Wallpaper is available under the [MIT License](LICENSE).
