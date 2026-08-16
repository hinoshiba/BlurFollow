import AppKit
import CoreImage
import QuartzCore

final class MaskEffectView: NSView {
    private static let strengthBlurFilterName = "blurFollowStrengthBlur"

    private let visualEffect = NSVisualEffectView()
    private let frostTintView = NSView()
    private let outlineView = NSView()
    private var strengthBlurFilter: CIFilter?
    private var region: MaskRegion
    private var forceRedact = false
    private var dragStartMouseLocation: CGPoint?
    private var dragStartWindowFrame: CGRect?
    private var editingStartWindowFrame: CGRect?
    private var movementBounds: CGRect?
    private var renderedSize: CGSize?
    private(set) var isDragging = false
    private(set) var isEditing = false
    private(set) var renderedFrostBlurRadius: CGFloat = 0
    var onDragEnded: ((CGRect) -> Void)?

    init(region: MaskRegion) {
        self.region = region
        super.init(frame: .zero)
        wantsLayer = true
        visualEffect.blendingMode = .behindWindow
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.autoresizingMask = [.width, .height]
        visualEffect.wantsLayer = true
        visualEffect.layer?.masksToBounds = true
        if let blurFilter = CIFilter(name: "CIGaussianBlur") {
            blurFilter.name = Self.strengthBlurFilterName
            blurFilter.setValue(0, forKey: kCIInputRadiusKey)
            strengthBlurFilter = blurFilter
            visualEffect.contentFilters = [blurFilter]
        }
        addSubview(visualEffect)

        frostTintView.wantsLayer = true
        frostTintView.autoresizingMask = [.width, .height]
        addSubview(frostTintView)

        outlineView.wantsLayer = true
        outlineView.autoresizingMask = [.width, .height]
        addSubview(outlineView)

        postsFrameChangedNotifications = true
        update(region: region)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        visualEffect.frame = bounds
        frostTintView.frame = bounds
        outlineView.frame = bounds
        layer?.cornerRadius = effectiveCornerRadius
        visualEffect.layer?.cornerRadius = effectiveCornerRadius
        frostTintView.layer?.cornerRadius = effectiveCornerRadius
        outlineView.layer?.cornerRadius = effectiveCornerRadius
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
            // Frost is rendered by the visual-effect and tint subviews. Keeping the tint above
            // the material prevents the material from hiding the visible Strength difference.
            break
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

        let parameters = MaskVisualParameters.resolve(strength: region.strength, maskSize: bounds.size)
        renderedSize = bounds.size
        let isFrost = effectiveStyle == .frost
        visualEffect.isHidden = !isFrost
        frostTintView.isHidden = !isFrost
        visualEffect.alphaValue = CGFloat(parameters.frostEffectOpacity)
        let targetBlurRadius = CGFloat(parameters.frostAdditionalBlurRadius)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let strengthBlurFilter {
            strengthBlurFilter.setValue(targetBlurRadius, forKey: kCIInputRadiusKey)
            // Reassigning the public NSView property makes the changed filter input immediately
            // visible without depending on Core Animation's string-based filter key paths.
            visualEffect.contentFilters = [strengthBlurFilter]
            renderedFrostBlurRadius = targetBlurRadius
        } else {
            renderedFrostBlurRadius = 0
        }
        frostTintView.layer?.backgroundColor = NSColor(
            calibratedRed: 0.16,
            green: 0.18,
            blue: 0.38,
            alpha: CGFloat(parameters.frostTintOpacity)
        ).cgColor
        layer?.cornerRadius = effectiveCornerRadius
        layer?.masksToBounds = true
        visualEffect.layer?.cornerRadius = effectiveCornerRadius
        frostTintView.layer?.cornerRadius = effectiveCornerRadius
        outlineView.layer?.cornerRadius = effectiveCornerRadius
        updateOutline()
        CATransaction.commit()
        needsDisplay = true
        return true
    }

    @discardableResult
    func setEditing(
        _ editing: Bool,
        movementBounds: CGRect? = nil,
        restoreInitialFrame: Bool = true
    ) -> Bool {
        self.movementBounds = editing ? movementBounds : nil

        if editing {
            if isEditing {
                // The followed source can move between entering Move mode and pressing the mask.
                // Keep cancellation anchored to the latest non-dragging overlay frame.
                if !isDragging { editingStartWindowFrame = window?.frame }
                return false
            }
            isEditing = true
            editingStartWindowFrame = window?.frame
        } else {
            guard isEditing else { return false }
            if restoreInitialFrame, let editingStartWindowFrame, let window {
                window.setFrame(editingStartWindowFrame, display: false, animate: false)
            }
            isEditing = false
            isDragging = false
            dragStartMouseLocation = nil
            dragStartWindowFrame = nil
            editingStartWindowFrame = nil
            NSCursor.arrow.set()
        }
        discardCursorRects()
        resetCursorRects()
        updateOutline()
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

    override var needsPanelToBecomeKey: Bool {
        // Borderless panels cannot normally become key. A nonactivating panel asks the hit view
        // whether it needs key status before delivering its first interaction.
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
        dragStartWindowFrame = window.frame
        discardCursorRects()
        resetCursorRects()
        NSCursor.closedHand.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isEditing,
              isDragging,
              let window,
              let startMouse = dragStartMouseLocation,
              let startFrame = dragStartWindowFrame else { return }
        let currentMouse = NSEvent.mouseLocation
        let proposedFrame = CGRect(
            x: startFrame.minX + currentMouse.x - startMouse.x,
            y: startFrame.minY + currentMouse.y - startMouse.y,
            width: startFrame.width,
            height: startFrame.height
        )
        let targetFrame = movementBounds.flatMap {
            MaskDragGeometry.clampedFrame(proposedFrame, inside: $0)
        } ?? proposedFrame
        window.setFrame(targetFrame, display: false, animate: false)
    }

    override func mouseUp(with event: NSEvent) {
        guard isEditing, isDragging, let window else { return }
        isDragging = false
        dragStartMouseLocation = nil
        dragStartWindowFrame = nil
        discardCursorRects()
        resetCursorRects()
        onDragEnded?(window.frame)
    }

    private func updateOutline() {
        outlineView.isHidden = forceRedact
        outlineView.layer?.borderColor = NSColor(
            calibratedRed: 0.43,
            green: 0.37,
            blue: 0.96,
            alpha: isEditing ? 1 : 0.75
        ).cgColor
        outlineView.layer?.borderWidth = isEditing ? 3 : 1
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
