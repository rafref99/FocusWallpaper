# Focus Wallpaper Todo

## Reliability

- [ ] Add Automatic Sync health/status: installed/running state, last sync time, last result, and last error.
- [ ] Add a `Test Shortcut` button that runs `Focus Wallpaper Sync` once and reports whether it returned `on` or `off`.
- [ ] Add a `Repair Sync` action that rewrites the LaunchAgent using the current app path.
- [ ] Surface recent sync errors in the setup window or menu bar menu instead of relying on logs.

## User Experience

- [ ] Change the menu bar icon based on state: idle, Focus active, and sync error.
- [ ] Clean up the setup window into clearer groups: Wallpapers, Automatic Sync, Startup, and Manual Actions.
- [ ] Add a compact first-run setup flow when no Focus wallpaper is configured.
- [ ] Bundle a Shortcut template and add an `Open Shortcut Template` button.

## Platform Integration

- [ ] Replace the custom Start at Login LaunchAgent with `SMAppService` on supported macOS versions.
- [ ] Add a distributable DMG packaging script.
