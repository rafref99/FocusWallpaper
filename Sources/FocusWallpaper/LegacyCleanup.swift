import Foundation

/// Only used once to retire old installations. No new launch job is registered.
enum LegacyCleanup {
    static func run() throws {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents")
        for label in ["local.focus-wallpaper-sync", "local.focus-wallpaper"] {
            let service = "gui/\(getuid())/\(label)"
            // Address the loaded service by label even when its plist is missing.
            let loaded = try launchctl(["print", service]) == 0
            if loaded {
                let result = try launchctl(["bootout", service])
                guard try result == 0 || launchctl(["print", service]) != 0 else {
                    throw NSError(domain: "FocusWallpaper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not stop the old background service \(label)."] )
                }
            }
            let plist = directory.appendingPathComponent(label + ".plist")
            if FileManager.default.fileExists(atPath: plist.path) { try FileManager.default.removeItem(at: plist) }
        }
    }
    private static func launchctl(_ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(5)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.02) }
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            process.waitUntilExit()
            throw NSError(domain: "FocusWallpaper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Removing the old background service timed out. Try reopening the app."] )
        }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

