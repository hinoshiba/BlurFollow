import AppKit

final class MaskEffectView: NSView {
    private let visualEffect = NSVisualEffectView()
    private var region: MaskRegion
    private var forceRedact = false
    private var dragStartMouseLocation: CGPoint?
    private var dragStartWindowOrigin: CGPoint?
    private var renderedSize: CGSize?
    private(set) var isDragging = false
    private(set) var isEditing = false
    var onDragEnded: ((CGRect) -> Void)?

    init(region: MaskRegion) {
        self.region = region
        super.init(frame: .zero)
        wantsLayer = true
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        addSubview(visualEffect)
        postsFrameChangedNotifications = true
        update(region: region)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        visualEffect.frame = bounds
        layer?.cornerRadius = effectiveCornerRadius
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let parameters = MaskVisualParameters.resolve(strength: region.strength, maskSize: bounds.size)
        let path = NSBezierPath(
            roundedRect: bounds,
            xRadius: effectiveCornerRadius,
            yRadius: effectiveCornerRadius
        )

        switch effectiveStyle {
        case .frost:
            NSColor(
                calibratedRed: 0.16,
                green: 0.18,
                blue: 0.38,
                alpha: CGFloat(parameters.frostTintOpacity)
            ).setFill()
            path.fill()
        case .mosaic:
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let cell = CGFloat(parameters.mosaicCellSize)
            let columns = Int(ceil(bounds.width / cell))
            let rows = Int(ceil(bounds.height / cell))
            for row in 0..<rows {
                for column in 0..<columns {
                    let alternate = (row + column) % 2 == 0
                    let alpha = min(1, parameters.mosaicOpacity + (alternate ? 0.05 : 0))
                    let color = alternate
                        ? NSColor(calibratedRed: 0.17, green: 0.20, blue: 0.35, alpha: CGFloat(alpha))
                        : NSColor(calibratedRed: 0.10, green: 0.13, blue: 0.25, alpha: CGFloat(alpha))
                    color.setFill()
                    NSRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell + 1, height: cell + 1).fill()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        case .redact:
            NSColor(calibratedRed: 0.055, green: 0.063, blue: 0.10, alpha: 1).setFill()
            path.fill()
        }

        if isEditing {
            NSColor(calibratedRed: 0.43, green: 0.37, blue: 0.96, alpha: 1).setStroke()
            path.lineWidth = 3
            path.stroke()
        } else if !forceRedact {
            NSColor(calibratedRed: 0.43, green: 0.37, blue: 0.96, alpha: 0.75).setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }

    @discardableResult
    func update(region: MaskRegion, forceRedact: Bool = false) -> Bool {
        let previousEffectiveStyle = effectiveStyle
        let appearanceChanged = self.region.style != region.style
            || self.region.strength != region.strength
            || self.region.cornerRadius != region.cornerRadius
            || self.forceRedact != forceRedact
            || renderedSize != bounds.size
        self.region = region
        self.forceRedact = forceRedact
        let effectiveStyleChanged = previousEffectiveStyle != effectiveStyle
        guard appearanceChanged || effectiveStyleChanged else { return false }

        renderedSize = bounds.size
        visualEffect.isHidden = effectiveStyle != .frost
        visualEffect.alphaValue = CGFloat(
            MaskVisualParameters.resolve(strength: region.strength, maskSize: bounds.size)
                .frostEffectOpacity
        )
        layer?.cornerRadius = effectiveCornerRadius
        layer?.masksToBounds = true
        needsDisplay = true
        return true
    }

    @discardableResult
    func setEditing(_ editing: Bool) -> Bool {
        guard isEditing != editing else { return false }
        isEditing = editing
        if !editing {
            isDragging = false
            dragStartMouseLocation = nil
            dragStartWindowOrigin = nil
            NSCursor.arrow.set()
        }
        discardCursorRects()
        resetCursorRects()
        needsDisplay = true
        return true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isEditing, bounds.contains(point) else { return super.hitTest(point) }
        // The visual-effect subview fills our bounds. Return self while editing so drag events
        // reach this view; the containing panel is click-through at all other times.
        return self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        isEditing
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard isEditing else { return }
        addCursorRect(bounds, cursor: isDragging ? .closedHand : .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        guard isEditing, let window else { return }
        isDragging = true
        dragStartMouseLocation = NSEvent.mouseLocation
        dragStartWindowOrigin = window.frame.origin
        discardCursorRects()
        resetCursorRects()
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing,
              isDragging,
              let window,
              let startMouse = dragStartMouseLocation,
              let startOrigin = dragStartWindowOrigin else { return }
        let currentMouse = NSEvent.mouseLocation
        window.setFrameOrigin(CGPoint(
            x: startOrigin.x + currentMouse.x - startMouse.x,
            y: startOrigin.y + currentMouse.y - startMouse.y
        ))
    }

    override func mouseUp(with event: NSEvent) {
        guard isEditing, isDragging, let window else { return }
        isDragging = false
        dragStartMouseLocation = nil
        dragStartWindowOrigin = nil
        discardCursorRects()
        resetCursorRects()
        onDragEnded?(window.frame)
    }

    private var effectiveCornerRadius: CGFloat {
        forceRedact ? 0 : CGFloat(region.cornerRadius)
    }

    private var effectiveStyle: MaskStyle {
        // Reduce Transparency removes the material effect. Use the opaque style so the visible
        // result still matches the selected mask area instead of becoming a faint tint.
        if forceRedact || (region.style == .frost && NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency) {
            return .redact
        }
        return region.style
    }
}
