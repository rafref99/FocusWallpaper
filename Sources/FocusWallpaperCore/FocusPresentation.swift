import Foundation

/// Owns a temporary desktop presentation, never the system wallpaper settings.
public final class FocusPresentation {
    private let show: (URL) throws -> Void
    private let hide: () -> Void
    public private(set) var activeImage: URL?

    public init(show: @escaping (URL) throws -> Void, hide: @escaping () -> Void) {
        self.show = show
        self.hide = hide
    }

    public func update(focused: Bool?, image: URL?) throws {
        guard let focused else { return }
        guard focused else { stop(); return }
        guard let image, image != activeImage else { return }
        try show(image)
        activeImage = image
    }

    public func stop() {
        hide()
        activeImage = nil
    }
}
