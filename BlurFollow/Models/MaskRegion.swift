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

enum MaskTint: String, Codable, CaseIterable, Identifiable, Sendable {
    case neutral
    case cool
    case warm
    case mint

    var id: String { rawValue }

    var title: String {
        switch self {
        case .neutral: return String(localized: "Neutral")
        case .cool: return String(localized: "Cool")
        case .warm: return String(localized: "Warm")
        case .mint: return String(localized: "Mint")
        }
    }

    var components: (red: Double, green: Double, blue: Double) {
        switch self {
        case .neutral: return (0.30, 0.32, 0.36)
        // Cool matches the tint used before Frost colors became configurable.
        case .cool: return (0.16, 0.18, 0.38)
        case .warm: return (0.42, 0.23, 0.14)
        case .mint: return (0.12, 0.34, 0.29)
        }
    }
}

/// Public-API-only rendering values shared by the desktop overlay.
///
/// `NSVisualEffectView` does not expose a blur-radius control. Granularity therefore maps to a
/// public Core Image background-filter radius for Frost and tile size for Mosaic, while Strength maps
/// to overall effect intensity. It is deliberately not presented as an exact alpha percentage.
/// Keeping the mapping here makes both sliders' effects deterministic and testable.
struct MaskVisualParameters: Equatable, Sendable {
    var normalizedStrength: Double
    var normalizedGranularity: Double
    var frostEffectOpacity: Double
    var frostTintOpacity: Double
    var frostAdditionalBlurRadius: Double
    var mosaicCellSize: Double
    var mosaicOpacity: Double

    static func resolve(
        strength: Double,
        granularity: Double? = nil,
        maskSize: CGSize
    ) -> MaskVisualParameters {
        let value = strength.isFinite ? min(max(strength, 0), 1) : 0
        // Falling back to Strength preserves the pre-customization rendering for call sites that
        // do not yet provide a separate granularity value.
        let requestedGranularity = granularity ?? value
        let resolvedGranularity = requestedGranularity.isFinite
            ? min(max(requestedGranularity, 0), 1)
            : 0
        let dimensions = [Double(maskSize.width), Double(maskSize.height)]
            .filter { $0.isFinite && $0 > 0 }
        let shortestSide = dimensions.min() ?? 1
        let weakCellSize = max(8, min(18, shortestSide / 18))
        let strongCellSize = max(24, min(64, shortestSide / 5))

        return MaskVisualParameters(
            normalizedStrength: value,
            normalizedGranularity: resolvedGranularity,
            frostEffectOpacity: 0.25 + (0.75 * value),
            frostTintOpacity: 0.08 + (0.42 * value),
            // NSVisualEffectView's material has a fixed system blur. Applying a public Core Image
            // background filter on top gives Granularity a real, continuous radius control that no
            // longer changes when the user adjusts Strength.
            frostAdditionalBlurRadius: 24 * resolvedGranularity,
            mosaicCellSize: weakCellSize + ((strongCellSize - weakCellSize) * resolvedGranularity),
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
    var granularity: Double
    var tint: MaskTint
    var borderEnabled: Bool
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
        granularity: Double = 0.78,
        tint: MaskTint = .cool,
        borderEnabled: Bool = true,
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
        self.granularity = min(max(granularity, 0), 1)
        self.tint = tint
        self.borderEnabled = borderEnabled
        self.cornerRadius = min(max(cornerRadius, 0), 40)
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case mode
        case normalizedRect
        case displayIdentifier
        case windowAnchor
        case style
        case strength
        case granularity
        case tint
        case borderEnabled
        case cornerRadius
        case isEnabled
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        mode = try container.decode(PinMode.self, forKey: .mode)
        normalizedRect = try container.decode(UnitRect.self, forKey: .normalizedRect)
        displayIdentifier = try container.decodeIfPresent(String.self, forKey: .displayIdentifier)
        windowAnchor = try container.decodeIfPresent(WindowAnchor.self, forKey: .windowAnchor)
        style = try container.decode(MaskStyle.self, forKey: .style)
        strength = try container.decode(Double.self, forKey: .strength)
        // Legacy snapshots used Strength for blur/cell size as well as effect intensity. Use it as
        // the migration default so loading an existing mask does not unexpectedly change its look.
        granularity = try container.decodeIfPresent(Double.self, forKey: .granularity)
            ?? strength
        tint = try container.decodeIfPresent(MaskTint.self, forKey: .tint) ?? .cool
        borderEnabled = try container.decodeIfPresent(Bool.self, forKey: .borderEnabled)
            ?? true
        cornerRadius = try container.decode(Double.self, forKey: .cornerRadius)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
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
