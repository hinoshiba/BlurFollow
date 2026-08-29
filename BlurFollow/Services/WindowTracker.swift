import AppKit
import CoreGraphics

struct TrackedWindowFrame: Equatable, Sendable {
    let windowID: CGWindowID
    let processID: pid_t
    let appKitFrame: CGRect
    let isOnScreen: Bool
}

enum TrackedWindowResolution: Equatable, Sendable {
    case frame(TrackedWindowFrame)
    /// WindowServer did not provide enough data to decide whether the selected window disappeared.
    case uncertain
    /// A complete lookup positively found no safe, unambiguous continuation of the selected window.
    case unavailable
}

enum WindowTrackingInspectionRole {
    case continuousIdentity
    case savedAnchor
    case automaticRebindCandidate

    /// Exact WindowServer identity may legitimately shrink after selection or between launches.
    /// The larger minimum is only a picker/rebind heuristic for rejecting utility artifacts.
    var allowsSmallGeometry: Bool {
        self != .automaticRebindCandidate
    }

    /// Titles are mutable content for an exact WindowServer ID/PID tuple. They are only evidence
    /// when choosing a different window automatically.
    var requiresStoredTitleMatch: Bool {
        self != .continuousIdentity
    }
}

enum WindowTrackingContinuityPolicy {
    static func allowsAutomaticResolution(hasConfirmedDiscontinuity: Bool) -> Bool {
        !hasConfirmedDiscontinuity
    }

    static func requiresExplicitRebind(after mismatch: WindowTrackingMismatchKind) -> Bool {
        mismatch == .identity
    }
}

enum WindowTrackingMismatchKind: Equatable {
    /// Process, layer, application, or exact WindowServer identity was positively rejected.
    case identity
    /// A persisted anchor still exists at its ID but its session-independent title evidence changed.
    case savedTitle
}

/// A complete all-window snapshot can fill in a partial targeted record only when it proves the
/// exact saved identity. A different same-app/same-title window never resolves that uncertainty.
enum WindowTrackingExactIdentityPolicy {
    static func matches(
        anchorWindowID: CGWindowID,
        anchorProcessID: pid_t?,
        candidate: TrackedWindowFrame
    ) -> Bool {
        guard
            candidate.windowID == anchorWindowID,
            let anchorProcessID,
            candidate.processID == anchorProcessID
        else { return false }
        return true
    }
}

/// Pure indexing for a batched WindowServer response. Only requested IDs are retained, and an
/// unexpected duplicate is rejected instead of choosing an arbitrary identity dictionary.
enum WindowDescriptionBatch {
    static func informationByID(
        from descriptions: [[String: Any]],
        requestedWindowIDs: Set<CGWindowID>
    ) -> [CGWindowID: [String: Any]] {
        var result: [CGWindowID: [String: Any]] = [:]
        var duplicateIDs: Set<CGWindowID> = []
        result.reserveCapacity(requestedWindowIDs.count)

        for description in descriptions {
            guard
                let idNumber = description[kCGWindowNumber as String] as? NSNumber
            else { continue }
            let windowID = CGWindowID(idNumber.uint32Value)
            guard requestedWindowIDs.contains(windowID) else { continue }

            if result.updateValue(description, forKey: windowID) != nil {
                duplicateIDs.insert(windowID)
            }
        }

        for windowID in duplicateIDs {
            result[windowID] = nil
        }
        return result
    }
}

/// Tracks a user-selected window using public WindowServer metadata. A binding is trusted only
/// while its window ID, process, layer, and application identity remain continuous. If continuity
/// breaks, rebinding requires one unambiguous identity match; uncertainty returns `nil` so callers
/// can decline ambiguous matches and request a new selection.
@MainActor
final class WindowTracker: ObservableObject {
    private enum InspectionResult {
        case found(InspectedWindow)
        case missing
        case incomplete
        case mismatch(WindowTrackingMismatchKind)
    }

    private enum RebindResult {
        case found(InspectedWindow)
        case uncertain
        case unavailable
    }

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
        enum InformationResult {
            case found([String: Any])
            case absent
            case uncertain
        }

        private enum CachedInformation {
            case found([String: Any])
            case missing
        }

        private var informationByID: [CGWindowID: CachedInformation] = [:]
        private var allWindowsCache: [[String: Any]]?
        private var loadedAllWindows = false

        init(windowIDs: Set<CGWindowID>) {
            guard !windowIDs.isEmpty else { return }
            let descriptions = WindowTracker.descriptions(for: windowIDs) ?? []
            let prefetched = WindowDescriptionBatch.informationByID(
                from: descriptions,
                requestedWindowIDs: windowIDs
            )
            informationByID.reserveCapacity(windowIDs.count)
            for windowID in windowIDs {
                informationByID[windowID] = prefetched[windowID]
                    .map(CachedInformation.found) ?? .missing
            }
        }

        func information(for windowID: CGWindowID) -> InformationResult {
            guard let cached = informationByID[windowID] else {
                return .uncertain
            }
            switch cached {
            case .found(let information):
                return .found(information)
            case .missing:
                // The targeted description API can fail or transiently omit a live window. Use the
                // one cached all-window snapshot as a bounded fallback before declaring it absent.
                guard let list = allWindows() else { return .uncertain }
                let exact = list.filter { information in
                    guard let number = information[kCGWindowNumber as String] as? NSNumber else {
                        return false
                    }
                    return CGWindowID(number.uint32Value) == windowID
                }
                if exact.count == 1 { return .found(exact[0]) }
                return exact.isEmpty ? .absent : .uncertain
            }
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
    /// A positive process/layer/application identity rejection must not be undone by a later
    /// recycled ID. Only a fresh picker selection (`bind`) clears this process-lifetime tombstone.
    private var discontinuedTrackingIDs: Set<UUID> = []

    func bind(_ candidate: WindowCandidate, to regionID: UUID) {
        discontinuedTrackingIDs.remove(regionID)
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
        discontinuedTrackingIDs.remove(regionID)
    }

    func frame(for region: MaskRegion) -> TrackedWindowFrame? {
        guard let anchor = region.windowAnchor else { return nil }
        return frame(for: anchor, trackingID: region.id)
    }

    /// Resolves a saved window anchor for a runtime feature that is not represented by a
    /// `MaskRegion`. Text-follow rules use this path while retaining the same identity-continuity
    /// and unambiguous-rebind requirements as Window Pins.
    func frame(for anchor: WindowAnchor, trackingID: UUID) -> TrackedWindowFrame? {
        let anchors = [trackingID: anchor]
        let lookup = RefreshLookup(windowIDs: requiredWindowIDs(for: anchors))
        guard case .frame(let frame) = resolution(
            for: anchor,
            trackingID: trackingID,
            lookup: lookup
        ) else { return nil }
        return frame
    }

    /// Resolves every region against one metadata snapshot/cache. Identity continuity and
    /// unambiguous-rebind rules remain identical to `frame(for:)`.
    func frames(for regions: [MaskRegion]) -> [UUID: TrackedWindowFrame] {
        let anchors = Dictionary(uniqueKeysWithValues: regions.compactMap { region in
            region.windowAnchor.map { (region.id, $0) }
        })
        return frames(for: anchors)
    }

    /// Resolves several non-`MaskRegion` window anchors against one WindowServer snapshot.
    func frames(for anchors: [UUID: WindowAnchor]) -> [UUID: TrackedWindowFrame] {
        let resolutions = resolutions(for: anchors)
        var result: [UUID: TrackedWindowFrame] = [:]
        result.reserveCapacity(resolutions.count)
        for (trackingID, resolution) in resolutions {
            if case .frame(let frame) = resolution { result[trackingID] = frame }
        }
        return result
    }

    /// Resolves several anchors while retaining the distinction between an incomplete WindowServer
    /// query and a complete lookup that found no safe continuation. Text Follow uses this to keep a
    /// last-known safety cover only for transient uncertainty, never after confirmed disappearance.
    func resolutions(for anchors: [UUID: WindowAnchor]) -> [UUID: TrackedWindowResolution] {
        let lookup = RefreshLookup(windowIDs: requiredWindowIDs(for: anchors))
        var result: [UUID: TrackedWindowResolution] = [:]
        result.reserveCapacity(anchors.count)
        for (trackingID, anchor) in anchors {
            result[trackingID] = resolution(
                for: anchor,
                trackingID: trackingID,
                lookup: lookup
            )
        }
        return result
    }

    private func requiredWindowIDs(for anchors: [UUID: WindowAnchor]) -> Set<CGWindowID> {
        var windowIDs: Set<CGWindowID> = []
        windowIDs.reserveCapacity(anchors.count * 2)
        for (trackingID, anchor) in anchors {
            // `resolution` will return the process-lifetime tombstone without consulting metadata.
            // Excluding it here avoids a useless WindowServer query on every refresh tick.
            guard !discontinuedTrackingIDs.contains(trackingID) else { continue }
            if anchor.windowID != kCGNullWindowID {
                windowIDs.insert(anchor.windowID)
            }
            if let binding = bindings[trackingID],
               binding.isContinuous,
               binding.windowID != kCGNullWindowID {
                windowIDs.insert(binding.windowID)
            }
        }
        return windowIDs
    }

    private func resolution(
        for anchor: WindowAnchor,
        trackingID: UUID,
        lookup: RefreshLookup
    ) -> TrackedWindowResolution {
        guard WindowTrackingContinuityPolicy.allowsAutomaticResolution(
            hasConfirmedDiscontinuity: discontinuedTrackingIDs.contains(trackingID)
        ) else { return .unavailable }

        var observedIncompleteMetadata = false

        if let binding = bindings[trackingID], binding.isContinuous {
            switch Self.inspect(
                windowID: binding.windowID,
                anchor: anchor,
                expectedProcessID: binding.processID,
                role: .continuousIdentity,
                lookup: lookup
            ) {
            case .found(let inspected):
                return .frame(inspected.frame)
            case .missing:
                break
            case .incomplete:
                // The live process/window/app continuity tuple outranks the saved title. If its
                // targeted record is partial, use the cached complete list to recover this exact
                // ID/PID. Never let another title-based candidate override unresolved identity.
                switch Self.exactIdentityFromAllWindows(
                    windowID: binding.windowID,
                    expectedProcessID: binding.processID,
                    anchor: anchor,
                    role: .continuousIdentity,
                    lookup: lookup
                ) {
                case .found(let inspected):
                    return .frame(inspected.frame)
                case .missing, .incomplete, .mismatch:
                    // The targeted snapshot still contained this binding. Cross-snapshot absence
                    // or disagreement cannot justify moving the mask to another identity.
                    return .uncertain
                }
            case .mismatch(let mismatch):
                return unavailable(after: mismatch, trackingID: trackingID)
            }
        }

        switch Self.inspect(
            windowID: anchor.windowID,
            anchor: anchor,
            expectedProcessID: anchor.processID,
            role: .savedAnchor,
            lookup: lookup
        ) {
        case .found(let inspected):
            bindings[trackingID] = Self.binding(from: inspected)
            return .frame(inspected.frame)
        case .missing:
            break
        case .incomplete:
            observedIncompleteMetadata = true
        case .mismatch(let mismatch):
            // An exact saved ID that exists but fails identity/title evidence blocks title-based
            // rebinding to a different window for this refresh.
            return unavailable(after: mismatch, trackingID: trackingID)
        }

        // A rejected continuous binding may refer to an older rebind and cannot resolve partial
        // metadata for the saved anchor. Keep the anchor uncertain unless the all-window snapshot
        // independently provides the exact saved ID and PID.
        if observedIncompleteMetadata {
            guard let anchorProcessID = anchor.processID else { return .uncertain }
            switch Self.exactIdentityFromAllWindows(
                windowID: anchor.windowID,
                expectedProcessID: anchorProcessID,
                anchor: anchor,
                role: .savedAnchor,
                lookup: lookup
            ) {
            case .found(let exactAnchor):
                bindings[trackingID] = Self.binding(from: exactAnchor)
                return .frame(exactAnchor.frame)
            case .missing, .incomplete:
                return .uncertain
            case .mismatch(let mismatch):
                return unavailable(after: mismatch, trackingID: trackingID)
            }
        }

        let rebindResult = Self.unambiguousRebind(anchor: anchor, lookup: lookup)
        switch rebindResult {
        case .found(let replacement):
            bindings[trackingID] = Self.binding(from: replacement)
            return .frame(replacement.frame)
        case .uncertain:
            // Preserve a continuous binding across a failed metadata query. A later complete
            // snapshot can still confirm the same identity without forcing a reconnect.
            return .uncertain
        case .unavailable:
            // A zero/ambiguous title candidate set is unavailable now but retried because a
            // legitimate source may be opened later.
            return .unavailable
        }
    }

    private func unavailable(
        after mismatch: WindowTrackingMismatchKind,
        trackingID: UUID
    ) -> TrackedWindowResolution {
        if WindowTrackingContinuityPolicy.requiresExplicitRebind(after: mismatch) {
            markDiscontinued(trackingID: trackingID)
        }
        return .unavailable
    }

    private func markDiscontinued(trackingID: UUID) {
        discontinuedTrackingIDs.insert(trackingID)
        if var binding = bindings[trackingID] {
            binding.isContinuous = false
            bindings[trackingID] = binding
        }
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
        role: WindowTrackingInspectionRole,
        lookup: RefreshLookup
    ) -> InspectionResult {
        let info: [String: Any]
        switch lookup.information(for: windowID) {
        case .found(let found):
            info = found
        case .absent:
            return .missing
        case .uncertain:
            return .incomplete
        }
        return inspectInformation(
            from: info,
            anchor: anchor,
            expectedProcessID: expectedProcessID,
            role: role
        )
    }

    private static func inspectInformation(
        from info: [String: Any],
        anchor: WindowAnchor,
        expectedProcessID: pid_t?,
        role: WindowTrackingInspectionRole
    ) -> InspectionResult {
        guard
            let idNumber = info[kCGWindowNumber as String] as? NSNumber,
            let ownerPIDNumber = info[kCGWindowOwnerPID as String] as? NSNumber,
            let layerNumber = info[kCGWindowLayer as String] as? NSNumber,
            let quartzRect = bounds(from: info)
        else { return .incomplete }
        guard layerNumber.intValue == 0 else { return .mismatch(.identity) }
        guard [quartzRect.minX, quartzRect.minY, quartzRect.width, quartzRect.height]
            .allSatisfy(\.isFinite),
              quartzRect.width >= 1,
              quartzRect.height >= 1 else { return .incomplete }
        if !role.allowsSmallGeometry,
           (quartzRect.width < 80 || quartzRect.height < 60) {
            return .mismatch(.identity)
        }

        let processID = pid_t(ownerPIDNumber.int32Value)
        guard processID != 0 else { return .incomplete }
        if let expectedProcessID, expectedProcessID != processID {
            return .mismatch(.identity)
        }

        let application = NSRunningApplication(processIdentifier: processID)
        let bundleIdentifier = application?.bundleIdentifier ?? ""
        let applicationName = info[kCGWindowOwnerName as String] as? String
            ?? application?.localizedName
            ?? ""
        if !anchor.bundleIdentifier.isEmpty {
            guard !bundleIdentifier.isEmpty else { return .incomplete }
            guard bundleIdentifier == anchor.bundleIdentifier else {
                return .mismatch(.identity)
            }
        } else if !anchor.applicationName.isEmpty {
            guard !applicationName.isEmpty else { return .incomplete }
            guard applicationName == anchor.applicationName else {
                return .mismatch(.identity)
            }
        } else {
            return .incomplete
        }

        let title: String
        if let observedTitle = info[kCGWindowName as String] as? String {
            title = observedTitle
        } else if role.requiresStoredTitleMatch, !anchor.windowTitle.isEmpty {
            return .incomplete
        } else {
            title = ""
        }
        if role.requiresStoredTitleMatch,
           !anchor.windowTitle.isEmpty,
           title != anchor.windowTitle {
            return .mismatch(.savedTitle)
        }

        // Missing visibility metadata is uncertainty, not proof that a window is visible.
        guard let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool else {
            return .incomplete
        }
        return .found(InspectedWindow(
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
        ))
    }

    private static func unambiguousRebind(
        anchor: WindowAnchor,
        lookup: RefreshLookup
    ) -> RebindResult {
        guard let list = lookup.allWindows() else { return .uncertain }

        let matches = list.compactMap { info -> InspectedWindow? in
            guard case .found(let candidate) = inspectInformation(
                from: info,
                anchor: anchor,
                expectedProcessID: nil,
                role: .automaticRebindCandidate
            ) else { return nil }
            // Rebinding to a hidden/off-Space window is not verifiable enough for automatic
            // placement. The user can bring it forward and BlurFollow will retry.
            return candidate.frame.isOnScreen ? candidate : nil
        }

        // Geometry is never an identity proof. Multiple same-app/title windows require an explicit
        // user selection rather than an automatic rebind.
        guard matches.count == 1 else { return .unavailable }
        return .found(matches[0])
    }

    /// Recovers a targeted lookup whose record was partial from the complete list without running
    /// generic same-title rebinding. Other candidates do not affect this exact ID/PID lookup, and
    /// exact identity remains valid even after the selected window shrinks below picker heuristics.
    private static func exactIdentityFromAllWindows(
        windowID: CGWindowID,
        expectedProcessID: pid_t,
        anchor: WindowAnchor,
        role: WindowTrackingInspectionRole,
        lookup: RefreshLookup
    ) -> InspectionResult {
        guard windowID != kCGNullWindowID, expectedProcessID != 0 else {
            return .incomplete
        }
        guard let list = lookup.allWindows() else { return .incomplete }

        let exactDescriptions = list.filter { information in
            guard let number = information[kCGWindowNumber as String] as? NSNumber else {
                return false
            }
            return CGWindowID(number.uint32Value) == windowID
        }
        guard !exactDescriptions.isEmpty else { return .missing }
        guard exactDescriptions.count == 1 else { return .incomplete }

        let inspected = inspectInformation(
            from: exactDescriptions[0],
            anchor: anchor,
            expectedProcessID: expectedProcessID,
            role: role
        )
        guard case .found(let candidate) = inspected else { return inspected }
        return WindowTrackingExactIdentityPolicy.matches(
            anchorWindowID: windowID,
            anchorProcessID: expectedProcessID,
            candidate: candidate.frame
        ) ? inspected : .mismatch(.identity)
    }

    private static func descriptions(
        for windowIDs: Set<CGWindowID>
    ) -> [[String: Any]]? {
        let sortedIDs = windowIDs.filter { $0 != kCGNullWindowID }.sorted()
        guard !sortedIDs.isEmpty else { return [] }

        // Quartz represents a CFArray of CGWindowID values as unretained pointer-sized integers.
        // Bridging `[NSNumber]` to CFArray looks natural in Swift but is not the API's input shape.
        var rawWindowIDs: [UnsafeRawPointer?] = sortedIDs.map {
            UnsafeRawPointer(bitPattern: UInt($0))
        }
        let windowArray: CFArray = rawWindowIDs.withUnsafeMutableBufferPointer { values in
            CFArrayCreate(kCFAllocatorDefault, values.baseAddress, values.count, nil)
        }
        return CGWindowListCreateDescriptionFromArray(windowArray) as? [[String: Any]]
    }

    private static func bounds(from info: [String: Any]) -> CGRect? {
        guard let dictionary = info[kCGWindowBounds as String] as? NSDictionary else { return nil }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }
}
