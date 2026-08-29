import AppKit

/// One click-through overlay window for all text matches produced by one saved rule.
///
/// Keeping the panel at the source-window bounds lets every OCR occurrence share the same
/// WindowServer surface. Only the mask effect subviews are added and removed as matches change.
final class TextFollowOverlayPanel: NSPanel {
    private let overlayView = TextFollowOverlayView()

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        contentView = overlayView
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
    }

    @discardableResult
    func update(
        rule: TextFollowRule,
        windowFrame: CGRect,
        normalizedRects: [UnitRect],
        usesSafetyCover: Bool = false
    ) -> Bool {
        let targetFrame = windowFrame.integral
        let geometryChanged = frame != targetFrame
        if geometryChanged {
            setFrame(targetFrame, display: false, animate: false)
        }
        let effectsChanged = overlayView.update(
            rule: rule,
            windowFrame: windowFrame,
            panelFrame: targetFrame,
            normalizedRects: normalizedRects,
            usesSafetyCover: usesSafetyCover
        )
        return geometryChanged || effectsChanged
    }

    func clearMatches() {
        overlayView.removeAllMatchViews()
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

private final class TextFollowOverlayView: NSView {
    private var matchViews: [MaskEffectView] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @discardableResult
    func update(
        rule: TextFollowRule,
        windowFrame: CGRect,
        panelFrame: CGRect,
        normalizedRects: [UnitRect],
        usesSafetyCover: Bool
    ) -> Bool {
        var changed = resizeMatchViews(to: normalizedRects.count, rule: rule)

        for (index, normalizedRect) in normalizedRects.enumerated() {
            let matchView = matchViews[index]
            let absoluteFrame = normalizedRect.rect(in: windowFrame).integral
            let localFrame = absoluteFrame.offsetBy(
                dx: -panelFrame.minX,
                dy: -panelFrame.minY
            )
            if matchView.frame != localFrame {
                matchView.frame = localFrame
                changed = true
            }
            if matchView.update(
                region: Self.region(
                    for: rule,
                    normalizedRect: normalizedRect,
                    usesSafetyCover: usesSafetyCover
                )
            ) {
                changed = true
            }
        }

        return changed
    }

    func removeAllMatchViews() {
        guard !matchViews.isEmpty else { return }
        matchViews.forEach { $0.removeFromSuperview() }
        matchViews.removeAll(keepingCapacity: false)
    }

    private func resizeMatchViews(to count: Int, rule: TextFollowRule) -> Bool {
        guard matchViews.count != count else { return false }

        while matchViews.count > count {
            matchViews.removeLast().removeFromSuperview()
        }
        while matchViews.count < count {
            let matchView = MaskEffectView(
                region: Self.region(for: rule, normalizedRect: .full)
            )
            addSubview(matchView)
            matchViews.append(matchView)
        }
        return true
    }

    private static func region(
        for rule: TextFollowRule,
        normalizedRect: UnitRect,
        usesSafetyCover: Bool = false
    ) -> MaskRegion {
        MaskRegion(
            id: rule.id,
            name: "",
            mode: .window,
            normalizedRect: normalizedRect,
            windowAnchor: rule.windowAnchor,
            style: .mosaic,
            strength: rule.strength,
            granularity: rule.granularity,
            tint: rule.tint,
            borderEnabled: usesSafetyCover ? false : rule.borderEnabled,
            cornerRadius: usesSafetyCover ? 0 : rule.cornerRadius,
            isEnabled: true,
            createdAt: rule.createdAt
        )
    }
}
