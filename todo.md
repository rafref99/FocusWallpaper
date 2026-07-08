# Focus Wallpaper Todo

## Completed

- [x] Add Automatic Sync status: installed state, last sync time, last result, and recent error awareness for the status icon/logs.
- [x] Add a `Test Shortcut` button that runs `Focus Wallpaper Sync` once and reports whether it returned `on` or `off`.
- [x] Add a `Repair Sync` action that rewrites the LaunchAgent using the current app path.
- [x] Add fast Automatic Sync intervals: 1 second, 5 seconds, 10 seconds, and 1 minute.
- [x] Change the menu bar icon based on state: idle, Focus active, and sync error.
- [x] Clean up the control window into Home, Settings, and About sections with a compact left navigation rail.
- [x] Add a compact first-run setup flow when no Focus wallpaper is configured.
- [x] Bundle a Shortcut template and add an `Open Shortcut Template` button.
- [x] Replace the custom Start at Login LaunchAgent with `SMAppService` on supported macOS versions.
- [x] Add a distributable DMG packaging script.
- [x] Create an HTML showcase page with download and setup information.

## Focus Mode Detection

- [ ] Add support for named Focus modes, not only active/inactive Focus state.
- [ ] Prefer Shortcuts as the named-mode source: update the sync shortcut so `Get Current Focus` returns the current Focus name, then pass that mode name to Focus Wallpaper.
- [ ] Add URL trigger support for named modes, for example `focuswallpaper://mode/work`, while keeping `focuswallpaper://on` and `focuswallpaper://off` for simple setups.
- [ ] Add fallback behavior for unknown or unsupported modes: use the default Focus wallpaper or restore the normal wallpaper.
- [ ] Document the limitation that Apple's public Focus Status API can indicate whether Focus is active, but app workflows need Shortcuts to identify the specific Focus mode name.

## Per-Focus Wallpapers

- [ ] Store separate wallpaper choices per Focus mode.
- [ ] Add a default Focus wallpaper that applies when a named Focus mode has no specific wallpaper.
- [ ] Add import, replace, reveal, and clear actions for each Focus mode wallpaper.
- [ ] Support restoring the user's normal wallpaper after any Focus mode ends.
- [ ] Decide how normal wallpaper presets should work with multiple displays and multiple Focus modes.

## Wallpaper Picker and Preview UI

- [ ] Replace the simple set-wallpaper rows with a visual wallpaper manager.
- [ ] Add image previews for Focus wallpaper, normal wallpaper, and each named Focus mode wallpaper.
- [ ] Add drag-and-drop wallpaper import.
- [ ] Add quick actions near each preview: Choose, Reveal in Finder, Clear, and Apply Now.
- [ ] Add empty states that clearly show what still needs setup.
- [ ] Add preview handling for missing or moved wallpaper files.

## Quality and Performance

- [ ] Move all LaunchAgent install, repair, and interval-change work off the main UI thread.
- [ ] Debounce repeated Focus state updates so the same wallpaper is not re-applied unnecessarily.
- [ ] Cache wallpaper metadata and preview images to keep the control window responsive.
- [ ] Add a lightweight diagnostics export with app version, sync plist contents, recent logs, and configured paths.
- [ ] Add validation that Automatic Sync was actually reloaded with the requested interval and throttle values.
- [ ] Add better failure recovery when the Shortcut is missing, returns invalid text, or macOS blocks automation access.
- [ ] Add focused tests for plist generation, interval selection, URL parsing, and mode-name normalization.

## Packaging and Documentation

- [ ] Keep screenshots current after each UI pass.
- [ ] Add release notes for each packaged version.
- [ ] Decide whether the DMG should include the Shortcut template as a separate readable file.
- [ ] Add a troubleshooting section for Shortcut permissions and LaunchAgent reload issues.
