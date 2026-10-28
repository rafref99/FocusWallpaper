import Foundation

/// Read-only interpretation of the version-8 Assertions store. This is an
/// undocumented macOS format; unknown versions or malformed data are errors.
public enum LocalFocusState {
    public static func isActive(in data: Data) throws -> Bool {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let header = root["header"] as? [String: Any],
              let version = header["version"] as? Int else { throw ReadError.invalidFormat }
        guard version == 8 else { throw ReadError.unsupportedVersion(version) }
        guard let stores = root["data"] as? [[String: Any]], stores.count == 1 else { throw ReadError.invalidFormat }
        let store = stores[0]
        // Version 8 omits the live-record key when no Focus is active.
        guard let rawRecords = store["storeAssertionRecords"] else {
            let knownKeys: Set<String> = ["storeInvalidationRecords", "storeInvalidationRequestRecords"]
            guard Set(store.keys).isSubset(of: knownKeys), store.values.allSatisfy({ $0 is [Any] }) else {
                throw ReadError.invalidFormat
            }
            return false
        }
        guard let records = rawRecords as? [[String: Any]] else { throw ReadError.invalidFormat }
        for record in records {
            guard let details = record["assertionDetails"] as? [String: Any],
                  let identifier = details["assertionDetailsModeIdentifier"] as? String,
                  !identifier.isEmpty else { throw ReadError.invalidFormat }
        }
        return !records.isEmpty
    }

    public enum ReadError: LocalizedError {
        case invalidFormat, unsupportedVersion(Int)
        public var errorDescription: String? {
            switch self {
            case .invalidFormat: return "The local Focus state is incomplete or unrecognized. Waiting for a valid update."
            case .unsupportedVersion(let version): return "macOS uses Focus data version \(version), which this app does not yet support."
            }
        }
    }
}
