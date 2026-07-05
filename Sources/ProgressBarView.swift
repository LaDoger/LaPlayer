import Cocoa

/// A minimal seek bar: thin track, filled progress, and a small thumb.
/// Click or drag anywhere on it to seek.
final class ProgressBarView: NSView {
    var progress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    var onSeek: ((CGFloat) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let trackHeight: CGFloat = 4
        let trackRect = NSRect(x: 0, y: bounds.midY - trackHeight / 2, width: bounds.width, height: trackHeight)

        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2).fill()

        let filledWidth = max(trackHeight, bounds.width * progress)
        if progress > 0 {
            let filledRect = NSRect(x: 0, y: trackRect.minY, width: filledWidth, height: trackHeight)
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: filledRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2).fill()
        }

        let thumbDiameter: CGFloat = 10
        let thumbX = (bounds.width * progress) - thumbDiameter / 2
        let thumbRect = NSRect(x: thumbX, y: bounds.midY - thumbDiameter / 2, width: thumbDiameter, height: thumbDiameter)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: thumbRect).fill()
    }

    override func mouseDown(with event: NSEvent) { seek(with: event) }
    override func mouseDragged(with event: NSEvent) { seek(with: event) }

    private func seek(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let fraction = min(max(point.x / bounds.width, 0), 1)
        progress = fraction
        onSeek?(fraction)
    }
}
