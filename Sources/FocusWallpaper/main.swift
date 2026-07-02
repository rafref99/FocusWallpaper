import AppKit
import Darwin
import Foundation
import Intents
import UniformTypeIdentifiers

private enum DefaultsKey {
    static let focusWallpaperURL = "focusWallpaperURL"
    static let normalWallpaperURL = "normalWallpaperURL"
    static let normalSnapshot = "normalSnapshot"
    static let pendingRestoreSnapshot = "pendingRestoreSnapshot"
    static let focusWallpaperApplied = "focusWallpaperApplied"
    static let shortcutFocusActive = "shortcutFocusActive"
    static let automaticSyncEnabled = "automaticSyncEnabled"
    static let automaticSyncInterval = "automaticSyncInterval"
}

private typealias WallpaperSnapshot = [String: String]

private final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    let url: URL
    private let lock = NSLock()

    private init() {
        let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
        url = directory.appendingPathComponent("FocusWallpaper.log")
    }

    func write(_ message: String) {
        lock.lock()
        defer { lock.unlock() }

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let line = "[\(Self.timestamp())] \(message)\n"
            let data = Data(line.utf8)

            if FileManager.default.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url)
            }
        } catch {
            NSLog("FocusWallpaper log error: \(error.localizedDescription)")
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: Date())
    }
}

private final class Preferences {
    private let defaults = UserDefaults.standard

    var focusWallpaperURL: URL? {
        get { url(forKey: DefaultsKey.focusWallpaperURL) }
        set { set(newValue, forKey: DefaultsKey.focusWallpaperURL) }
    }

    var normalWallpaperURL: URL? {
        get { url(forKey: DefaultsKey.normalWallpaperURL) }
        set { set(newValue, forKey: DefaultsKey.normalWallpaperURL) }
    }

    var normalSnapshot: WallpaperSnapshot {
        get { snapshot(forKey: DefaultsKey.normalSnapshot) }
        set { defaults.set(newValue, forKey: DefaultsKey.normalSnapshot) }
    }

    var pendingRestoreSnapshot: WallpaperSnapshot {
        get { snapshot(forKey: DefaultsKey.pendingRestoreSnapshot) }
        set { defaults.set(newValue, forKey: DefaultsKey.pendingRestoreSnapshot) }
    }

    var focusWallpaperApplied: Bool {
        get { defaults.bool(forKey: DefaultsKey.focusWallpaperApplied) }
        set { defaults.set(newValue, forKey: DefaultsKey.focusWallpaperApplied) }
    }

    var shortcutFocusActive: Bool {
        get { defaults.bool(forKey: DefaultsKey.shortcutFocusActive) }
        set { defaults.set(newValue, forKey: DefaultsKey.shortcutFocusActive) }
    }

    var automaticSyncEnabled: Bool {
        get { defaults.bool(forKey: DefaultsKey.automaticSyncEnabled) }
        set { defaults.set(newValue, forKey: DefaultsKey.automaticSyncEnabled) }
    }

    var automaticSyncInterval: Int {
        get {
            let interval = defaults.integer(forKey: DefaultsKey.automaticSyncInterval)
            return interval > 0 ? interval : 10
        }
        set { defaults.set(newValue, forKey: DefaultsKey.automaticSyncInterval) }
    }

    func clearNormalPreset() {
        normalWallpaperURL = nil
        defaults.removeObject(forKey: DefaultsKey.normalSnapshot)
    }

    func clearPendingRestore() {
        defaults.removeObject(forKey: DefaultsKey.pendingRestoreSnapshot)
    }

    private func url(forKey key: String) -> URL? {
        guard let rawValue = defaults.string(forKey: key) else {
            return nil
        }
        return URL(string: rawValue)
    }

    private func set(_ url: URL?, forKey key: String) {
        defaults.set(url?.absoluteString, forKey: key)
    }

    private func snapshot(forKey key: String) -> WallpaperSnapshot {
        defaults.dictionary(forKey: key) as? WallpaperSnapshot ?? [:]
    }
}

private final class WallpaperController {
    private let workspace = NSWorkspace.shared

    func snapshot() -> WallpaperSnapshot {
        var snapshot: WallpaperSnapshot = [:]

        for screen in NSScreen.screens {
            guard let url = workspace.desktopImageURL(for: screen) else {
                continue
            }
            snapshot[displayID(for: screen)] = url.absoluteString
        }

        return snapshot
    }

    func setWallpaperOnAllScreens(_ url: URL) throws {
        for screen in NSScreen.screens {
            try setWallpaper(url, for: screen)
        }
    }

    func restore(_ snapshot: WallpaperSnapshot) throws {
        guard !snapshot.isEmpty else {
            return
        }

        let fallback = snapshot.values.compactMap(resolveURL).first

        for screen in NSScreen.screens {
            let displayID = displayID(for: screen)
            let url = snapshot[displayID].flatMap(resolveURL) ?? fallback

            guard let url else {
                continue
            }

            try setWallpaper(url, for: screen)
        }
    }

    private func setWallpaper(_ url: URL, for screen: NSScreen) throws {
        let options = workspace.desktopImageOptions(for: screen) ?? [:]
        try workspace.setDesktopImageURL(url, for: screen, options: options)
    }

    private func resolveURL(_ rawValue: String) -> URL? {
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: rawValue)
    }

    private func displayID(for screen: NSScreen) -> String {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        if let number = screen.deviceDescription[key] as? NSNumber {
            return number.stringValue
        }
        return screen.localizedName
    }
}

private final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()

    let directoryURL: URL

    private init() {
        directoryURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FocusWallpaper", isDirectory: true)
    }

    func ensureDirectoryExists() throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func importImage(at sourceURL: URL, named baseName: String) throws -> URL {
        try ensureDirectoryExists()

        let fileExtension = sourceURL.pathExtension.nilIfEmpty ?? "image"
        let destinationURL = directoryURL.appendingPathComponent("\(baseName).\(fileExtension)")

        if sourceURL.standardizedFileURL == destinationURL.standardizedFileURL {
            return sourceURL
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }
}

private final class LaunchAgentController {
    private let label = "local.focus-wallpaper"

    var launchAgentURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return libraryURL
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    func install() throws {
        guard let bundlePath = Bundle.main.bundlePath.nilIfEmpty else {
            throw AppError("Could not determine the app bundle path.")
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/usr/bin/open",
                "-g",
                bundlePath
            ],
            "RunAtLoad": true
        ]

        let directoryURL = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgentURL)
    }

    func remove() throws {
        guard isInstalled else {
            return
        }
        try FileManager.default.removeItem(at: launchAgentURL)
    }
}

private final class FocusSyncAgentController {
    private let label = "local.focus-wallpaper-sync"
    private let defaultInterval = 10

    var launchAgentURL: URL {
        let libraryURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return libraryURL
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: launchAgentURL.path)
    }

    var interval: Int {
        guard
            let data = try? Data(contentsOf: launchAgentURL),
            let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
            let dictionary = plist as? [String: Any],
            let interval = dictionary["StartInterval"] as? Int
        else {
            return defaultInterval
        }

        return interval
    }

    func install(interval: Int) throws {
        guard let helperScriptURL = Bundle.main.url(forResource: "focus-wallpaper-sync", withExtension: "sh") else {
            throw AppError("Could not find the bundled Focus Wallpaper sync helper.")
        }

        guard let appExecutablePath = Bundle.main.executablePath?.nilIfEmpty else {
            throw AppError("Could not determine the app executable path.")
        }

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/bin/sh",
                helperScriptURL.path,
                appExecutablePath
            ],
            "ProcessType": "Background",
            "RunAtLoad": true,
            "StartInterval": interval,
            "StandardOutPath": "/tmp/FocusWallpaperSync.out.log",
            "StandardErrorPath": "/tmp/FocusWallpaperSync.err.log"
        ]

        let directoryURL = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgentURL)

        try? runLaunchctl(["bootout", "gui/\(getuid())", launchAgentURL.path], allowFailure: true)
        try runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentURL.path])
        try runLaunchctl(["enable", "gui/\(getuid())/\(label)"])
        try runLaunchctl(["kickstart", "-k", "gui/\(getuid())/\(label)"])
    }

    func remove() throws {
        try? runLaunchctl(["bootout", "gui/\(getuid())", launchAgentURL.path], allowFailure: true)

        if isInstalled {
            try FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    private func runLaunchctl(_ arguments: [String], allowFailure: Bool = false) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 || allowFailure else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppError(message?.nilIfEmpty ?? "launchctl failed with exit code \(process.terminationStatus).")
        }
    }
}

private struct AppError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private enum FocusCommand: String {
    case on
    case off
    case status

    init?(arguments: [String]) {
        guard let rawValue = arguments.dropFirst().first else {
            return nil
        }

        switch rawValue {
        case "--focus-on", "focus-on", "on":
            self = .on
        case "--focus-off", "focus-off", "off":
            self = .off
        case "--status", "status":
            self = .status
        default:
            return nil
        }
    }
}

private final class FocusCommandRunner {
    private let preferences = Preferences()
    private let wallpapers = WallpaperController()

    func run(_ command: FocusCommand) -> Int32 {
        do {
            switch command {
            case .on:
                try focusOn()
                print("Focus wallpaper applied.")
            case .off:
                try focusOff()
                print("Normal wallpaper restored.")
            case .status:
                printStatus()
            }
            return 0
        } catch {
            fputs("FocusWallpaper: \(error.localizedDescription)\n", stderr)
            return 1
        }
    }

    private func focusOn() throws {
        guard let focusWallpaperURL = preferences.focusWallpaperURL else {
            throw AppError("Choose a Focus wallpaper in the app before using the shortcut trigger.")
        }

        let storedFocusWallpaperURL = try ImageStore.shared.importImage(at: focusWallpaperURL, named: "FocusWallpaper")
        preferences.focusWallpaperURL = storedFocusWallpaperURL

        if !preferences.focusWallpaperApplied {
            preferences.pendingRestoreSnapshot = wallpapers.snapshot()
        }

        try wallpapers.setWallpaperOnAllScreens(storedFocusWallpaperURL)
        preferences.focusWallpaperApplied = true
        preferences.shortcutFocusActive = true
        AppLog.shared.write("Applied Focus wallpaper from command-line trigger: \(storedFocusWallpaperURL.path)")
    }

    private func focusOff() throws {
        preferences.shortcutFocusActive = false
        try restoreNormalWallpaper()
        preferences.focusWallpaperApplied = false
        preferences.clearPendingRestore()
        AppLog.shared.write("Restored normal wallpaper from command-line trigger.")
    }

    private func restoreNormalWallpaper() throws {
        if let normalWallpaperURL = preferences.normalWallpaperURL {
            try wallpapers.setWallpaperOnAllScreens(normalWallpaperURL)
            return
        }

        if !preferences.normalSnapshot.isEmpty {
            try wallpapers.restore(preferences.normalSnapshot)
            return
        }

        try wallpapers.restore(preferences.pendingRestoreSnapshot)
    }

    private func printStatus() {
        let authorization = INFocusStatusCenter.default.authorizationStatus
        let publicFocus = authorization == .authorized
            ? String(describing: INFocusStatusCenter.default.focusStatus.isFocused)
            : "unavailable"

        print("Focus Status authorization: \(authorization)")
        print("Public Focus Status value: \(publicFocus)")
        print("Shortcut trigger active: \(preferences.shortcutFocusActive)")
        print("Focus wallpaper configured: \(preferences.focusWallpaperURL?.path ?? "no")")
        print("Focus wallpaper applied: \(preferences.focusWallpaperApplied)")
        print("Log: \(AppLog.shared.url.path)")
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let preferences = Preferences()
    private let wallpapers = WallpaperController()
    private let launchAgent = LaunchAgentController()
    private let focusSyncAgent = FocusSyncAgentController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private var timer: Timer?
    private var setupWindow: NSWindow?
    private var stateValueLabel: NSTextField?
    private var focusWallpaperValueLabel: NSTextField?
    private var normalPresetValueLabel: NSTextField?
    private var automaticSyncValueLabel: NSTextField?
    private var syncIntervalPopup: NSPopUpButton?
    private var syncToggleButton: NSButton?

    private let titleItem = NSMenuItem(title: "Focus Wallpaper", action: nil, keyEquivalent: "")
    private let focusStateItem = NSMenuItem(title: "App trigger state: Unknown", action: nil, keyEquivalent: "")
    private let focusWallpaperItem = NSMenuItem(title: "Focus wallpaper: Not set", action: nil, keyEquivalent: "")
    private let normalPresetItem = NSMenuItem(title: "Normal preset: Capture on activation", action: nil, keyEquivalent: "")
    private let automaticSyncItem = NSMenuItem(title: "Automatic sync: Off", action: nil, keyEquivalent: "")
    private let showSetupWindowItem = NSMenuItem(title: "Show Setup Window", action: #selector(showSetupWindow), keyEquivalent: "")
    private let chooseFocusWallpaperItem = NSMenuItem(title: "Choose Focus Wallpaper...", action: #selector(chooseFocusWallpaper), keyEquivalent: "")
    private let showWallpaperFolderItem = NSMenuItem(title: "Show Wallpaper Folder", action: #selector(showWallpaperFolder), keyEquivalent: "")
    private let useCurrentAsNormalItem = NSMenuItem(title: "Use Current Wallpaper as Normal Preset", action: #selector(useCurrentAsNormalPreset), keyEquivalent: "")
    private let chooseNormalWallpaperItem = NSMenuItem(title: "Choose Normal Wallpaper...", action: #selector(chooseNormalWallpaper), keyEquivalent: "")
    private let clearNormalPresetItem = NSMenuItem(title: "Clear Normal Preset", action: #selector(clearNormalPreset), keyEquivalent: "")
    private let applyFocusNowItem = NSMenuItem(title: "Apply Focus Wallpaper Now", action: #selector(applyFocusWallpaperNow), keyEquivalent: "")
    private let restoreNormalNowItem = NSMenuItem(title: "Restore Normal Now", action: #selector(restoreNormalNow), keyEquivalent: "")
    private let toggleAutomaticSyncItem = NSMenuItem(title: "Enable Automatic Sync", action: #selector(toggleAutomaticSync), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.shared.write("Application did finish launching.")
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureMenu()
        migrateConfiguredWallpapersIfNeeded()
        restoreAutomaticSyncIfNeeded()
        if preferences.focusWallpaperURL == nil {
            showSetupWindow()
        }
        pollFocusState()
        timer = Timer.scheduledTimer(
            timeInterval: 3.0,
            target: self,
            selector: #selector(timerFired),
            userInfo: nil,
            repeats: true
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()

        do {
            if focusSyncAgent.isInstalled {
                try focusSyncAgent.remove()
                AppLog.shared.write("Automatic sync LaunchAgent stopped because the app quit.")
            }
        } catch {
            AppLog.shared.write("Could not stop automatic sync LaunchAgent on quit: \(error.localizedDescription)")
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            handleTriggerURL(url)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === setupWindow {
            NSApp.setActivationPolicy(.accessory)
            AppLog.shared.write("Setup window closed; app returned to menu bar only.")
        }
    }

    @objc private func timerFired(_ timer: Timer) {
        pollFocusState()
    }

    private func migrateConfiguredWallpapersIfNeeded() {
        if let focusWallpaperURL = preferences.focusWallpaperURL {
            do {
                let storedURL = try ImageStore.shared.importImage(at: focusWallpaperURL, named: "FocusWallpaper")
                preferences.focusWallpaperURL = storedURL
            } catch {
                AppLog.shared.write("Could not migrate Focus wallpaper: \(error.localizedDescription)")
            }
        }

        if let normalWallpaperURL = preferences.normalWallpaperURL {
            do {
                let storedURL = try ImageStore.shared.importImage(at: normalWallpaperURL, named: "NormalWallpaper")
                preferences.normalWallpaperURL = storedURL
            } catch {
                AppLog.shared.write("Could not migrate normal wallpaper: \(error.localizedDescription)")
            }
        }

        updateMenu()
    }

    private func restoreAutomaticSyncIfNeeded() {
        let wasAlreadyInstalled = focusSyncAgent.isInstalled
        if wasAlreadyInstalled {
            preferences.automaticSyncInterval = focusSyncAgent.interval
        }

        guard preferences.automaticSyncEnabled || wasAlreadyInstalled else {
            return
        }

        do {
            preferences.automaticSyncEnabled = true
            try focusSyncAgent.install(interval: preferences.automaticSyncInterval)
            AppLog.shared.write("Automatic sync LaunchAgent started on app launch.")
            updateMenu()
            updateSetupWindowText()
        } catch {
            AppLog.shared.write("Could not start automatic sync LaunchAgent on app launch: \(error.localizedDescription)")
        }
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Focus Wallpaper")
            button.title = "Focus Wallpaper"
            button.imagePosition = .imageLeft
        }
    }

    private func configureMenu() {
        let menu = NSMenu()

        titleItem.isEnabled = false
        focusStateItem.isEnabled = false
        focusWallpaperItem.isEnabled = false
        normalPresetItem.isEnabled = false
        automaticSyncItem.isEnabled = false

        [
            showSetupWindowItem,
            chooseFocusWallpaperItem,
            showWallpaperFolderItem,
            useCurrentAsNormalItem,
            chooseNormalWallpaperItem,
            clearNormalPresetItem,
            applyFocusNowItem,
            restoreNormalNowItem,
            toggleAutomaticSyncItem,
            launchAtLoginItem
        ].forEach { $0.target = self }

        menu.addItem(titleItem)
        menu.addItem(focusStateItem)
        menu.addItem(focusWallpaperItem)
        menu.addItem(normalPresetItem)
        menu.addItem(automaticSyncItem)
        menu.addItem(.separator())
        menu.addItem(showSetupWindowItem)
        menu.addItem(chooseFocusWallpaperItem)
        menu.addItem(showWallpaperFolderItem)
        menu.addItem(useCurrentAsNormalItem)
        menu.addItem(chooseNormalWallpaperItem)
        menu.addItem(clearNormalPresetItem)
        menu.addItem(.separator())
        menu.addItem(toggleAutomaticSyncItem)
        menu.addItem(applyFocusNowItem)
        menu.addItem(restoreNormalNowItem)
        menu.addItem(.separator())
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
        updateMenu()
    }

    @objc private func showSetupWindow() {
        NSApp.setActivationPolicy(.regular)
        let window = setupWindow ?? makeSetupWindow()
        setupWindow = window
        updateSetupWindowText()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppLog.shared.write("Setup window shown.")
    }

    private func makeSetupWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Focus Wallpaper"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let contentView = NSView()
        window.contentView = contentView

        let title = label("Focus Wallpaper", font: .boldSystemFont(ofSize: 24), textColor: .labelColor)
        let summary = label(
            "Choose your wallpapers and optionally let a LaunchAgent run the Focus Wallpaper Sync shortcut on a schedule.",
            font: .systemFont(ofSize: 13),
            textColor: .secondaryLabelColor
        )

        let stateValue = valueLabel()
        let focusWallpaperValue = valueLabel()
        let normalPresetValue = valueLabel()
        let automaticSyncValue = valueLabel()
        stateValueLabel = stateValue
        focusWallpaperValueLabel = focusWallpaperValue
        normalPresetValueLabel = normalPresetValue
        automaticSyncValueLabel = automaticSyncValue

        let chooseFocusButton = button("Choose Focus Wallpaper...", action: #selector(chooseFocusWallpaper))
        let showFolderButton = button("Show Wallpaper Folder", action: #selector(showWallpaperFolder))
        let applyButton = button("Apply Focus Now", action: #selector(applyFocusWallpaperNow))
        let restoreButton = button("Restore Normal Now", action: #selector(restoreNormalNow))
        let useCurrentButton = button("Use Current as Normal", action: #selector(useCurrentAsNormalPreset))
        let chooseNormalButton = button("Choose Normal Wallpaper...", action: #selector(chooseNormalWallpaper))

        let intervalPopup = NSPopUpButton()
        intervalPopup.translatesAutoresizingMaskIntoConstraints = false
        intervalPopup.addItems(withTitles: ["Every 10 seconds", "Every minute", "Every 5 minutes", "Every 15 minutes"])
        intervalPopup.item(at: 0)?.tag = 10
        intervalPopup.item(at: 1)?.tag = 60
        intervalPopup.item(at: 2)?.tag = 300
        intervalPopup.item(at: 3)?.tag = 900
        intervalPopup.target = self
        intervalPopup.action = #selector(syncIntervalChanged)
        syncIntervalPopup = intervalPopup

        let toggleSyncButton = button("Enable Automatic Sync", action: #selector(toggleAutomaticSync))
        syncToggleButton = toggleSyncButton

        let manualButtons = horizontalStack([applyButton, restoreButton])
        let focusButtons = horizontalStack([chooseFocusButton, showFolderButton])
        let normalButtons = horizontalStack([useCurrentButton, chooseNormalButton])
        let syncButtons = horizontalStack([intervalPopup, toggleSyncButton])

        let stack = NSStackView(views: [
            title,
            summary,
            separator(),
            infoRow(title: "State", value: stateValue),
            infoRow(title: "Focus wallpaper", value: focusWallpaperValue),
            focusButtons,
            infoRow(title: "Normal wallpaper", value: normalPresetValue),
            normalButtons,
            infoRow(title: "Automatic sync", value: automaticSyncValue),
            syncButtons,
            separator(),
            manualButtons
        ])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24),

            summary.widthAnchor.constraint(equalTo: stack.widthAnchor),
            manualButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            focusButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            normalButtons.widthAnchor.constraint(equalTo: stack.widthAnchor),
            syncButtons.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])

        return window
    }

    private func label(_ text: String, font: NSFont, textColor: NSColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = font
        label.textColor = textColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    private func valueLabel() -> NSTextField {
        let label = label("", font: .systemFont(ofSize: 13), textColor: .labelColor)
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        return label
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    private func infoRow(title: String, value: NSTextField) -> NSStackView {
        let titleLabel = label(title, font: .systemFont(ofSize: 13, weight: .medium), textColor: .secondaryLabelColor)
        titleLabel.maximumNumberOfLines = 1
        titleLabel.widthAnchor.constraint(equalToConstant: 128).isActive = true

        let row = NSStackView(views: [titleLabel, value])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func horizontalStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        box.translatesAutoresizingMaskIntoConstraints = false
        return box
    }

    private func updateSetupWindowText() {
        stateValueLabel?.stringValue = appTriggerStateText()
        focusWallpaperValueLabel?.stringValue = description(for: preferences.focusWallpaperURL)
        normalPresetValueLabel?.stringValue = normalPresetText()
        automaticSyncValueLabel?.stringValue = automaticSyncText()
        syncToggleButton?.title = focusSyncAgent.isInstalled ? "Disable Automatic Sync" : "Enable Automatic Sync"
        selectCurrentSyncInterval()
    }

    private func pollFocusState() {
        let authorization = INFocusStatusCenter.default.authorizationStatus
        let publicFocused = authorization == .authorized
            ? INFocusStatusCenter.default.focusStatus.isFocused
            : nil
        let focused = preferences.shortcutFocusActive ? true : publicFocused

        if let focused {
            handleFocusState(focused)
        } else if preferences.focusWallpaperApplied, authorization == .authorized {
            handleFocusState(false)
        }

        updateMenu()
        updateSetupWindowText()
    }

    private func handleFocusState(_ focused: Bool) {
        if focused {
            applyFocusWallpaperForFocusActivation()
        } else {
            restoreAfterFocusIfNeeded()
        }
    }

    private func applyFocusWallpaperForFocusActivation() {
        guard !preferences.focusWallpaperApplied else {
            return
        }

        guard let focusWallpaperURL = preferences.focusWallpaperURL else {
            AppLog.shared.write("Focus is active, but no Focus wallpaper is configured.")
            return
        }

        do {
            preferences.pendingRestoreSnapshot = wallpapers.snapshot()
            try wallpapers.setWallpaperOnAllScreens(focusWallpaperURL)
            preferences.focusWallpaperApplied = true
            AppLog.shared.write("Applied Focus wallpaper: \(focusWallpaperURL.path)")
        } catch {
            AppLog.shared.write("Failed to apply Focus wallpaper: \(error.localizedDescription)")
            showError("Could not apply the Focus wallpaper.", error: error)
        }
    }

    private func restoreAfterFocusIfNeeded() {
        guard preferences.focusWallpaperApplied else {
            return
        }

        do {
            try restoreNormalWallpaper()
            preferences.focusWallpaperApplied = false
            preferences.clearPendingRestore()
            AppLog.shared.write("Restored normal wallpaper.")
        } catch {
            AppLog.shared.write("Failed to restore normal wallpaper: \(error.localizedDescription)")
            showError("Could not restore the normal wallpaper.", error: error)
        }
    }

    private func restoreNormalWallpaper() throws {
        if let normalWallpaperURL = preferences.normalWallpaperURL {
            try wallpapers.setWallpaperOnAllScreens(normalWallpaperURL)
            return
        }

        if !preferences.normalSnapshot.isEmpty {
            try wallpapers.restore(preferences.normalSnapshot)
            return
        }

        try wallpapers.restore(preferences.pendingRestoreSnapshot)
    }

    private func handleTriggerURL(_ url: URL) {
        guard url.scheme == "focuswallpaper" else {
            return
        }

        let action = triggerAction(from: url)

        do {
            switch action {
            case "on":
                try applyFocusWallpaperFromShortcutTrigger()
            case "off":
                try restoreNormalFromShortcutTrigger()
            default:
                showMessage(
                    "Unknown Focus Wallpaper URL.",
                    informativeText: "Use focuswallpaper://on or focuswallpaper://off."
                )
            }
        } catch {
            showError("Could not run the Focus Wallpaper URL trigger.", error: error)
        }
    }

    private func triggerAction(from url: URL) -> String {
        if let host = url.host, !host.isEmpty {
            return host.lowercased()
        }

        return url.pathComponents
            .first(where: { $0 != "/" })?
            .lowercased() ?? ""
    }

    private func applyFocusWallpaperFromShortcutTrigger() throws {
        guard let focusWallpaperURL = preferences.focusWallpaperURL else {
            throw AppError("Choose a Focus wallpaper first.")
        }

        if !preferences.focusWallpaperApplied {
            preferences.pendingRestoreSnapshot = wallpapers.snapshot()
        }

        try wallpapers.setWallpaperOnAllScreens(focusWallpaperURL)
        preferences.focusWallpaperApplied = true
        preferences.shortcutFocusActive = true
        AppLog.shared.write("Applied Focus wallpaper from URL trigger: \(focusWallpaperURL.path)")
        updateMenu()
        updateSetupWindowText()
    }

    private func restoreNormalFromShortcutTrigger() throws {
        preferences.shortcutFocusActive = false
        try restoreNormalWallpaper()
        preferences.focusWallpaperApplied = false
        preferences.clearPendingRestore()
        AppLog.shared.write("Restored normal wallpaper from URL trigger.")
        updateMenu()
        updateSetupWindowText()
    }

    @objc private func chooseFocusWallpaper() {
        guard let url = pickImageURL() else {
            return
        }

        do {
            let storedURL = try ImageStore.shared.importImage(at: url, named: "FocusWallpaper")
            preferences.focusWallpaperURL = storedURL
            AppLog.shared.write("Configured Focus wallpaper: \(storedURL.path)")
            updateMenu()
            updateSetupWindowText()
            pollFocusState()
        } catch {
            showError("Could not save the Focus wallpaper.", error: error)
        }
    }

    @objc private func showWallpaperFolder() {
        do {
            try ImageStore.shared.ensureDirectoryExists()
            NSWorkspace.shared.open(ImageStore.shared.directoryURL)
        } catch {
            showError("Could not open the wallpaper folder.", error: error)
        }
    }

    @objc private func chooseNormalWallpaper() {
        guard let url = pickImageURL() else {
            return
        }

        do {
            let storedURL = try ImageStore.shared.importImage(at: url, named: "NormalWallpaper")
            preferences.normalWallpaperURL = storedURL
            preferences.normalSnapshot = [:]
            AppLog.shared.write("Configured normal wallpaper: \(storedURL.path)")
            updateMenu()
            updateSetupWindowText()
        } catch {
            showError("Could not save the normal wallpaper.", error: error)
        }
    }

    @objc private func useCurrentAsNormalPreset() {
        preferences.normalWallpaperURL = nil
        preferences.normalSnapshot = wallpapers.snapshot()
        AppLog.shared.write("Captured current wallpaper as normal preset.")
        updateMenu()
        updateSetupWindowText()
    }

    @objc private func clearNormalPreset() {
        preferences.clearNormalPreset()
        AppLog.shared.write("Cleared normal preset.")
        updateMenu()
        updateSetupWindowText()
    }

    @objc private func applyFocusWallpaperNow() {
        guard let focusWallpaperURL = preferences.focusWallpaperURL else {
            showMessage("Choose a Focus wallpaper first.", informativeText: "")
            return
        }

        do {
            if !preferences.focusWallpaperApplied {
                preferences.pendingRestoreSnapshot = wallpapers.snapshot()
            }
            try wallpapers.setWallpaperOnAllScreens(focusWallpaperURL)
            preferences.focusWallpaperApplied = true
            preferences.shortcutFocusActive = true
            AppLog.shared.write("Applied Focus wallpaper manually: \(focusWallpaperURL.path)")
            updateMenu()
            updateSetupWindowText()
        } catch {
            AppLog.shared.write("Failed to manually apply Focus wallpaper: \(error.localizedDescription)")
            showError("Could not apply the Focus wallpaper.", error: error)
        }
    }

    @objc private func restoreNormalNow() {
        do {
            try restoreNormalWallpaper()
            preferences.focusWallpaperApplied = false
            preferences.shortcutFocusActive = false
            preferences.clearPendingRestore()
            AppLog.shared.write("Restored normal wallpaper manually.")
            updateMenu()
            updateSetupWindowText()
        } catch {
            AppLog.shared.write("Failed to manually restore normal wallpaper: \(error.localizedDescription)")
            showError("Could not restore the normal wallpaper.", error: error)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAgent.isInstalled {
                try launchAgent.remove()
                showMessage("Start at Login removed.", informativeText: "The app will no longer be launched automatically at login.")
            } else {
                try launchAgent.install()
                showMessage("Start at Login installed.", informativeText: "The app will launch the next time you log in.")
            }
            updateMenu()
        } catch {
            showError("Could not update Start at Login.", error: error)
        }
    }

    @objc private func toggleAutomaticSync() {
        do {
            if focusSyncAgent.isInstalled {
                try focusSyncAgent.remove()
                preferences.automaticSyncEnabled = false
                AppLog.shared.write("Automatic sync disabled.")
            } else {
                let interval = selectedSyncInterval()
                preferences.automaticSyncInterval = interval
                try focusSyncAgent.install(interval: interval)
                preferences.automaticSyncEnabled = true
                AppLog.shared.write("Automatic sync enabled every \(interval) seconds.")
            }
            updateMenu()
            updateSetupWindowText()
        } catch {
            showError("Could not update automatic sync.", error: error)
        }
    }

    @objc private func syncIntervalChanged() {
        preferences.automaticSyncInterval = selectedSyncInterval()

        guard focusSyncAgent.isInstalled else {
            updateMenu()
            updateSetupWindowText()
            return
        }

        do {
            let interval = selectedSyncInterval()
            preferences.automaticSyncInterval = interval
            try focusSyncAgent.install(interval: interval)
            preferences.automaticSyncEnabled = true
            AppLog.shared.write("Automatic sync interval changed to \(interval) seconds.")
            updateMenu()
            updateSetupWindowText()
        } catch {
            showError("Could not update the automatic sync interval.", error: error)
        }
    }

    private func pickImageURL() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]

        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }

    private func updateMenu() {
        focusStateItem.title = "App trigger state: \(appTriggerStateText())"
        focusWallpaperItem.title = "Focus wallpaper: \(description(for: preferences.focusWallpaperURL))"
        normalPresetItem.title = "Normal preset: \(normalPresetText())"
        automaticSyncItem.title = "Automatic sync: \(automaticSyncText())"
        updateStatusButton()
        applyFocusNowItem.isEnabled = preferences.focusWallpaperURL != nil
        restoreNormalNowItem.isEnabled = preferences.focusWallpaperApplied
            || preferences.normalWallpaperURL != nil
            || !preferences.normalSnapshot.isEmpty
            || !preferences.pendingRestoreSnapshot.isEmpty
        clearNormalPresetItem.isEnabled = preferences.normalWallpaperURL != nil || !preferences.normalSnapshot.isEmpty
        toggleAutomaticSyncItem.title = focusSyncAgent.isInstalled ? "Disable Automatic Sync" : "Enable Automatic Sync"
        toggleAutomaticSyncItem.state = focusSyncAgent.isInstalled ? .on : .off
        launchAtLoginItem.state = launchAgent.isInstalled ? .on : .off
    }

    private func updateStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        if preferences.focusWallpaperURL == nil {
            button.title = "Focus Wallpaper"
            button.imagePosition = .imageLeft
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    private func appTriggerStateText() -> String {
        if preferences.shortcutFocusActive {
            return "On (Shortcut trigger)"
        }

        if preferences.focusWallpaperApplied {
            return "On (Manual/app state)"
        }

        if INFocusStatusCenter.default.authorizationStatus == .authorized,
           INFocusStatusCenter.default.focusStatus.isFocused == true {
            return "On (Public API)"
        }

        return "Off (no active app trigger)"
    }

    private func normalPresetText() -> String {
        if let normalWallpaperURL = preferences.normalWallpaperURL {
            return description(for: normalWallpaperURL)
        }

        if !preferences.normalSnapshot.isEmpty {
            let count = preferences.normalSnapshot.count
            return count == 1 ? "Current wallpaper snapshot" : "Current wallpaper snapshot (\(count) screens)"
        }

        return "Capture on activation"
    }

    private func automaticSyncText() -> String {
        guard focusSyncAgent.isInstalled else {
            return "Off"
        }

        return "On, \(intervalText(focusSyncAgent.interval))"
    }

    private func selectedSyncInterval() -> Int {
        syncIntervalPopup?.selectedItem?.tag
            ?? (focusSyncAgent.isInstalled ? focusSyncAgent.interval : preferences.automaticSyncInterval)
    }

    private func selectCurrentSyncInterval() {
        guard let syncIntervalPopup else {
            return
        }

        let interval = focusSyncAgent.isInstalled ? focusSyncAgent.interval : preferences.automaticSyncInterval
        if let item = syncIntervalPopup.itemArray.first(where: { $0.tag == interval }) {
            syncIntervalPopup.select(item)
        } else {
            syncIntervalPopup.selectItem(at: 0)
        }
    }

    private func intervalText(_ interval: Int) -> String {
        switch interval {
        case 10:
            return "every 10 seconds"
        case 60:
            return "every minute"
        case 300:
            return "every 5 minutes"
        case 900:
            return "every 15 minutes"
        default:
            return "every \(interval) seconds"
        }
    }

    private func description(for url: URL?) -> String {
        guard let url else {
            return "Not set"
        }
        return url.lastPathComponent.nilIfEmpty ?? url.path.nilIfEmpty ?? url.absoluteString
    }

    private func showError(_ message: String, error: Error) {
        showMessage(message, informativeText: error.localizedDescription)
    }

    private func showMessage(_ message: String, informativeText: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")

        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

if let command = FocusCommand(arguments: CommandLine.arguments) {
    exit(FocusCommandRunner().run(command))
}

private let app = NSApplication.shared
private let delegate = AppDelegate()
app.delegate = delegate
app.run()
