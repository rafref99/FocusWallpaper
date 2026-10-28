import XCTest
@testable import FocusWallpaperCore

final class FocusPresentationTests: XCTestCase {
    private let image = URL(fileURLWithPath: "/focus.jpg")
    func testOffRemovesPresentationWithoutWallpaperRestore() throws {
        var displayed: URL?
        let controller = FocusPresentation(show: { displayed = $0 }, hide: { displayed = nil })
        try controller.update(focused: true, image: image)
        XCTAssertEqual(displayed, image)
        try controller.update(focused: false, image: image)
        XCTAssertNil(displayed)
        XCTAssertNil(controller.activeImage)
    }
    func testRepeatedOnDoesNotRecreatePresentation() throws {
        var shows = 0
        let controller = FocusPresentation(show: { _ in shows += 1 }, hide: {})
        try controller.update(focused: true, image: image)
        try controller.update(focused: true, image: image)
        XCTAssertEqual(shows, 1)
    }
    func testUnknownDoesNotHideActiveImage() throws {
        var hides = 0
        let controller = FocusPresentation(show: { _ in }, hide: { hides += 1 })
        try controller.update(focused: true, image: image)
        try controller.update(focused: nil, image: image)
        XCTAssertEqual(controller.activeImage, image)
        XCTAssertEqual(hides, 0)
    }
    func testPauseOrQuitAlwaysClearsPresentation() throws {
        var hides = 0
        let controller = FocusPresentation(show: { _ in }, hide: { hides += 1 })
        try controller.update(focused: true, image: image)
        controller.stop()
        XCTAssertNil(controller.activeImage)
        XCTAssertEqual(hides, 1)
    }
    func testImageReplacementAndFailure() throws {
        struct Failure: Error {}
        let next = URL(fileURLWithPath: "/next.jpg")
        var fail = false
        var displayed: URL?
        let controller = FocusPresentation(show: { if fail { throw Failure() }; displayed = $0 }, hide: { displayed = nil })
        try controller.update(focused: true, image: image)
        fail = true
        XCTAssertThrowsError(try controller.update(focused: true, image: next))
        XCTAssertEqual(controller.activeImage, image)
        XCTAssertEqual(displayed, image)
        fail = false
        try controller.update(focused: true, image: next)
        XCTAssertEqual(displayed, next)
    }
}
