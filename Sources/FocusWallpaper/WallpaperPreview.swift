import AppKit

/// The layout owns the preview size; the image's pixel dimensions must not
/// contribute to the window's minimum fitting size.
final class WallpaperPreview: NSImageView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}
