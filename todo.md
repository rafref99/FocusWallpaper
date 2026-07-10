# Focus Wallpaper Roadmap

This roadmap is ordered by dependency and user impact. A task is complete only when its behavior is covered by an automated check or a documented manual verification, user-facing failures are actionable, and README/release notes are updated where relevant.

## Completed foundation

- [x] Provide direct `focuswallpaper://on` and `focuswallpaper://off` actions plus CLI equivalents.
- [x] Preserve a configured normal wallpaper or a per-display snapshot for restoration.
- [x] Add Automatic Sync with 1, 5, 10, and 60 second intervals.
- [x] Add Automatic Sync status, Shortcut testing, LaunchAgent repair, and recent error reporting.
- [x] Use `SMAppService` for Start at Login on supported macOS versions.
- [x] Add the Home, Settings, and About control window, first-run guidance, and state-aware menu bar icon.
- [x] Package an app bundle and DMG and publish a static showcase page.
- [x] Debounce repeated CLI and URL Focus updates so polling does not reapply unchanged wallpaper state.
- [x] Move Shortcut and LaunchAgent install/repair/update work off the main UI thread.
- [x] Bound app and sync log growth and read only the tail of sync logs.
- [x] Validate Automatic Sync intervals in both the app and development installer.
- [x] Use a central `VERSION` file for app packaging and the static project site.

## Milestone 1 — Reliability and testability

Goal: make the existing active/inactive workflow safe to change and straightforward to diagnose.

- [ ] Extract wallpaper transitions, URL parsing, Shortcut output parsing, and interval rules from `main.swift` into testable modules.
- [ ] Add an XCTest target covering state transitions, URL variants, Shortcut normalization, interval validation, plist generation, and per-display restoration fallback.
- [ ] Make LaunchAgent updates transactional: preserve the last working plist, reload it on failure, and verify the requested `StartInterval` and `ThrottleInterval` after bootstrap.
- [ ] Distinguish “configured” from “file available”; surface missing or moved image files before attempting a transition.
- [ ] Consolidate the duplicated CLI and AppDelegate wallpaper transition paths behind one state controller.
- [ ] Add recovery guidance for a missing Shortcut, invalid output, denied Automation access, and a loaded-but-unhealthy LaunchAgent.
- [ ] Add a diagnostics export containing app/build metadata, sanitized configured paths, generated plist values, and recent bounded logs.

Acceptance criteria:

- `swift test` covers the shared state and parsing layer.
- A failed LaunchAgent update leaves the previous working configuration active.
- Missing files and permission failures appear in the UI with a specific recovery action.

## Milestone 2 — Named Focus modes

Goal: map individual Focus modes to individual wallpapers without breaking simple on/off automations.

- [ ] Define canonical mode-name normalization and a stable storage model for named wallpaper mappings.
- [ ] Extend the sync Shortcut contract to return the active Focus name or `off`.
- [ ] Support URL actions such as `focuswallpaper://mode/work`, retaining `on` and `off` for backward compatibility.
- [ ] Add a default Focus wallpaper for active modes without an explicit mapping.
- [ ] Define unknown-mode behavior and preserve the last pre-Focus desktop across transitions between named modes.
- [ ] Document that Shortcuts supplies the mode name because the public Focus Status API does not expose it for this workflow.

Acceptance criteria:

- Switching Work → Personal changes wallpaper without restoring the normal desktop between modes.
- Ending any named Focus restores the correct pre-Focus multi-display state.
- Existing on/off automations continue to behave exactly as before.

## Milestone 3 — Wallpaper manager

Goal: make multi-mode configuration visual and resilient.

- [ ] Add previews for the normal, default Focus, and named-mode wallpapers.
- [ ] Add drag-and-drop import plus Choose, Replace, Reveal, Clear, and Apply Now actions.
- [ ] Cache scaled previews and file metadata; invalidate cache entries when the source changes.
- [ ] Add useful empty, missing-file, and unsupported-image states.
- [ ] Define normal presets for multiple displays, Spaces, and changing display configurations.
- [ ] Add accessibility labels, keyboard navigation, and a VoiceOver pass for the manager.

## Milestone 4 — Release engineering

Goal: make every published artifact reproducible, verifiable, and easy to install.

- [ ] Add CI checks for debug/release builds, `swift test`, shell syntax, plist validation, and static-site links.
- [ ] Stop tracking Xcode user state and generated app/DMG staging directories; publish versioned DMGs as release artifacts instead.
- [ ] Add semantic version tags, release notes, and SHA-256 checksums for published artifacts.
- [ ] Add Developer ID signing, notarization, and stapling to the release pipeline without storing credentials in the repository.
- [ ] Decide whether the Shortcut recipe should remain a readable text file, become an importable Shortcut, or ship as both.
- [ ] Refresh screenshots as part of each UI release checklist.

Acceptance criteria:

- A clean checkout can produce the same app structure and passing checks with one documented command.
- Published DMGs are signed, notarized, checksummed, and linked from the project site.
