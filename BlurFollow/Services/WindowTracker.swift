import AppKit
import CoreGraphics

struct TrackedWindowFrame: Sendable {
    let windowID: CGWindowID
    let processID: pid_t
    let appKitFrame: CGRect
    let isOnScreen: Bool
}

/// Tracks a user-selected window using public WindowServer metadata. A binding is trusted only
/// while its window ID, process, layer, and application identity remain continuous. If continuity
/// breaks, rebinding requires one unambiguous identity match; uncertainty returns `nil` so callers
/// can decline ambiguous matches and request a new selection.
@MainActor
final class WindowTracker: ObservableObject {
    private struct Binding {
        var windowID: CGWindowID
        var processID: pid_t
        var bundleIdentifier: String
        var applicationName: String
        var isContinuous: Bool
    }

    private struct InspectedWindow {
        var frame: TrackedWindowFrame
        var processID: pid_t
        var bundleIdentifier: String
        var applicationName: String
        var title: String
    }

    /// Shares WindowServer results across all masks in one visual refresh. Several masks commonly
    /// follow the same browser window, so querying that window once per mask creates avoidable main
    /// thread work and visible lag while the source moves.
    @MainActor
    private final class RefreshLookup {
        private enum CachedInformation {
            case found([String: Any])
            case missing
        }

        private var informationByID: [CGWindowID: CachedInformation] = [:]
        private var allWindowsCache: [[String: Any]]?
        private var loadedAllWindows = false

        func information(for windowID: CGWindowID) -> [String: Any]? {
            if let cached = informationByID[windowID] {
                switch cached {
                case .found(let information): return information
                case .missing: return nil
                }
            }

            let information = WindowTracker.information(for: windowID)
            informationByID[windowID] = information.map(CachedInformation.found) ?? .missing
            return information
        }

        func allWindows() -> [[String: Any]]? {
            if loadedAllWindows { return allWindowsCache }
            loadedAllWindows = true
            allWindowsCache = CGWindowListCopyWindowInfo(
                [.optionAll, .excludeDesktopElements],
                kCGNullWindowID
            ) as? [[String: Any]]
            return allWindowsCache
        }
    }

    private var bindings: [UUID: Binding] = [:]

    func bind(_ candidate: WindowCandidate, to regionID: UUID) {
        bindings[regionID] = Binding(
            windowID: candidate.id,
            processID: candidate.processID,
            bundleIdentifier: candidate.bundleIdentifier,
            applicationName: candidate.applicationName,
            isContinuous: true
        )
    }

    func unbind(regionID: UUID) {
        bindings[regionID] = nil
    }

    func frame(for region: MaskRegion) -> TrackedWindowFrame? {
        frame(for: region, lookup: RefreshLookup())
    }

    /// Resolves every region against one metadata snapshot/cache. Identity continuity and
    /// unambiguous-rebind rules remain identical to `frame(for:)`.
    func frames(for regions: [MaskRegion]) -> [UUID: TrackedWindowFrame] {
        let lookup = RefreshLookup()
        var result: [UUID: TrackedWindowFrame] = [:]
        result.reserveCapacity(regions.count)
        for region in regions {
            if let frame = frame(for: region, lookup: lookup) {
                result[region.id] = frame
            }
        }
        return result
    }

    private func frame(for region: MaskRegion, lookup: RefreshLookup) -> TrackedWindowFrame? {
        guard let anchor = region.windowAnchor else { return nil }

        if var binding = bindings[region.id], binding.isContinuous {
            if let inspected = Self.inspect(
                windowID: binding.windowID,
                anchor: anchor,
                expectedProcessID: binding.processID,
                requireStoredTitle: false,
                lookup: lookup
            ) {
                return inspected.frame
            }

            // Once an observed ID disappears or changes identity, never silently trust it again.
            // A recycled CGWindowID can otherwise move a mask onto an unrelated window.
            binding.isContinuous = false
            bindings[region.id] = binding
        }

        if let inspected = Self.inspect(
            windowID: anchor.windowID,
            anchor: anchor,
            expectedProcessID: anchor.processID,
            requireStoredTitle: true,
            lookup: lookup
        ) {
            bindings[region.id] = Self.binding(from: inspected)
            return inspected.frame
        }

        guard let replacement = Self.unambiguousRebind(anchor: anchor, lookup: lookup) else { return nil }
        bindings[region.id] = Self.binding(from: replacement)
        return replacement.frame
    }

    private static func binding(from window: InspectedWindow) -> Binding {
        Binding(
            windowID: window.frame.windowID,
            processID: window.processID,
            bundleIdentifier: window.bundleIdentifier,
            applicationName: window.applicationName,
            isContinuous: true
        )
    }

    private static func inspect(
        windowID: CGWindowID,
        anchor: WindowAnchor,
        expectedProcessID: pid_t?,
        requireStoredTitle: Bool,
        lookup: RefreshLookup
    ) -> InspectedWindow? {
        guard let info = lookup.information(for: windowID) else { return nil }
        return inspectedWindow(
            from: info,
            anchor: anchor,
            expectedProcessID: expectedProcessID,
            requireStoredTitle: requireStoredTitle
        )
    }

    private static func inspectedWindow(
        from info: [String: Any],
        anchor: WindowAnchor,
        expectedProcessID: pid_t?,
        requireStoredTitle: Bool
    ) -> InspectedWindow? {
        guard
            let idNumber = info[kCGWindowNumber as String] as? NSNumber,
            let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
            let layerNumber = info[kCGWindowLayer as String] as? NSNumber,
            layerNumber.intValue == 0,
            let quartzRect = bounds(from: info),
            quartzRect.width >= 80,
            quartzRect.height >= 60
        else { return nil }

        let processID = pid_t(ownerPIDNumber.int32Value)
        if let expectedProcessID, expectedProcessID != processID { return nil }

        let application = NSRunningApplication(processIdentifier: processID)
        let bundleIdentifier = application?.bundleIdentifier ?? ""
        let applicationName = info[kCGWindowOwnerName as String] as? String
            ?? application?.localizedName
            ?? ""
        let sameApplication = !anchor.bundleIdentifier.isEmpty
            ? bundleIdentifier == anchor.bundleIdentifier
            : (!anchor.applicationName.isEmpty && applicationName == anchor.applicationName)
        guard sameApplication else { return nil }

        let title = info[kCGWindowName as String] as? String ?? ""
        if requireStoredTitle, !anchor.windowTitle.isEmpty, title != anchor.windowTitle {
            return nil
        }

        // Missing visibility metadata is uncertainty, not proof that a window is visible.
        let isOnScreen = (info[kCGWindowIsOnscreen as String] as? Bool) ?? false
        return InspectedWindow(
            frame: TrackedWindowFrame(
                windowID: CGWindowID(idNumber.uint32Value),
                processID: processID,
                appKitFrame: ScreenCoordinates.appKitRect(fromQuartz: quartzRect),
                isOnScreen: isOnScreen
            ),
            processID: processID,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            title: title
        )
    }

    private static func unambiguousRebind(
        anchor: WindowAnchor,
        lookup: RefreshLookup
    ) -> InspectedWindow? {
        guard let list = lookup.allWindows() else { return nil }

        let matches = list.compactMap { info -> InspectedWindow? in
            guard let candidate = inspectedWindow(
                from: info,
                anchor: anchor,
                expectedProcessID: nil,
                requireStoredTitle: !anchor.windowTitle.isEmpty
            ) else { return nil }
            // Rebinding to a hidden/off-Space window is not verifiable enough for automatic
            // placement. The user can bring it forward and BlurFollow will retry.
            return candidate.frame.isOnScreen ? candidate : nil
        }

        // Geometry is never an identity proof. Multiple same-app/title windows require an explicit
        // user selection rather than an automatic rebind.
        guard matches.count == 1 else { return nil }
        return matches[0]
    }

    private static func information(for windowID: CGWindowID) -> [String: Any]? {
        (CGWindowListCopyWindowInfo([.optionIncludingWindow], windowID) as? [[String: Any]])?.first
    }

    private static func bounds(from info: [String: Any]) -> CGRect? {
        guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }
}
