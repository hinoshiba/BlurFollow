import AppKit
import CoreGraphics

/// A rectangle expressed as fractions of a containing rectangle.
/// Keeping placements normalized makes masks survive window and display resizing.
struct UnitRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let full = UnitRect(x: 0, y: 0, width: 1, height: 1)

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(rect: CGRect, in container: CGRect) {
        guard container.width > 0, container.height > 0 else {
            self = .full
            return
        }
        self.init(
            x: (rect.minX - container.minX) / container.width,
            y: (rect.minY - container.minY) / container.height,
            width: rect.width / container.width,
            height: rect.height / container.height
        )
        self = clamped()
    }

    func rect(in container: CGRect) -> CGRect {
        CGRect(
            x: container.minX + CGFloat(x) * container.width,
            y: container.minY + CGFloat(y) * container.height,
            width: CGFloat(width) * container.width,
            height: CGFloat(height) * container.height
        )
    }

    func clamped(minimumSize: Double = 0.002) -> UnitRect {
        let safeWidth = min(max(width, minimumSize), 1)
        let safeHeight = min(max(height, minimumSize), 1)
        return UnitRect(
            x: min(max(x, 0), 1 - safeWidth),
            y: min(max(y, 0), 1 - safeHeight),
            width: safeWidth,
            height: safeHeight
        )
    }
}

struct CodableRect: Codable, Hashable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var cgRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}

enum MaskDragGeometry {
    /// Keeps a moved mask completely inside its current display or source-window frame.
    /// The mask size is preserved unless the source container has become smaller than the mask.
    static func clampedFrame(_ proposedFrame: CGRect, inside container: CGRect) -> CGRect? {
        let values = [
            proposedFrame.minX, proposedFrame.minY, proposedFrame.width, proposedFrame.height,
            container.minX, container.minY, container.width, container.height
        ]
        guard values.allSatisfy(\.isFinite),
              proposedFrame.width > 0,
              proposedFrame.height > 0,
              container.width > 0,
              container.height > 0 else {
            return nil
        }

        let width = min(proposedFrame.width, container.width)
        let height = min(proposedFrame.height, container.height)
        let x = min(max(proposedFrame.minX, container.minX), container.maxX - width)
        let y = min(max(proposedFrame.minY, container.minY), container.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func normalizedRect(for proposedFrame: CGRect, inside container: CGRect) -> UnitRect? {
        guard let clamped = clampedFrame(proposedFrame, inside: container) else { return nil }
        return UnitRect(rect: clamped, in: container)
    }
}

enum ScreenCoordinates {
    /// Quartz window bounds use a top-left origin. AppKit windows use a bottom-left origin.
    /// Both coordinate spaces use the primary display as their reference plane.
    static func appKitRect(fromQuartz rect: CGRect, primaryDisplayHeight: CGFloat? = nil) -> CGRect {
        let height = primaryDisplayHeight ?? NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    static func quartzRect(fromAppKit rect: CGRect, primaryDisplayHeight: CGFloat? = nil) -> CGRect {
        let height = primaryDisplayHeight ?? NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }
}

extension NSScreen {
    var blurFollowIdentifier: String {
        guard
            let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
            let uuid = CGDisplayCreateUUIDFromDisplayID(CGDirectDisplayID(number.uint32Value))?.takeRetainedValue()
        else {
            return localizedName
        }
        return CFUUIDCreateString(nil, uuid) as String
    }

    static func blurFollowScreen(identifier: String?) -> NSScreen? {
        guard let identifier else { return screens.first }
        return screens.first { $0.blurFollowIdentifier == identifier } ?? screens.first
    }

    static func bestMatch(for rect: CGRect) -> NSScreen? {
        screens.max { lhs, rhs in
            lhs.frame.intersection(rect).area < rhs.frame.intersection(rect).area
        }
    }
}

private extension CGRect {
    var area: CGFloat { isNull || isInfinite ? 0 : width * height }
}
