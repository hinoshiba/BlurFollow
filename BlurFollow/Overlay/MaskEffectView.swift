import AppKit
import CoreImage
import QuartzCore

final class MaskEffectView: NSView {
    private static let granularityBlurFilterName = "blurFollowGranularityBlur"
    private static let mosaicFilterName = "blurFollowMosaic"

    private let visualEffect = NSVisualEffectView()
    private let frostTintView = NSView()
    private let outlineView = NSView()
    private var granularityBlurFilter: CIFilter?
    private var mosaicFilter: CIFilter?
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
    private(set) var renderedMosaicCellSize: CGFloat = 0
    private(set) var usesBackdropMosaicFilter = false
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
        visualEffect.layerUsesCoreImageFilters = true
        visualEffect.layer?.masksToBounds = true
        if let blurFilter = CIFilter(name: "CIGaussianBlur") {
            blurFilter.name = Self.granularityBlurFilterName
            blurFilter.setValue(0, forKey: kCIInputRadiusKey)
            granularityBlurFilter = blurFilter
            // Granularity controls the sampled backdrop, not the already-rendered material.
            visualEffect.backgroundFilters = [blurFilter]
        }
        if let mosaicFilter = CIFilter(name: "CIPixellate") {
            mosaicFilter.name = Self.mosaicFilterName
            mosaicFilter.setValue(8, forKey: kCIInputScaleKey)
            self.mosaicFilter = mosaicFilter
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
        let parameters = MaskVisualParameters.resolve(
            strength: region.strength,
            granularity: region.granularity,
            maskSize: bounds.size
        )
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
            // The visual-effect view applies CIPixellate to the actual backdrop. Keep a very light
            // cell tint above it so the area remains visible on flat-colour backgrounds. If Core
            // Image cannot create the public filter, the opaque grid is a fail-closed fallback.
            NSGraphicsContext.saveGraphicsState()
            path.addClip()
            let cell = CGFloat(parameters.mosaicCellSize)
            let tint = region.tint.components
            let columns = Int(ceil(bounds.width / cell))
            let rows = Int(ceil(bounds.height / cell))
            let hasBackdropPixelation = mosaicFilter != nil
            for row in 0..<rows {
                for column in 0..<columns {
                    let alternate = (row + column) % 2 == 0
                    let alpha = hasBackdropPixelation ? (alternate ? 0.10 : 0.06) : 1
                    let color = alternate
                        ? NSColor(
                            calibratedRed: CGFloat(min(1, tint.red * 0.85 + 0.04)),
                            green: CGFloat(min(1, tint.green * 0.85 + 0.04)),
                            blue: CGFloat(min(1, tint.blue * 0.85 + 0.04)),
                            alpha: CGFloat(alpha)
                        )
                        : NSColor(
                            calibratedRed: CGFloat(tint.red * 0.65),
                            green: CGFloat(tint.green * 0.65),
                            blue: CGFloat(tint.blue * 0.65),
                            alpha: CGFloat(alpha)
                        )
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
            || self.region.granularity != region.granularity
            || self.region.tint != region.tint
            || self.region.borderEnabled != region.borderEnabled
            || self.region.cornerRadius != region.cornerRadius
            || self.forceRedact != forceRedact
            || renderedSize != bounds.size
        self.region = region
        self.forceRedact = forceRedact
        let effectiveStyleChanged = previousEffectiveStyle != effectiveStyle
        guard appearanceChanged || effectiveStyleChanged else { return false }

        let parameters = MaskVisualParameters.resolve(
            strength: region.strength,
            granularity: region.granularity,
            maskSize: bounds.size
        )
        renderedSize = bounds.size
        let isFrost = effectiveStyle == .frost
        let isMosaic = effectiveStyle == .mosaic
        visualEffect.isHidden = !isFrost && !isMosaic
        frostTintView.isHidden = !isFrost && !isMosaic
        // Mosaic must transform the complete backdrop rather than reveal a readable original
        // through a partially transparent decorative grid. Strength still controls its colour
        // treatment, while Granularity controls the sampled pixel-cell size.
        visualEffect.alphaValue = isMosaic ? 1 : CGFloat(parameters.frostEffectOpacity)
        let targetBlurRadius = CGFloat(parameters.frostAdditionalBlurRadius)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if isFrost, let granularityBlurFilter {
            granularityBlurFilter.setValue(targetBlurRadius, forKey: kCIInputRadiusKey)
            // Reassigning the public NSView property makes the changed filter input immediately
            // visible without depending on Core Animation's string-based filter key paths.
            visualEffect.backgroundFilters = [granularityBlurFilter]
            renderedFrostBlurRadius = targetBlurRadius
            renderedMosaicCellSize = 0
            usesBackdropMosaicFilter = false
        } else if isMosaic, let mosaicFilter {
            mosaicFilter.setValue(parameters.mosaicCellSize, forKey: kCIInputScaleKey)
            mosaicFilter.setValue(
                CIVector(x: bounds.midX, y: bounds.midY),
                forKey: kCIInputCenterKey
            )
            visualEffect.backgroundFilters = [mosaicFilter]
            renderedFrostBlurRadius = 0
            renderedMosaicCellSize = CGFloat(parameters.mosaicCellSize)
            usesBackdropMosaicFilter = true
        } else {
            visualEffect.backgroundFilters = []
            renderedFrostBlurRadius = 0
            renderedMosaicCellSize = isMosaic ? CGFloat(parameters.mosaicCellSize) : 0
            usesBackdropMosaicFilter = false
        }
        let tint = region.tint.components
        let tintOpacity = isMosaic
            ? 0.06 + (0.24 * min(max(region.strength, 0), 1))
            : parameters.frostTintOpacity
        frostTintView.layer?.backgroundColor = NSColor(
            calibratedRed: CGFloat(tint.red),
            green: CGFloat(tint.green),
            blue: CGFloat(tint.blue),
            alpha: CGFloat(tintOpacity)
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
        let showsConfiguredBorder = region.style == .redact || region.borderEnabled
        outlineView.isHidden = forceRedact || (!showsConfiguredBorder && !isEditing)
        let tint = region.tint.components
        outlineView.layer?.borderColor = NSColor(
            calibratedRed: CGFloat(min(1, tint.red * 1.4 + 0.18)),
            green: CGFloat(min(1, tint.green * 1.4 + 0.18)),
            blue: CGFloat(min(1, tint.blue * 1.4 + 0.18)),
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
