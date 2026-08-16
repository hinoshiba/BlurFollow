import Foundation
import CoreGraphics

enum PinMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case display
    case window

    var id: String { rawValue }

    var title: String {
        switch self {
        case .display: return String(localized: "Display Pin")
        case .window: return String(localized: "Window Pin")
        }
    }

    var systemImage: String {
        switch self {
        case .display: return "display"
        case .window: return "macwindow.badge.plus"
        }
    }
}

enum MaskStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case frost
    case mosaic
    case redact

    var id: String { rawValue }

    var title: String {
        switch self {
        case .frost: return String(localized: "Frost")
        case .mosaic: return String(localized: "Mosaic")
        case .redact: return String(localized: "Redact")
        }
    }

    var detail: String {
        switch self {
        case .frost: return String(localized: "Softens the selected area. Check readability before sharing.")
        case .mosaic: return String(localized: "Pixelates the selected area. Check the preview before sharing.")
        case .redact: return String(localized: "Draws an opaque fill over the selected rectangle.")
        }
    }
}

/// Public-API-only rendering values shared by the desktop overlay.
///
/// `NSVisualEffectView` does not expose a blur-radius control. Frost therefore maps strength to
/// the opacity of the system material plus its tint, while Mosaic maps it to tile size and
/// opacity. Keeping the mapping here makes the slider's effect deterministic and testable.
struct MaskVisualParameters: Equatable, Sendable {
    var normalizedStrength: Double
    var frostEffectOpacity: Double
    var frostTintOpacity: Double
    var mosaicCellSize: Double
    var mosaicOpacity: Double

    static func resolve(strength: Double, maskSize: CGSize) -> MaskVisualParameters {
        let value = strength.isFinite ? min(max(strength, 0), 1) : 0
        let dimensions = [Double(maskSize.width), Double(maskSize.height)]
            .filter { $0.isFinite && $0 > 0 }
        let shortestSide = dimensions.min() ?? 1
        let weakCellSize = max(8, min(18, shortestSide / 18))
        let strongCellSize = max(24, min(64, shortestSide / 5))

        return MaskVisualParameters(
            normalizedStrength: value,
            frostEffectOpacity: 0.25 + (0.75 * value),
            frostTintOpacity: 0.08 + (0.42 * value),
            mosaicCellSize: weakCellSize + ((strongCellSize - weakCellSize) * value),
            mosaicOpacity: 0.55 + (0.43 * value)
        )
    }
}

struct WindowAnchor: Codable, Hashable, Sendable {
    /// Stable only for the lifetime of the source window; identity fields are used to rebind later.
    var windowID: UInt32
    var bundleIdentifier: String
    var applicationName: String
    var windowTitle: String
    var initialFrame: CodableRect
    /// A process identifier is session-scoped. It prevents a recycled window ID from silently
    /// binding to another process; title and application identity are used after an app relaunch.
    var processID: Int32? = nil
}

struct MaskRegion: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var mode: PinMode
    var normalizedRect: UnitRect
    var displayIdentifier: String?
    var windowAnchor: WindowAnchor?
    var style: MaskStyle
    var strength: Double
    var cornerRadius: Double
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        mode: PinMode,
        normalizedRect: UnitRect,
        displayIdentifier: String? = nil,
        windowAnchor: WindowAnchor? = nil,
        style: MaskStyle = .frost,
        strength: Double = 0.78,
        cornerRadius: Double = 12,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.normalizedRect = normalizedRect.clamped()
        self.displayIdentifier = displayIdentifier
        self.windowAnchor = windowAnchor
        self.style = style
        self.strength = min(max(strength, 0), 1)
        self.cornerRadius = min(max(cornerRadius, 0), 40)
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}

enum TrackingState: Equatable, Sendable {
    case positionKnown
    case reconnecting
    case unavailable

    var title: String {
        switch self {
        case .positionKnown: return String(localized: "Position found")
        case .reconnecting: return String(localized: "Finding window")
        case .unavailable: return String(localized: "Select again")
        }
    }
}
