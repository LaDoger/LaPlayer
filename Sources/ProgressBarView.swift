import Cocoa

/// A minimal seek bar: thin track, filled progress, and a small thumb.
/// Click or drag anywhere on it to seek.
final class ProgressBarView: NSView {
    var progress: CGFloat = 0 {
        didSet { needsDisplay = true }
    }
    /// Trim in/out points as fractions of the duration, or nil if unset.
    var trimStartFraction: CGFloat? {
        didSet { needsDisplay = true }
    }
    var trimEndFraction: CGFloat? {
        didSet { needsDisplay = true }
    }
    var onSeek: ((CGFloat) -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let trackHeight: CGFloat = 4
        let trackRect = NSRect(x: 0, y: bounds.midY - trackHeight / 2, width: bounds.width, height: trackHeight)

        NSColor.white.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2).fill()

        // Shade the selected trim range on the track.
        if let s = trimStartFraction, let e = trimEndFraction {
            let lo = min(s, e), hi = max(s, e)
            let rangeRect = NSRect(x: bounds.width * lo, y: trackRect.minY,
                                   width: bounds.width * (hi - lo), height: trackHeight)
            NSColor.systemYellow.withAlphaComponent(0.5).setFill()
            NSBezierPath(rect: rangeRect).fill()
        }

        let filledWidth = max(trackHeight, bounds.width * progress)
        if progress > 0 {
            let filledRect = NSRect(x: 0, y: trackRect.minY, width: filledWidth, height: trackHeight)
            NSColor.white.withAlphaComponent(0.9).setFill()
            NSBezierPath(roundedRect: filledRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2).fill()
        }

        drawTrimMarker(trimStartFraction, color: .systemGreen)
        drawTrimMarker(trimEndFraction, color: .systemRed)

        let thumbDiameter: CGFloat = 10
        let thumbX = (bounds.width * progress) - thumbDiameter / 2
        let thumbRect = NSRect(x: thumbX, y: bounds.midY - thumbDiameter / 2, width: thumbDiameter, height: thumbDiameter)
        NSColor.white.setFill()
        NSBezierPath(ovalIn: thumbRect).fill()
    }

    private func drawTrimMarker(_ fraction: CGFloat?, color: NSColor) {
        guard let fraction else { return }
        let markerWidth: CGFloat = 2.5
        let markerHeight: CGFloat = 14
        let x = bounds.width * fraction - markerWidth / 2
        let rect = NSRect(x: x, y: bounds.midY - markerHeight / 2, width: markerWidth, height: markerHeight)
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: markerWidth / 2, yRadius: markerWidth / 2).fill()
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
