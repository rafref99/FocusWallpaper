import AppKit
import Darwin
import Foundation
import Intents
import ServiceManagement
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

private enum AutomaticSyncInterval {
    static let defaultValue = 10
    static let supportedValues = [1, 5, 10, 60]

    static func isSupported(_ value: Int) -> Bool {
        supportedValues.contains(value)
    }
}

private typealias WallpaperSnapshot = [String: String]

private final class AppLog: @unchecked Sendable {
    static let shared = AppLog()

    let url: URL
    private let maximumFileSize = 1_048_576
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
            try rotateIfNeeded(adding: data.count)

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

    private func rotateIfNeeded(adding byteCount: Int) throws {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let currentSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0

        guard currentSize + byteCount > maximumFileSize else {
            return
        }

        let archiveURL = url.appendingPathExtension("previous")
        try? FileManager.default.removeItem(at: archiveURL)
        try FileManager.default.moveItem(at: url, to: archiveURL)
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
            return AutomaticSyncInterval.isSupported(interval)
                ? interval
                : AutomaticSyncInterval.defaultValue
        }
        set { defaults.set(newValue, forKey: DefaultsKey.automaticSyncInterval) }
    }

    @discardableResult
    func synchronize() -> Bool {
        defaults.synchronize()
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

private enum StartAtLoginState {
    case enabled
    case disabled
    case requiresApproval
    case unavailable

    var isRegistered: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .disabled, .unavailable:
            return false
        }
    }

    var displayText: String {
        switch self {
        case .enabled:
            return "On"
        case .disabled:
            return "Off"
        case .requiresApproval:
            return "Needs approval in System Settings"
        case .unavailable:
            return "Unavailable"
        }
    }
}

private final class StartAtLoginController {
    private let fallbackLaunchAgent = LaunchAgentController()

    var state: StartAtLoginState {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return .enabled
            case .requiresApproval:
                return .requiresApproval
            case .notRegistered:
                return .disabled
            case .notFound:
                return .unavailable
            @unknown default:
                return .unavailable
            }
        }

        return fallbackLaunchAgent.isInstalled ? .enabled : .disabled
    }

    var backendName: String {
        if #available(macOS 13.0, *) {
            return "SMAppService"
        }

        return "LaunchAgent"
    }

    func install() throws {
        if #available(macOS 13.0, *) {
            try? fallbackLaunchAgent.remove()
            try SMAppService.mainApp.register()
            return
        }

        try fallbackLaunchAgent.install()
    }

    func remove() throws {
        if #available(macOS 13.0, *) {
            try SMAppService.mainApp.unregister()
            try? fallbackLaunchAgent.remove()
            return
        }

        try fallbackLaunchAgent.remove()
    }
}

private struct FocusSyncStatus {
    let isInstalled: Bool
    let isLoaded: Bool?
    let interval: Int
    let lastSyncDate: Date?
    let lastResult: String?
    let lastErrorDate: Date?
    let lastError: String?
}

private struct AutomaticSyncRestoreResult: Sendable {
    enum Outcome: Sendable {
        case restored
        case failed(String)
    }

    let outcome: Outcome
    let interval: Int
}

private enum AutomaticSyncChange: Sendable {
    case install(interval: Int)
    case remove
}

private struct AutomaticSyncChangeResult: Sendable {
    enum Outcome: Sendable {
        case succeeded
        case failed(String)
    }

    let outcome: Outcome
    let isEnabled: Bool
    let interval: Int?
}

private enum ShortcutTestResult: Sendable {
    case succeeded(String)
    case failed(String)
}

private final class FocusSyncAgentController {
    private let label = "local.focus-wallpaper-sync"
    private let shortcutName = "Focus Wallpaper Sync"
    private let defaultInterval = AutomaticSyncInterval.defaultValue
    private let standardOutURL = URL(fileURLWithPath: "/tmp/FocusWallpaperSync.out.log")
    private let standardErrorURL = URL(fileURLWithPath: "/tmp/FocusWallpaperSync.err.log")

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

    func status(checkLoadedState: Bool = false) -> FocusSyncStatus {
        let installed = isInstalled
        let loaded = installed && checkLoadedState ? launchAgentIsLoaded : nil

        return FocusSyncStatus(
            isInstalled: installed,
            isLoaded: loaded,
            interval: interval,
            lastSyncDate: modificationDate(for: standardOutURL),
            lastResult: lastNonEmptyLine(in: standardOutURL),
            lastErrorDate: modificationDate(for: standardErrorURL),
            lastError: lastNonEmptyLine(in: standardErrorURL)
        )
    }

    func testShortcut() throws -> String {
        let output = try runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"),
            arguments: ["run", shortcutName]
        )
        return try normalizedShortcutAction(from: output)
    }

    func install(interval: Int) throws {
        guard AutomaticSyncInterval.isSupported(interval) else {
            throw AppError("Automatic Sync interval must be 1, 5, 10, or 60 seconds.")
        }

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
            "ThrottleInterval": throttleInterval(for: interval),
            "StandardOutPath": standardOutURL.path,
            "StandardErrorPath": standardErrorURL.path
        ]

        let directoryURL = launchAgentURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: launchAgentURL)

        unload()
        try runLaunchctl(["bootstrap", "gui/\(getuid())", launchAgentURL.path])
        try runLaunchctl(["enable", "gui/\(getuid())/\(label)"])
        try runLaunchctl(["kickstart", "-k", "gui/\(getuid())/\(label)"])
    }

    func remove() throws {
        unload()

        if isInstalled {
            try FileManager.default.removeItem(at: launchAgentURL)
        }
    }

    private func unload() {
        try? runLaunchctl(["bootout", "gui/\(getuid())/\(label)"], allowFailure: true)
        try? runLaunchctl(["bootout", "gui/\(getuid())", launchAgentURL.path], allowFailure: true)
    }

    private var launchAgentIsLoaded: Bool {
        do {
            try runLaunchctl(["print", "gui/\(getuid())/\(label)"])
            return true
        } catch {
            return false
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

    private func throttleInterval(for interval: Int) -> Int {
        max(1, min(interval, defaultInterval))
    }

    private func runProcess(executableURL: URL, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let output = String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        let errorOutput = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""

        guard process.terminationStatus == 0 else {
            let message = errorOutput.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? output.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
                ?? "Process failed with exit code \(process.terminationStatus)."
            throw AppError(message)
        }

        return output
    }

    private func normalizedShortcutAction(from output: String) throws -> String {
        let tokens = output
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
        guard let value = tokens.last?.lowercased() else {
            throw AppError("\(shortcutName) returned no output. It must return 'on' or 'off'.")
        }

        switch value {
        case "on", "focused", "focus", "true", "yes", "1":
            return "on"
        case "off", "none", "false", "no", "0":
            return "off"
        default:
            let preview = output.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "<empty output>"
            throw AppError("\(shortcutName) must return 'on' or 'off'; got: \(preview)")
        }
    }

    private func lastNonEmptyLine(in url: URL) -> String? {
        let maximumTailSize: UInt64 = 64 * 1_024

        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return nil
        }

        defer { try? handle.close() }

        let fileSize = (try? handle.seekToEnd()) ?? 0
        let offset = fileSize > maximumTailSize ? fileSize - maximumTailSize : 0
        try? handle.seek(toOffset: offset)

        guard
            let data = try? handle.readToEnd(),
            let contents = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        for line in contents.components(separatedBy: .newlines).reversed() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        return nil
    }

    private func modificationDate(for url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }
}

private struct AppMetadata {
    static let developerName = "Rafael Refaiya"

    let name: String
    let developer: String
    let version: String
    let buildDate: Date?
    let bundleIdentifier: String
    let urlScheme: String
    let appPath: String
    let logPath: String

    static var current: AppMetadata {
        let bundle = Bundle.main
        let displayName = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)?.nilIfEmpty
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)?.nilIfEmpty
            ?? "Focus Wallpaper"
        let shortVersion = (bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)?.nilIfEmpty
            ?? "Unknown"
        let buildNumber = (bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String)?.nilIfEmpty
        let version = buildNumber.map { $0 == shortVersion ? shortVersion : "\(shortVersion) (\($0))" }
            ?? shortVersion

        return AppMetadata(
            name: displayName,
            developer: Self.developerName,
            version: version,
            buildDate: bundle.executableURL.flatMap(Self.modificationDate),
            bundleIdentifier: bundle.bundleIdentifier ?? "Unknown",
            urlScheme: "focuswallpaper",
            appPath: bundle.bundlePath,
            logPath: AppLog.shared.url.path
        )
    }

    private static func modificationDate(for url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
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
                let changed = try focusOn()
                print(changed ? "Focus wallpaper applied." : "Focus wallpaper already active.")
            case .off:
                let changed = try focusOff()
                print(changed ? "Normal wallpaper restored." : "Focus wallpaper already inactive.")
            case .status:
                printStatus()
            }
            preferences.synchronize()
            return 0
        } catch {
            fputs("FocusWallpaper: \(error.localizedDescription)\n", stderr)
            preferences.synchronize()
            return 1
        }
    }

    private func focusOn() throws -> Bool {
        guard let focusWallpaperURL = preferences.focusWallpaperURL else {
            throw AppError("Choose a Focus wallpaper in the app before using the shortcut trigger.")
        }

        if preferences.focusWallpaperApplied {
            preferences.shortcutFocusActive = true
            return false
        }

        let storedFocusWallpaperURL = try ImageStore.shared.importImage(at: focusWallpaperURL, named: "FocusWallpaper")
        preferences.focusWallpaperURL = storedFocusWallpaperURL

        preferences.pendingRestoreSnapshot = wallpapers.snapshot()

        try wallpapers.setWallpaperOnAllScreens(storedFocusWallpaperURL)
        preferences.focusWallpaperApplied = true
        preferences.shortcutFocusActive = true
        AppLog.shared.write("Applied Focus wallpaper from command-line trigger: \(storedFocusWallpaperURL.path)")
        return true
    }

    private func focusOff() throws -> Bool {
        preferences.shortcutFocusActive = false

        guard preferences.focusWallpaperApplied else {
            return false
        }

        try restoreNormalWallpaper()
        preferences.focusWallpaperApplied = false
        preferences.clearPendingRestore()
        AppLog.shared.write("Restored normal wallpaper from command-line trigger.")
        return true
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

private enum SetupSection {
    case home
    case settings
    case about
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let preferences = Preferences()
    private let wallpapers = WallpaperController()
    private let startAtLogin = StartAtLoginController()
    private let focusSyncAgent = FocusSyncAgentController()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

    private var timer: Timer?
    private var setupWindow: NSWindow?
    private var setupWindowController: NSWindowController?
    private var selectedSetupSection: SetupSection = .home
    private var setupHomeButton: NSButton?
    private var setupSettingsButton: NSButton?
    private var setupAboutButton: NSButton?
    private var setupHomeView: NSView?
    private var setupSettingsView: NSView?
    private var setupAboutView: NSView?
    private var firstRunSetupView: NSStackView?
    private var firstRunSeparatorView: NSBox?
    private var stateValueLabel: NSTextField?
    private var focusWallpaperValueLabel: NSTextField?
    private var normalPresetValueLabel: NSTextField?
    private var automaticSyncValueLabel: NSTextField?
    private var syncLastRunValueLabel: NSTextField?
    private var syncLastErrorValueLabel: NSTextField?
    private var launchAtLoginValueLabel: NSTextField?
    private var aboutVersionValueLabel: NSTextField?
    private var aboutDeveloperValueLabel: NSTextField?
    private var aboutBuildDateValueLabel: NSTextField?
    private var aboutBundleIdentifierValueLabel: NSTextField?
    private var aboutURLSchemeValueLabel: NSTextField?
    private var aboutAppPathValueLabel: NSTextField?
    private var aboutLogPathValueLabel: NSTextField?
    private var syncIntervalPopup: NSPopUpButton?
    private var syncToggleButton: NSButton?
    private var launchAtLoginButton: NSButton?
    private var clearNormalPresetButton: NSButton?
    private var wakeRefreshTimer: Timer?
    private var automaticSyncInitializationInProgress = false
    private var shortcutTestInProgress = false

    private let titleItem = NSMenuItem(title: "Focus Wallpaper", action: nil, keyEquivalent: "")
    private let focusStateItem = NSMenuItem(title: "App trigger state: Unknown", action: nil, keyEquivalent: "")
    private let showSetupWindowItem = NSMenuItem(title: "Show Control Window", action: #selector(showSetupWindow), keyEquivalent: "")
    private let applyFocusNowItem = NSMenuItem(title: "Apply Focus Wallpaper Now", action: #selector(applyFocusWallpaperNow), keyEquivalent: "")
    private let restoreNormalNowItem = NSMenuItem(title: "Restore Normal Now", action: #selector(restoreNormalNow), keyEquivalent: "")
    private let launchAtLoginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private let manualFocusSeparatorItem = NSMenuItem.separator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.shared.write("Application did finish launching.")
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureMenu()
        registerWorkspaceNotifications()
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
        wakeRefreshTimer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)

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
            clearSetupWindowReferences()
            NSApp.setActivationPolicy(.accessory)
            AppLog.shared.write("Setup window closed; app returned to menu bar only.")
        }
    }

    @objc private func timerFired(_ timer: Timer) {
        pollFocusState()
    }

    @objc private func systemWillSleep(_ notification: Notification) {
        wakeRefreshTimer?.invalidate()
        AppLog.shared.write("System will sleep; Focus state refresh paused until wake.")
    }

    @objc private func systemDidWake(_ notification: Notification) {
        AppLog.shared.write("System woke; scheduling Focus state refresh.")
        scheduleWakeRefresh()
    }

    @objc private func wakeRefreshTimerFired(_ timer: Timer) {
        wakeRefreshTimer = nil
        refreshFocusStateAfterWake()
    }

    private func registerWorkspaceNotifications() {
        let notificationCenter = NSWorkspace.shared.notificationCenter
        notificationCenter.addObserver(
            self,
            selector: #selector(systemWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(systemDidWake),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
    }

    private func scheduleWakeRefresh() {
        wakeRefreshTimer?.invalidate()
        wakeRefreshTimer = Timer.scheduledTimer(
            timeInterval: 1.0,
            target: self,
            selector: #selector(wakeRefreshTimerFired),
            userInfo: nil,
            repeats: false
        )
    }

    private func refreshFocusStateAfterWake() {
        preferences.synchronize()
        refreshAutomaticSyncAfterWake()
        pollFocusState()
    }

    private func refreshAutomaticSyncAfterWake() {
        let wasAlreadyInstalled = focusSyncAgent.isInstalled

        guard preferences.automaticSyncEnabled || wasAlreadyInstalled else {
            return
        }

        if wasAlreadyInstalled {
            preferences.automaticSyncInterval = focusSyncAgent.interval
        }

        performAutomaticSyncChange(
            .install(interval: preferences.automaticSyncInterval),
            successLog: "Automatic sync LaunchAgent refreshed after wake.",
            failureTitle: "Could not refresh Automatic Sync after wake.",
            showFailure: false
        )
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
        let automaticSyncEnabled = preferences.automaticSyncEnabled
        let wasAlreadyInstalled = focusSyncAgent.isInstalled
        let preferredInterval = wasAlreadyInstalled ? focusSyncAgent.interval : preferences.automaticSyncInterval

        guard automaticSyncEnabled || wasAlreadyInstalled else {
            return
        }

        automaticSyncInitializationInProgress = true
        let restoreTask = Task.detached(priority: .utility) { () -> AutomaticSyncRestoreResult in
            let focusSyncAgent = FocusSyncAgentController()

            do {
                try focusSyncAgent.install(interval: preferredInterval)
                return AutomaticSyncRestoreResult(outcome: .restored, interval: preferredInterval)
            } catch {
                return AutomaticSyncRestoreResult(outcome: .failed(error.localizedDescription), interval: preferredInterval)
            }
        }

        Task { @MainActor [weak self] in
            let result = await restoreTask.value
            self?.finishAutomaticSyncRestore(result)
        }
    }

    private func finishAutomaticSyncRestore(_ result: AutomaticSyncRestoreResult) {
        automaticSyncInitializationInProgress = false

        switch result.outcome {
        case .restored:
            preferences.automaticSyncEnabled = true
            preferences.automaticSyncInterval = result.interval
            preferences.synchronize()
            AppLog.shared.write("Automatic sync LaunchAgent started on app launch.")
        case .failed(let message):
            AppLog.shared.write("Could not start automatic sync LaunchAgent on app launch: \(message)")
        }

        updateMenu()
        updateSetupWindowText()
    }

    private func performAutomaticSyncChange(
        _ change: AutomaticSyncChange,
        successLog: String,
        failureTitle: String,
        successMessage: (title: String, details: String)? = nil,
        showFailure: Bool = true
    ) {
        guard !automaticSyncInitializationInProgress else {
            return
        }

        automaticSyncInitializationInProgress = true
        updateMenu()
        updateSetupWindowText()

        let changeTask = Task.detached(priority: .utility) { () -> AutomaticSyncChangeResult in
            let controller = FocusSyncAgentController()

            do {
                switch change {
                case .install(let interval):
                    try controller.install(interval: interval)
                    return AutomaticSyncChangeResult(
                        outcome: .succeeded,
                        isEnabled: true,
                        interval: interval
                    )
                case .remove:
                    try controller.remove()
                    return AutomaticSyncChangeResult(
                        outcome: .succeeded,
                        isEnabled: false,
                        interval: nil
                    )
                }
            } catch {
                return AutomaticSyncChangeResult(
                    outcome: .failed(error.localizedDescription),
                    isEnabled: controller.isInstalled,
                    interval: controller.isInstalled ? controller.interval : nil
                )
            }
        }

        Task { @MainActor [weak self] in
            let result = await changeTask.value
            self?.finishAutomaticSyncChange(
                result,
                successLog: successLog,
                failureTitle: failureTitle,
                successMessage: successMessage,
                showFailure: showFailure
            )
        }
    }

    private func finishAutomaticSyncChange(
        _ result: AutomaticSyncChangeResult,
        successLog: String,
        failureTitle: String,
        successMessage: (title: String, details: String)?,
        showFailure: Bool
    ) {
        automaticSyncInitializationInProgress = false

        switch result.outcome {
        case .succeeded:
            preferences.automaticSyncEnabled = result.isEnabled
            if let interval = result.interval {
                preferences.automaticSyncInterval = interval
            }
            preferences.synchronize()
            AppLog.shared.write(successLog)

            if let successMessage {
                showMessage(successMessage.title, informativeText: successMessage.details)
            }
        case .failed(let message):
            AppLog.shared.write("\(failureTitle) \(message)")
            if showFailure {
                showMessage(failureTitle, informativeText: message)
            }
        }

        updateMenu()
        updateSetupWindowText()
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

        [
            showSetupWindowItem,
            applyFocusNowItem,
            restoreNormalNowItem,
            launchAtLoginItem
        ].forEach { $0.target = self }

        menu.addItem(titleItem)
        menu.addItem(focusStateItem)
        menu.addItem(.separator())
        menu.addItem(showSetupWindowItem)
        menu.addItem(launchAtLoginItem)
        menu.addItem(manualFocusSeparatorItem)
        menu.addItem(applyFocusNowItem)
        menu.addItem(restoreNormalNowItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        statusItem.menu = menu
        updateMenu()
    }

    @objc private func showSetupWindow() {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async { [weak self] in
            self?.presentSetupWindow()
        }
    }

    private func presentSetupWindow() {
        let window = setupWindow ?? makeSetupWindow()
        setupWindow = window
        let controller = setupWindowController ?? NSWindowController(window: window)
        setupWindowController = controller
        updateSetupWindowText()
        if !window.isVisible {
            window.center()
        }
        window.level = .normal
        window.deminiaturize(nil)
        controller.showWindow(self)
        window.makeKeyAndOrderFront(self)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        AppLog.shared.write("Setup window shown.")
    }

    private func clearSetupWindowReferences() {
        setupWindow = nil
        setupWindowController = nil
        setupHomeButton = nil
        setupSettingsButton = nil
        setupAboutButton = nil
        setupHomeView = nil
        setupSettingsView = nil
        setupAboutView = nil
        firstRunSetupView = nil
        firstRunSeparatorView = nil
        stateValueLabel = nil
        focusWallpaperValueLabel = nil
        normalPresetValueLabel = nil
        automaticSyncValueLabel = nil
        syncLastRunValueLabel = nil
        syncLastErrorValueLabel = nil
        launchAtLoginValueLabel = nil
        aboutVersionValueLabel = nil
        aboutDeveloperValueLabel = nil
        aboutBuildDateValueLabel = nil
        aboutBundleIdentifierValueLabel = nil
        aboutURLSchemeValueLabel = nil
        aboutAppPathValueLabel = nil
        aboutLogPathValueLabel = nil
        syncIntervalPopup = nil
        syncToggleButton = nil
        launchAtLoginButton = nil
        clearNormalPresetButton = nil
    }

    @objc private func showHomeSetupSection() {
        selectedSetupSection = .home
        updateSetupSectionVisibility()
    }

    @objc private func showSettingsSetupSection() {
        selectedSetupSection = .settings
        updateSetupSectionVisibility()
    }

    @objc private func showAboutSetupSection() {
        selectedSetupSection = .about
        updateSetupSectionVisibility()
    }

    private func updateSetupSectionVisibility() {
        setupHomeView?.isHidden = selectedSetupSection != .home
        setupSettingsView?.isHidden = selectedSetupSection != .settings
        setupAboutView?.isHidden = selectedSetupSection != .about

        setupHomeButton?.state = selectedSetupSection == .home ? .on : .off
        setupSettingsButton?.state = selectedSetupSection == .settings ? .on : .off
        setupAboutButton?.state = selectedSetupSection == .about ? .on : .off
    }

    private func makeSetupWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Focus Wallpaper"
        window.isReleasedWhenClosed = false
        window.delegate = self

        let contentView = NSView()
        window.contentView = contentView

        let homeTitle = label("Home", font: .boldSystemFont(ofSize: 24), textColor: .labelColor)
        let homeSummary = label(
            "Choose wallpapers and switch Focus Wallpaper manually when you need direct control.",
            font: .systemFont(ofSize: 13),
            textColor: .secondaryLabelColor
        )
        let settingsTitle = label("Settings", font: .boldSystemFont(ofSize: 24), textColor: .labelColor)
        let settingsSummary = label(
            "Configure Automatic Sync, shortcut tools, and startup behavior.",
            font: .systemFont(ofSize: 13),
            textColor: .secondaryLabelColor
        )
        let aboutTitle = label("About", font: .boldSystemFont(ofSize: 24), textColor: .labelColor)
        let aboutSummary = label(
            "App version, build, and support paths.",
            font: .systemFont(ofSize: 13),
            textColor: .secondaryLabelColor
        )

        let stateValue = valueLabel()
        let focusWallpaperValue = valueLabel()
        let normalPresetValue = valueLabel()
        let automaticSyncValue = valueLabel()
        let syncLastRunValue = valueLabel()
        let syncLastErrorValue = valueLabel()
        let launchAtLoginValue = valueLabel()
        let aboutVersionValue = valueLabel()
        let aboutDeveloperValue = valueLabel()
        let aboutBuildDateValue = valueLabel()
        let aboutBundleIdentifierValue = valueLabel()
        let aboutURLSchemeValue = valueLabel()
        let aboutAppPathValue = valueLabel()
        let aboutLogPathValue = valueLabel()
        stateValueLabel = stateValue
        focusWallpaperValueLabel = focusWallpaperValue
        normalPresetValueLabel = normalPresetValue
        automaticSyncValueLabel = automaticSyncValue
        syncLastRunValueLabel = syncLastRunValue
        syncLastErrorValueLabel = syncLastErrorValue
        launchAtLoginValueLabel = launchAtLoginValue
        aboutVersionValueLabel = aboutVersionValue
        aboutDeveloperValueLabel = aboutDeveloperValue
        aboutBuildDateValueLabel = aboutBuildDateValue
        aboutBundleIdentifierValueLabel = aboutBundleIdentifierValue
        aboutURLSchemeValueLabel = aboutURLSchemeValue
        aboutAppPathValueLabel = aboutAppPathValue
        aboutLogPathValueLabel = aboutLogPathValue

        let chooseFocusButton = button("Choose Focus Wallpaper...", action: #selector(chooseFocusWallpaper))
        let firstRunChooseFocusButton = button("Choose Focus Wallpaper...", action: #selector(chooseFocusWallpaper))
        let showFolderButton = button("Show Wallpaper Folder", action: #selector(showWallpaperFolder))
        let applyButton = button("Apply Focus Now", action: #selector(applyFocusWallpaperNow))
        let restoreButton = button("Restore Normal Now", action: #selector(restoreNormalNow))
        let useCurrentButton = button("Use Current as Normal", action: #selector(useCurrentAsNormalPreset))
        let chooseNormalButton = button("Choose Normal Wallpaper...", action: #selector(chooseNormalWallpaper))
        let clearNormalButton = button("Clear Normal Preset", action: #selector(clearNormalPreset))
        clearNormalPresetButton = clearNormalButton
        let firstRunOpenTemplateButton = button("Open Shortcut Template", action: #selector(openShortcutTemplate))
        let openTemplateButton = button("Open Shortcut Template", action: #selector(openShortcutTemplate))
        let testShortcutButton = button("Test Shortcut", action: #selector(testShortcut))
        let repairSyncButton = button("Repair Sync", action: #selector(repairAutomaticSync))
        let startAtLoginButton = button("Enable Start at Login", action: #selector(toggleLaunchAtLogin))
        launchAtLoginButton = startAtLoginButton

        let intervalPopup = NSPopUpButton()
        intervalPopup.translatesAutoresizingMaskIntoConstraints = false
        intervalPopup.addItems(withTitles: [
            "Every second",
            "Every 5 seconds",
            "Every 10 seconds",
            "Every minute"
        ])
        intervalPopup.item(at: 0)?.tag = 1
        intervalPopup.item(at: 1)?.tag = 5
        intervalPopup.item(at: 2)?.tag = 10
        intervalPopup.item(at: 3)?.tag = 60
        intervalPopup.selectItem(at: 2)
        intervalPopup.target = self
        intervalPopup.action = #selector(syncIntervalChanged)
        syncIntervalPopup = intervalPopup

        let toggleSyncButton = button("Enable Automatic Sync", action: #selector(toggleAutomaticSync))
        syncToggleButton = toggleSyncButton

        let manualButtons = horizontalStack([applyButton, restoreButton])
        let focusButtons = horizontalStack([chooseFocusButton, showFolderButton])
        let normalButtons = horizontalStack([useCurrentButton, chooseNormalButton, clearNormalButton])
        let syncButtons = horizontalStack([intervalPopup, toggleSyncButton])
        let syncToolButtons = horizontalStack([openTemplateButton, testShortcutButton, repairSyncButton])
        let startupButtons = horizontalStack([startAtLoginButton])
        let firstRunButtons = horizontalStack([firstRunChooseFocusButton, firstRunOpenTemplateButton])
        let firstRunText = label(
            "First run: choose a Focus wallpaper, then use URL automations or the sync shortcut template.",
            font: .systemFont(ofSize: 13),
            textColor: .secondaryLabelColor
        )
        let firstRunSetup = NSStackView(views: [
            sectionLabel("First Run"),
            firstRunText,
            firstRunButtons
        ])
        firstRunSetup.orientation = .vertical
        firstRunSetup.alignment = .width
        firstRunSetup.spacing = 8
        firstRunSetup.translatesAutoresizingMaskIntoConstraints = false
        firstRunSetupView = firstRunSetup
        let firstRunSeparator = separator()
        firstRunSeparatorView = firstRunSeparator

        let homeStack = setupContentStack([
            homeTitle,
            homeSummary,
            separator(),
            firstRunSetup,
            firstRunSeparator,
            sectionLabel("Wallpapers"),
            infoRow(title: "Focus wallpaper", value: focusWallpaperValue),
            focusButtons,
            infoRow(title: "Normal wallpaper", value: normalPresetValue),
            normalButtons,
            separator(),
            sectionLabel("Manual Actions"),
            infoRow(title: "State", value: stateValue),
            manualButtons
        ])

        let settingsStack = setupContentStack([
            settingsTitle,
            settingsSummary,
            separator(),
            sectionLabel("Automatic Sync"),
            infoRow(title: "Automatic sync", value: automaticSyncValue),
            infoRow(title: "Last run", value: syncLastRunValue),
            infoRow(title: "Last error", value: syncLastErrorValue),
            syncButtons,
            syncToolButtons,
            separator(),
            sectionLabel("Startup"),
            infoRow(title: "Start at Login", value: launchAtLoginValue),
            startupButtons
        ])

        let aboutStack = setupContentStack([
            aboutTitle,
            aboutSummary,
            separator(),
            infoRow(title: "Version", value: aboutVersionValue),
            infoRow(title: "Developer", value: aboutDeveloperValue),
            infoRow(title: "Build date", value: aboutBuildDateValue),
            infoRow(title: "Bundle ID", value: aboutBundleIdentifierValue),
            infoRow(title: "URL scheme", value: aboutURLSchemeValue),
            infoRow(title: "App path", value: aboutAppPathValue),
            infoRow(title: "Log", value: aboutLogPathValue)
        ])

        let homeView = homeStack
        let settingsView = settingsStack
        let aboutView = aboutStack
        setupHomeView = homeView
        setupSettingsView = settingsView
        setupAboutView = aboutView

        let sidebar = NSVisualEffectView()
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        sidebar.material = .sidebar
        sidebar.blendingMode = .withinWindow
        sidebar.state = .active

        let homeButton = navigationButton(
            symbolName: "house",
            accessibilityLabel: "Home",
            action: #selector(showHomeSetupSection)
        )
        let settingsButton = navigationButton(
            symbolName: "gearshape",
            accessibilityLabel: "Settings",
            action: #selector(showSettingsSetupSection)
        )
        let aboutButton = navigationButton(
            symbolName: "info.circle",
            accessibilityLabel: "About",
            action: #selector(showAboutSetupSection)
        )
        setupHomeButton = homeButton
        setupSettingsButton = settingsButton
        setupAboutButton = aboutButton

        let sidebarStack = NSStackView(views: [
            homeButton,
            settingsButton,
            aboutButton
        ])
        sidebarStack.orientation = .vertical
        sidebarStack.alignment = .centerX
        sidebarStack.spacing = 10
        sidebarStack.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(sidebarStack)

        let sidebarDivider = NSBox()
        sidebarDivider.boxType = .separator
        sidebarDivider.translatesAutoresizingMaskIntoConstraints = false

        let appTitle = label("Focus Wallpaper", font: .boldSystemFont(ofSize: 17), textColor: .labelColor)
        appTitle.maximumNumberOfLines = 1

        let contentArea = NSView()
        contentArea.translatesAutoresizingMaskIntoConstraints = false
        [homeView, settingsView, aboutView].forEach {
            contentArea.addSubview($0)
            NSLayoutConstraint.activate([
                $0.topAnchor.constraint(equalTo: contentArea.topAnchor, constant: 16),
                $0.leadingAnchor.constraint(equalTo: contentArea.leadingAnchor, constant: 28),
                $0.trailingAnchor.constraint(equalTo: contentArea.trailingAnchor, constant: -28),
                $0.bottomAnchor.constraint(lessThanOrEqualTo: contentArea.bottomAnchor, constant: -24)
            ])
        }

        contentView.addSubview(sidebar)
        contentView.addSubview(sidebarDivider)
        contentView.addSubview(appTitle)
        contentView.addSubview(contentArea)

        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sidebar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 64),

            sidebarStack.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 20),
            sidebarStack.centerXAnchor.constraint(equalTo: sidebar.centerXAnchor),

            sidebarDivider.topAnchor.constraint(equalTo: contentView.topAnchor),
            sidebarDivider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            sidebarDivider.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            sidebarDivider.widthAnchor.constraint(equalToConstant: 1),

            appTitle.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),
            appTitle.leadingAnchor.constraint(equalTo: sidebarDivider.trailingAnchor, constant: 28),
            appTitle.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),

            contentArea.topAnchor.constraint(equalTo: appTitle.bottomAnchor, constant: 8),
            contentArea.leadingAnchor.constraint(equalTo: sidebarDivider.trailingAnchor),
            contentArea.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            contentArea.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        updateSetupSectionVisibility()
        return window
    }

    private func setupContentStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .width
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
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

    private func sectionLabel(_ text: String) -> NSTextField {
        label(text, font: .systemFont(ofSize: 13, weight: .semibold), textColor: .labelColor)
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return button
    }

    private func navigationButton(symbolName: String, accessibilityLabel: String, action: Selector) -> NSButton {
        let button = NSButton(title: "", target: self, action: action)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: accessibilityLabel)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = accessibilityLabel
        button.setAccessibilityLabel(accessibilityLabel)
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.setButtonType(.toggle)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 42),
            button.heightAnchor.constraint(equalToConstant: 42)
        ])
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

    private func updateSetupWindowText(syncStatus providedSyncStatus: FocusSyncStatus? = nil) {
        guard setupWindow != nil else {
            return
        }

        let syncStatus = providedSyncStatus ?? focusSyncAgent.status()
        let metadata = AppMetadata.current
        let needsFirstRunSetup = preferences.focusWallpaperURL == nil
        firstRunSetupView?.isHidden = !needsFirstRunSetup
        firstRunSeparatorView?.isHidden = !needsFirstRunSetup
        stateValueLabel?.stringValue = appTriggerStateText()
        focusWallpaperValueLabel?.stringValue = description(for: preferences.focusWallpaperURL)
        normalPresetValueLabel?.stringValue = normalPresetText()
        clearNormalPresetButton?.isEnabled = preferences.normalWallpaperURL != nil
            || !preferences.normalSnapshot.isEmpty
        automaticSyncValueLabel?.stringValue = automaticSyncInitializationInProgress
            ? "Updating..."
            : automaticSyncText(status: syncStatus)
        syncLastRunValueLabel?.stringValue = syncLastRunText(syncStatus)
        syncLastErrorValueLabel?.stringValue = syncLastErrorText(syncStatus)
        syncToggleButton?.title = syncStatus.isInstalled ? "Disable Automatic Sync" : "Enable Automatic Sync"
        syncToggleButton?.isEnabled = !automaticSyncInitializationInProgress
        syncIntervalPopup?.isEnabled = !automaticSyncInitializationInProgress
        let startAtLoginState = startAtLogin.state
        launchAtLoginValueLabel?.stringValue = "\(startAtLoginState.displayText) (\(startAtLogin.backendName))"
        launchAtLoginButton?.title = startAtLoginState.isRegistered ? "Disable Start at Login" : "Enable Start at Login"
        aboutVersionValueLabel?.stringValue = metadata.version
        aboutDeveloperValueLabel?.stringValue = metadata.developer
        aboutBuildDateValueLabel?.stringValue = buildDateText(metadata.buildDate)
        aboutBundleIdentifierValueLabel?.stringValue = metadata.bundleIdentifier
        aboutURLSchemeValueLabel?.stringValue = metadata.urlScheme
        aboutAppPathValueLabel?.stringValue = metadata.appPath
        aboutLogPathValueLabel?.stringValue = metadata.logPath
        selectCurrentSyncInterval()
    }

    private func pollFocusState() {
        preferences.synchronize()

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

        let syncStatus = focusSyncAgent.status()
        updateMenu(syncStatus: syncStatus)
        updateSetupWindowText(syncStatus: syncStatus)
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

        if preferences.focusWallpaperApplied {
            preferences.shortcutFocusActive = true
            updateMenu()
            updateSetupWindowText()
            return
        }

        preferences.pendingRestoreSnapshot = wallpapers.snapshot()
        try wallpapers.setWallpaperOnAllScreens(focusWallpaperURL)
        preferences.focusWallpaperApplied = true
        preferences.shortcutFocusActive = true
        AppLog.shared.write("Applied Focus wallpaper from URL trigger: \(focusWallpaperURL.path)")
        updateMenu()
        updateSetupWindowText()
    }

    private func restoreNormalFromShortcutTrigger() throws {
        preferences.shortcutFocusActive = false

        guard preferences.focusWallpaperApplied else {
            updateMenu()
            updateSetupWindowText()
            return
        }

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
            if startAtLogin.state.isRegistered {
                try startAtLogin.remove()
                showMessage("Start at Login removed.", informativeText: "The app will no longer be launched automatically at login.")
            } else {
                try startAtLogin.install()
                showMessage(
                    "Start at Login installed.",
                    informativeText: "The app will launch the next time you log in. On recent macOS versions, you can review this in System Settings."
                )
            }
            updateMenu()
            updateSetupWindowText()
        } catch {
            showError("Could not update Start at Login.", error: error)
        }
    }

    @objc private func openShortcutTemplate() {
        guard let templateURL = shortcutTemplateURL() else {
            showMessage(
                "Shortcut template not found.",
                informativeText: "Rebuild the app bundle or open Resources/Focus Wallpaper Sync Template.txt from the project."
            )
            return
        }

        NSWorkspace.shared.open(templateURL)
        AppLog.shared.write("Opened shortcut template: \(templateURL.path)")
    }

    @objc private func testShortcut() {
        guard !shortcutTestInProgress else {
            showMessage("Shortcut test is already running.", informativeText: "Wait for the current test to finish.")
            return
        }

        shortcutTestInProgress = true
        let testTask = Task.detached(priority: .userInitiated) { () -> ShortcutTestResult in
            let controller = FocusSyncAgentController()

            do {
                return .succeeded(try controller.testShortcut())
            } catch {
                return .failed(error.localizedDescription)
            }
        }

        Task { @MainActor [weak self] in
            let result = await testTask.value
            guard let self else {
                return
            }

            self.shortcutTestInProgress = false

            switch result {
            case .succeeded(let action):
                AppLog.shared.write("Tested Focus Wallpaper Sync shortcut; result: \(action).")
                showMessage(
                    "Shortcut returned \(action).",
                    informativeText: "Focus Wallpaper Sync is returning a valid state."
                )
            case .failed(let message):
                AppLog.shared.write("Focus Wallpaper Sync shortcut test failed: \(message)")
                showMessage("Could not test Focus Wallpaper Sync.", informativeText: message)
            }

            updateMenu()
            updateSetupWindowText()
        }
    }

    @objc private func repairAutomaticSync() {
        guard !automaticSyncInitializationInProgress else {
            showMessage("Automatic Sync is busy.", informativeText: "Try again after the current operation finishes.")
            return
        }

        let interval = selectedSyncInterval()
        performAutomaticSyncChange(
            .install(interval: interval),
            successLog: "Automatic sync LaunchAgent repaired with interval \(interval) seconds.",
            failureTitle: "Could not repair Automatic Sync.",
            successMessage: (
                title: "Automatic Sync repaired.",
                details: "The LaunchAgent was rewritten and reloaded using the current app path."
            )
        )
    }

    private func shortcutTemplateURL() -> URL? {
        if let bundledURL = Bundle.main.url(forResource: "Focus Wallpaper Sync Template", withExtension: "txt") {
            return bundledURL
        }

        let developmentURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources", isDirectory: true)
            .appendingPathComponent("Focus Wallpaper Sync Template.txt")
        return FileManager.default.fileExists(atPath: developmentURL.path) ? developmentURL : nil
    }

    @objc private func toggleAutomaticSync() {
        guard !automaticSyncInitializationInProgress else {
            showMessage("Automatic Sync is busy.", informativeText: "Try again after the current operation finishes.")
            return
        }

        if focusSyncAgent.isInstalled {
            performAutomaticSyncChange(
                .remove,
                successLog: "Automatic sync disabled.",
                failureTitle: "Could not disable Automatic Sync."
            )
        } else {
            let interval = selectedSyncInterval()
            performAutomaticSyncChange(
                .install(interval: interval),
                successLog: "Automatic sync enabled every \(interval) seconds.",
                failureTitle: "Could not enable Automatic Sync."
            )
        }
    }

    @objc private func syncIntervalChanged() {
        guard !automaticSyncInitializationInProgress else {
            selectCurrentSyncInterval()
            showMessage("Automatic Sync is busy.", informativeText: "Try again after the current operation finishes.")
            return
        }

        let interval = selectedSyncInterval()

        guard focusSyncAgent.isInstalled else {
            preferences.automaticSyncInterval = interval
            updateMenu()
            updateSetupWindowText()
            return
        }

        performAutomaticSyncChange(
            .install(interval: interval),
            successLog: "Automatic sync interval changed to \(interval) seconds.",
            failureTitle: "Could not update the Automatic Sync interval."
        )
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

    private func updateMenu(syncStatus providedSyncStatus: FocusSyncStatus? = nil) {
        let syncStatus = providedSyncStatus ?? focusSyncAgent.status()
        focusStateItem.title = "Focus mode: \(isFocusActiveForDisplay() ? "Enabled" : "Disabled")"
        updateStatusButton(syncStatus: syncStatus)
        applyFocusNowItem.title = "Set Focus On"
        restoreNormalNowItem.title = "Set Focus Off"
        applyFocusNowItem.isEnabled = preferences.focusWallpaperURL != nil
        restoreNormalNowItem.isEnabled = preferences.focusWallpaperApplied
            || preferences.normalWallpaperURL != nil
            || !preferences.normalSnapshot.isEmpty
            || !preferences.pendingRestoreSnapshot.isEmpty
        applyFocusNowItem.isHidden = syncStatus.isInstalled
        restoreNormalNowItem.isHidden = syncStatus.isInstalled
        manualFocusSeparatorItem.isHidden = syncStatus.isInstalled
        switch startAtLogin.state {
        case .enabled:
            launchAtLoginItem.state = .on
        case .requiresApproval:
            launchAtLoginItem.state = .mixed
        case .disabled, .unavailable:
            launchAtLoginItem.state = .off
        }
    }

    private func updateStatusButton(syncStatus: FocusSyncStatus) {
        guard let button = statusItem.button else {
            return
        }

        if hasCurrentSyncError(syncStatus) {
            button.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Focus Wallpaper sync error")
        } else if isFocusActiveForDisplay() {
            button.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "Focus Wallpaper active")
        } else {
            button.image = NSImage(systemSymbolName: "moon", accessibilityDescription: "Focus Wallpaper idle")
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

    private func isFocusActiveForDisplay() -> Bool {
        if preferences.shortcutFocusActive || preferences.focusWallpaperApplied {
            return true
        }

        return INFocusStatusCenter.default.authorizationStatus == .authorized
            && INFocusStatusCenter.default.focusStatus.isFocused == true
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

    private func automaticSyncText(status: FocusSyncStatus) -> String {
        guard status.isInstalled else {
            return "Off"
        }

        var parts = ["On", intervalText(status.interval)]
        if let isLoaded = status.isLoaded {
            parts.append(isLoaded ? "loaded" : "not loaded")
        }

        return parts.joined(separator: ", ")
    }

    private func syncLastRunText(_ status: FocusSyncStatus) -> String {
        guard let result = status.lastResult else {
            return "No runs recorded"
        }

        guard let date = status.lastSyncDate else {
            return result
        }

        return "\(timestampText(date)): \(result)"
    }

    private func syncLastErrorText(_ status: FocusSyncStatus) -> String {
        guard let error = status.lastError else {
            return "None"
        }

        guard let date = status.lastErrorDate else {
            return error
        }

        return "\(timestampText(date)): \(error)"
    }

    private func hasCurrentSyncError(_ status: FocusSyncStatus) -> Bool {
        guard status.lastError != nil else {
            return false
        }

        guard let lastErrorDate = status.lastErrorDate else {
            return true
        }

        if let lastSyncDate = status.lastSyncDate, lastSyncDate > lastErrorDate {
            return false
        }

        return true
    }

    private func timestampText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        if Calendar.current.isDateInToday(date) {
            formatter.dateStyle = .none
            formatter.timeStyle = .medium
        } else {
            formatter.dateStyle = .short
            formatter.timeStyle = .short
        }
        return formatter.string(from: date)
    }

    private func buildDateText(_ date: Date?) -> String {
        guard let date else {
            return "Unknown"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
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
        } else if let item = syncIntervalPopup.itemArray.first(where: { $0.tag == 10 }) {
            syncIntervalPopup.select(item)
        } else {
            syncIntervalPopup.selectItem(at: 0)
        }
    }

    private func intervalText(_ interval: Int) -> String {
        switch interval {
        case 1:
            return "every second"
        case 5:
            return "every 5 seconds"
        case 10:
            return "every 10 seconds"
        case 60:
            return "every minute"
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
