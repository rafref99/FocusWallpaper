import XCTest
@testable import FocusWallpaperCore

final class LocalFocusStateTests: XCTestCase {
    private func read(_ store: String, version: Int = 8) throws -> Bool {
        try LocalFocusState.isActive(in: Data("{\"header\":{\"version\":\(version)},\"data\":[\(store)]}".utf8))
    }
    func testActiveMode() throws {
        XCTAssertTrue(try read(#"{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.work"}}]}"#))
    }
    func testExplicitOff() throws { XCTAssertFalse(try read(#"{"storeAssertionRecords":[]}"#)) }
    func testOmittedRecordsWithHistoryMeansOff() throws {
        XCTAssertFalse(try read(#"{"storeInvalidationRecords":[{}],"storeInvalidationRequestRecords":[]}"#))
        XCTAssertFalse(try read("{}"))
    }
    func testUnknownSchemaIsNotOff() {
        XCTAssertThrowsError(try read("{}", version: 9))
        XCTAssertThrowsError(try read(#"{"newActiveRecords":[]}"#))
        XCTAssertThrowsError(try LocalFocusState.isActive(in: Data(#"{"data":[{}]}"#.utf8)))
    }
    func testMalformedRecordsAreNotOff() {
        for store in [#"{"storeAssertionRecords":null}"#, #"{"storeAssertionRecords":{}}"#, #"{"storeAssertionRecords":[{}]}"#] {
            XCTAssertThrowsError(try read(store))
        }
        XCTAssertThrowsError(try LocalFocusState.isActive(in: Data("{".utf8)))
    }
}
