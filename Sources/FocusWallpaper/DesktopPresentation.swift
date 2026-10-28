import AppKit

private final class DesktopWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DesktopPresentation {
    private(set) var windows: [NSWindow] = []
    private var image: NSImage?

    func show(_ url: URL) throws {
        guard let image = NSImage(contentsOf: url), image.isValid else {
            throw NSError(domain: "FocusWallpaper", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Choose an available image file."])
        }
        self.image = image
        rebuild()
    }

    func rebuild() {
        guard let image else { return }
        let previous = windows
        windows = NSScreen.screens.map { screen in
            let window = DesktopWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            // Same level as the wallpaper, ordered above it but below desktop icons.
            window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
            if #available(macOS 13.0, *) { window.collectionBehavior.insert(.canJoinAllApplications) }
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.hasShadow = false
            window.isOpaque = true
            window.backgroundColor = .black
            window.isExcludedFromWindowsMenu = true
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer?.contents = image
            view.layer?.contentsGravity = .resizeAspectFill
            view.layer?.masksToBounds = true
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            return window
        }
        previous.forEach { $0.orderOut(nil); $0.close() }
    }

    func hide() {
        windows.forEach { $0.orderOut(nil); $0.close() }
        windows.removeAll()
        image = nil
    }
}
