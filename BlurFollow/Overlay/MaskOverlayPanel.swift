import AppKit

final class MaskOverlayPanel: NSPanel {
    private let effectView: MaskEffectView
    var onMoveEnded: ((CGRect) -> Void)?

    var isDragging: Bool { effectView.isDragging }
    var renderedFrostBlurRadius: CGFloat { effectView.renderedFrostBlurRadius }

    override var canBecomeKey: Bool { effectView.isEditing }
    override var canBecomeMain: Bool { false }

    init(region: MaskRegion) {
        effectView = MaskEffectView(region: region)
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = effectView
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isReleasedWhenClosed = false
        effectView.onDragEnded = { [weak self] frame in
            self?.onMoveEnded?(frame)
        }
    }

    @discardableResult
    func update(
        region: MaskRegion,
        frame: CGRect,
        forceRedact: Bool = false,
        isEditing: Bool = false,
        movementBounds: CGRect? = nil
    ) -> Bool {
        let targetFrame = frame.integral
        var geometryChanged = false
        if !effectView.isDragging {
            geometryChanged = self.frame != targetFrame
            if geometryChanged {
                // Moving a window does not require redrawing its contents. A resize is detected by
                // MaskEffectView below and invalidates only the effect surface.
                setFrame(targetFrame, display: false, animate: false)
            }
        }
        let appearanceChanged = effectView.update(region: region, forceRedact: forceRedact)
        let editingChanged = setEditing(
            isEditing && !forceRedact,
            movementBounds: movementBounds
        )
        return geometryChanged || appearanceChanged || editingChanged
    }

    @discardableResult
    func setEditing(
        _ editing: Bool,
        movementBounds: CGRect? = nil,
        restoreInitialFrame: Bool = true
    ) -> Bool {
        let effectChanged = effectView.setEditing(
            editing,
            movementBounds: movementBounds,
            restoreInitialFrame: restoreInitialFrame
        )
        let shouldIgnoreMouseEvents = !editing
        let hitTestingChanged = ignoresMouseEvents != shouldIgnoreMouseEvents
        if hitTestingChanged { ignoresMouseEvents = shouldIgnoreMouseEvents }
        return effectChanged || hitTestingChanged
    }

    func showIfNeeded() {
        guard !isVisible else { return }
        orderFrontRegardless()
    }

    func hideIfNeeded() {
        guard isVisible else { return }
        orderOut(nil)
    }
}
