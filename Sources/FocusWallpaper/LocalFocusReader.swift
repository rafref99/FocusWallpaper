import Foundation
import FocusWallpaperCore

final class LocalFocusReader {
    static var defaultDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB", isDirectory: true)
    }
    private let defaults = UserDefaults.standard
    private let bookmarkKey = "focusStateDirectoryBookmark"
    private var directory = LocalFocusReader.defaultDirectory
    private var hasScopedAccess = false

    init() {
        guard let data = defaults.data(forKey: bookmarkKey) else { return }
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
            directory = url
            hasScopedAccess = url.startAccessingSecurityScopedResource()
            if stale, let refreshed = try? url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil) {
                defaults.set(refreshed, forKey: bookmarkKey)
            }
        }
    }
    deinit { if hasScopedAccess { directory.stopAccessingSecurityScopedResource() } }

    func grantAccess(to url: URL) throws {
        guard url.standardizedFileURL == Self.defaultDirectory.standardizedFileURL else {
            throw ReaderError.wrongFolder
        }
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess], includingResourceValuesForKeys: nil, relativeTo: nil)
            if hasScopedAccess { directory.stopAccessingSecurityScopedResource() }
            directory = url
            hasScopedAccess = scoped
            defaults.set(bookmark, forKey: bookmarkKey)
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    func read() throws -> Bool {
        let url = directory.appendingPathComponent("Assertions.json")
        do {
            // Bound reads and reopen each time: macOS may replace the file atomically.
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let limit = 2 * 1024 * 1024
            let data = try handle.read(upToCount: limit + 1) ?? Data()
            guard data.count <= limit else { throw LocalFocusState.ReadError.invalidFormat }
            return try LocalFocusState.isActive(in: data)
        } catch let error as LocalFocusState.ReadError { throw error }
        // FileHandle can report Cocoa's write-permission code for an EPERM
        // even when opened read-only. Do not surface a misleading "save" error.
        catch let error as CocoaError where error.code == .fileReadNoPermission || error.code == .fileWriteNoPermission {
            throw ReaderError.noPermission
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw ReaderError.missingFile
        }
    }
    enum ReaderError: LocalizedError {
        case wrongFolder, noPermission, missingFile
        var errorDescription: String? {
            switch self {
            case .wrongFolder: return "Choose your Library/DoNotDisturb/DB folder."
            case .noPermission: return "macOS blocked the Focus state file. Use Allow Focus file access. If still blocked, grant this app Full Disk Access in System Settings → Privacy & Security, then reopen it."
            case .missingFile: return "The Focus state file is missing. Turn a Focus mode on once, then try again."
            }
        }
    }
}
