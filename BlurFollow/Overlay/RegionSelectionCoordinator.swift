import AppKit
import Combine

@MainActor
final class RegionSelectionCoordinator: ObservableObject {
    @Published private(set) var isSelecting = false
    private var panels: [SelectionPanel] = []
    private var completion: ((CGRect?) -> Void)?

    func select(on frames: [CGRect], completion: @escaping (CGRect?) -> Void) {
        cancel()
        self.completion = completion
        isSelecting = true

        panels = frames.map { frame in
            let panel = SelectionPanel(frame: frame)
            panel.selectionHandler = { [weak self, weak panel] localRect in
                guard let self, let panel else { return }
                let screenRect = localRect.map { panel.convertToScreen($0) }
                self.finish(screenRect)
            }
            panel.orderFrontRegardless()
            return panel
        }
        panels.first?.makeKey()
        NSCursor.crosshair.push()
    }

    func cancel() {
        guard isSelecting else { return }
        finish(nil)
    }

    private func finish(_ rect: CGRect?) {
        panels.forEach { $0.close() }
        panels.removeAll()
        if isSelecting { NSCursor.pop() }
        isSelecting = false
        let callback = completion
        completion = nil
        callback?(rect)
    }
}

private final class SelectionPanel: NSPanel {
    var selectionHandler: ((CGRect?) -> Void)? {
        didSet { canvas.selectionHandler = selectionHandler }
    }
    private let canvas = SelectionCanvasView()

    init(frame: CGRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .none
        isReleasedWhenClosed = false
        contentView = canvas
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
}

private final class SelectionCanvasView: NSView {
    var selectionHandler: ((CGRect?) -> Void)?
    private var startPoint: CGPoint?
    private var currentPoint: CGPoint?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        let rect = selectionRect
        selectionHandler?(rect.width >= 24 && rect.height >= 24 ? rect : nil)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            selectionHandler?(nil)
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.02, alpha: 0.44).setFill()
        bounds.fill()

        if startPoint != nil, currentPoint != nil {
            let rect = selectionRect
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .clear
            NSColor.clear.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
            NSGraphicsContext.restoreGraphicsState()

            NSColor(calibratedRed: 0.49, green: 0.42, blue: 1, alpha: 1).setStroke()
            let outline = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)
            outline.lineWidth = 3
            outline.stroke()
        }

        drawInstruction()
    }

    private var selectionRect: CGRect {
        guard let startPoint, let currentPoint else { return .zero }
        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(startPoint.x - currentPoint.x),
            height: abs(startPoint.y - currentPoint.y)
        )
    }

    private func drawInstruction() {
        let text = String(localized: "Drag to select an area · Esc to cancel")
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let size = text.size(withAttributes: attributes)
        let box = CGRect(x: bounds.midX - size.width / 2 - 18, y: bounds.maxY - 72, width: size.width + 36, height: 42)
        NSColor(calibratedWhite: 0.04, alpha: 0.86).setFill()
        NSBezierPath(roundedRect: box, xRadius: 13, yRadius: 13).fill()
        text.draw(at: CGPoint(x: box.minX + 18, y: box.minY + 11), withAttributes: attributes)
    }
}
