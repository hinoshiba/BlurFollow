import AppKit
import Combine
import CoreMedia
import CoreVideo
import CryptoKit
import ImageIO
import ScreenCaptureKit
import Vision

enum TextFollowRuntimeState: String, Equatable, Sendable {
    case disabled
    case reconnectRequired
    case connecting
    case scanning
    case following
    case noMatches
    case sourceUnavailable
    case failed
}

enum TextFollowWindowAvailability: Equatable, Sendable {
    case visible
    case confirmedUnavailable
}

enum TextFollowWindowRecoveryPolicy {
    /// An incomplete WindowServer lookup is not a persistent availability transition. It may use
    /// the last trusted frame unless a prior complete lookup already proved the source unavailable.
    static func allowsFallbackDuringUncertainty(
        after availability: TextFollowWindowAvailability?
    ) -> Bool {
        availability != .confirmedUnavailable
    }

    /// Only a positively unavailable source becoming visible needs a new capture baseline. A
    /// transient metadata gap must not restart ScreenCaptureKit or invalidate in-flight OCR.
    static func shouldRequestFreshFrame(
        whenVisibleAfter availability: TextFollowWindowAvailability?
    ) -> Bool {
        availability == .confirmedUnavailable
    }
}

enum TextFollowDesktopPlacementPolicy {
    static func usesFullSafetyCover(
        state: TextFollowRuntimeState,
        completedMatches: [UnitRect],
        safetyCoverEnabled: Bool
    ) -> Bool {
        guard safetyCoverEnabled else { return false }
        switch state {
        case .connecting, .scanning, .sourceUnavailable, .failed, .reconnectRequired:
            return true
        case .following:
            // A completed state without geometry is torn; cover instead of disappearing.
            return completedMatches.isEmpty
        case .noMatches:
            // OCR returning zero matches cannot prove that the protected text is absent. Strict
            // safety mode therefore stays fail-closed even for a coherent completed empty scan.
            return true
        case .disabled:
            return false
        }
    }

    static func rects(
        state: TextFollowRuntimeState,
        completedMatches: [UnitRect],
        safetyCoverEnabled: Bool
    ) -> [UnitRect] {
        usesFullSafetyCover(
            state: state,
            completedMatches: completedMatches,
            safetyCoverEnabled: safetyCoverEnabled
        ) ? [.full] : completedMatches
    }
}

enum TextFollowProvisionalGeometryPolicy {
    /// A superseded result cannot prove absence in newer pixels. Keep every completed placement
    /// and conservatively add provisional placements until a current frame completes. Replacing a
    /// ten-match completed frame with one intermediate-scroll match creates avoidable disclosure
    /// in relaxed mode; temporary over-masking is the safer tradeoff.
    static func resolve(
        retainedRects: [UnitRect],
        provisionalRects: [UnitRect]
    ) -> [UnitRect] {
        var resolved = retainedRects
        resolved.reserveCapacity(retainedRects.count + provisionalRects.count)
        for rect in provisionalRects where !resolved.contains(rect) {
            resolved.append(rect)
        }
        return resolved
    }
}

struct TextFollowDesktopPanelPlacement: Equatable {
    let windowFrame: CGRect
    let normalizedRects: [UnitRect]
    let usesSafetyCover: Bool

    /// Resolves both the normal and temporary-loss desktop paths. A WindowServer lookup can be
    /// inconclusive for one refresh even while the selected window is still visible, so callers
    /// supply the last trusted (or picker-time) frame instead of dropping completed placements.
    static func resolve(
        state: TextFollowRuntimeState,
        completedMatches: [UnitRect],
        safetyCoverEnabled: Bool,
        windowResolution: TrackedWindowResolution,
        fallbackWindowFrame: CGRect?,
        allowsUncertainFallback: Bool = true
    ) -> TextFollowDesktopPanelPlacement? {
        let windowFrame: CGRect?
        switch windowResolution {
        case .frame(let frame):
            windowFrame = frame.appKitFrame
        case .uncertain:
            windowFrame = allowsUncertainFallback ? fallbackWindowFrame : nil
        case .unavailable:
            // A positively unavailable/rebound source must not leave a cover over unrelated pixels.
            windowFrame = nil
        }
        guard let windowFrame else { return nil }
        let normalizedRects = TextFollowDesktopPlacementPolicy.rects(
            state: state,
            completedMatches: completedMatches,
            safetyCoverEnabled: safetyCoverEnabled
        )
        guard !normalizedRects.isEmpty else { return nil }
        return TextFollowDesktopPanelPlacement(
            windowFrame: windowFrame,
            normalizedRects: normalizedRects,
            usesSafetyCover: TextFollowDesktopPlacementPolicy.usesFullSafetyCover(
                state: state,
                completedMatches: completedMatches,
                safetyCoverEnabled: safetyCoverEnabled
            )
        )
    }
}

struct TextFollowWindowIdentity: Hashable, Sendable {
    enum ApplicationIdentity: Hashable, Sendable {
        case bundleIdentifier(String)
        case applicationName(String)
    }

    let windowID: CGWindowID
    let processID: pid_t
    let applicationIdentity: ApplicationIdentity
    let bundleIdentifier: String
    let applicationName: String

    init?(
        windowID: CGWindowID,
        processID: pid_t,
        bundleIdentifier: String,
        applicationName: String
    ) {
        guard windowID != kCGNullWindowID, processID != 0 else { return nil }
        let applicationIdentity: ApplicationIdentity
        if !bundleIdentifier.isEmpty {
            applicationIdentity = .bundleIdentifier(bundleIdentifier)
        } else if !applicationName.isEmpty {
            applicationIdentity = .applicationName(applicationName)
        } else {
            return nil
        }
        self.windowID = windowID
        self.processID = processID
        self.applicationIdentity = applicationIdentity
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
    }

    init?(candidate: WindowCandidate) {
        self.init(
            windowID: candidate.id,
            processID: candidate.processID,
            bundleIdentifier: candidate.bundleIdentifier,
            applicationName: candidate.applicationName
        )
    }

    init?(anchor: WindowAnchor) {
        guard let processID = anchor.processID else { return nil }
        self.init(
            windowID: anchor.windowID,
            processID: processID,
            bundleIdentifier: anchor.bundleIdentifier,
            applicationName: anchor.applicationName
        )
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.windowID == rhs.windowID
            && lhs.processID == rhs.processID
            && lhs.applicationIdentity == rhs.applicationIdentity
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(windowID)
        hasher.combine(processID)
        hasher.combine(applicationIdentity)
    }

    func representsSameWindow(as other: Self) -> Bool {
        windowID == other.windowID
            && processID == other.processID
            && WindowApplicationIdentityMatcher.compare(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                toBundleIdentifier: other.bundleIdentifier,
                applicationName: other.applicationName
            ) == .same
    }

    func representsSameWindow(as anchor: WindowAnchor) -> Bool {
        guard let anchorProcessID = anchor.processID else { return false }
        return windowID == anchor.windowID
            && processID == anchorProcessID
            && WindowApplicationIdentityMatcher.compare(
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                toBundleIdentifier: anchor.bundleIdentifier,
                applicationName: anchor.applicationName
            ) == .same
    }
}

struct TextFollowSharePreviewRuntime: Equatable, Sendable {
    let identity: TextFollowWindowIdentity
    let state: TextFollowRuntimeState
    let normalizedRects: [UnitRect]
    /// WindowServer mach absolute time for the frame that produced `normalizedRects`.
    let completedFrameTime: UInt64?

    init(
        identity: TextFollowWindowIdentity,
        state: TextFollowRuntimeState,
        normalizedRects: [UnitRect],
        completedFrameTime: UInt64? = nil
    ) {
        self.identity = identity
        self.state = state
        self.normalizedRects = normalizedRects
        self.completedFrameTime = completedFrameTime
    }
}

struct TextFollowSharePreviewSnapshot: Equatable, Sendable {
    let regions: [MaskRegion]
    let requiresFullCover: Bool
    let relevantRuleCount: Int
    /// The oldest completed OCR frame among all relevant rules. Share Preview compares this with
    /// its own stream's damage time before it trusts the dynamic rectangles.
    let minimumCompletedFrameTime: UInt64?
    /// The newest completed OCR frame. Share Preview advances its own stream at least this far
    /// before rebasing new geometry onto a cached static source sample.
    let maximumCompletedFrameTime: UInt64?
}

enum TextFollowSharePreviewResolver {
    static func resolve(
        source: TextFollowWindowIdentity,
        masksEnabled: Bool,
        safetyCoverEnabled: Bool = false,
        rules: [TextFollowRule],
        runtimes: [UUID: TextFollowSharePreviewRuntime]
    ) -> TextFollowSharePreviewSnapshot {
        var regions: [MaskRegion] = []
        var requiresFullCover = false
        var relevantRuleCount = 0
        var completedFrameTimes: [UInt64] = []

        for rule in rules.sorted(by: ruleOrder) where rule.isEnabled {
            switch relevance(
                of: rule.windowAnchor,
                to: source,
                runtime: runtimes[rule.id]
            ) {
            case .unrelated:
                continue
            case .staleCandidate:
                // A saved rule can outlive its process-scoped PID and CGWindowID. Do not trust its
                // old coordinates, but also do not silently omit a plausible same-window rule.
                relevantRuleCount += 1
                requiresFullCover = true
                continue
            case .exact:
                break
            }
            relevantRuleCount += 1

            guard masksEnabled,
                  let runtime = runtimes[rule.id],
                  runtime.identity.representsSameWindow(as: source) else {
                requiresFullCover = true
                continue
            }

            switch runtime.state {
            case .following:
                // `following` is only valid with at least one placement. Treat an inconsistent
                // state/match pair as an in-flight update and keep the preview covered.
                guard !runtime.normalizedRects.isEmpty else {
                    requiresFullCover = true
                    continue
                }
            case .noMatches:
                // Stale placements paired with `noMatches` indicate a torn snapshot and must not
                // be presented. Even a coherent zero result remains covered in strict safety
                // mode because OCR absence is not proof that the protected text is absent.
                guard runtime.normalizedRects.isEmpty else {
                    requiresFullCover = true
                    continue
                }
                if safetyCoverEnabled {
                    requiresFullCover = true
                    continue
                }
            case .disabled, .reconnectRequired, .connecting, .scanning,
                 .sourceUnavailable, .failed:
                requiresFullCover = true
                continue
            }
            guard let completedFrameTime = runtime.completedFrameTime else {
                // Cross-stream ordering cannot be established without WindowServer's display time.
                requiresFullCover = true
                continue
            }
            completedFrameTimes.append(completedFrameTime)

            for normalizedRect in runtime.normalizedRects {
                regions.append(MaskRegion(
                    id: rule.id,
                    name: rule.name,
                    mode: .window,
                    normalizedRect: normalizedRect,
                    windowAnchor: rule.windowAnchor,
                    style: .mosaic,
                    strength: rule.strength,
                    granularity: rule.granularity,
                    tint: rule.tint,
                    borderEnabled: rule.borderEnabled,
                    cornerRadius: rule.cornerRadius,
                    isEnabled: true,
                    createdAt: rule.createdAt
                ))
            }
        }

        return TextFollowSharePreviewSnapshot(
            regions: regions,
            requiresFullCover: requiresFullCover,
            relevantRuleCount: relevantRuleCount,
            minimumCompletedFrameTime: !requiresFullCover
                && completedFrameTimes.count == relevantRuleCount
                ? completedFrameTimes.min()
                : nil,
            maximumCompletedFrameTime: !requiresFullCover
                && completedFrameTimes.count == relevantRuleCount
                ? completedFrameTimes.max()
                : nil
        )
    }

    private static func ruleOrder(_ lhs: TextFollowRule, _ rhs: TextFollowRule) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }

    private enum Relevance {
        case unrelated
        case staleCandidate
        case exact
    }

    private static func relevance(
        of anchor: WindowAnchor,
        to source: TextFollowWindowIdentity,
        runtime: TextFollowSharePreviewRuntime?
    ) -> Relevance {
        if source.representsSameWindow(as: anchor) { return .exact }

        let savedApplicationComparison = WindowApplicationIdentityMatcher.compare(
            bundleIdentifier: anchor.bundleIdentifier,
            applicationName: anchor.applicationName,
            toBundleIdentifier: source.bundleIdentifier,
            applicationName: source.applicationName
        )
        guard savedApplicationComparison != .different else { return .unrelated }

        // A live picker-authorized connection to a different process-scoped window proves that
        // this rule belongs elsewhere. Without that authorization boundary, a saved title is not
        // sufficient to dismiss the rule: browser/document titles commonly change after a page
        // transition or relaunch, so doing so could silently omit a still-relevant rule.
        if let runtime {
            let runtimeApplicationComparison = WindowApplicationIdentityMatcher.compare(
                bundleIdentifier: runtime.identity.bundleIdentifier,
                applicationName: runtime.identity.applicationName,
                toBundleIdentifier: source.bundleIdentifier,
                applicationName: source.applicationName
            )
            if runtime.identity.windowID != source.windowID
                || runtime.identity.processID != source.processID
                || runtimeApplicationComparison == .different {
                return .unrelated
            }
            guard runtimeApplicationComparison == .same else { return .staleCandidate }
        }
        return .staleCandidate
    }
}

/// Runs picker-authorized, on-device text recognition independently from saved Window Pins.
///
/// Saved rules intentionally do not imply capture authorization. A rule loaded after launch stays
/// in `reconnectRequired` until the user selects its source again and `connect(_:to:)` supplies the
/// picker-created content filter for this process lifetime.
@MainActor
final class TextFollowCoordinator: ObservableObject {
    @Published private(set) var states: [UUID: TextFollowRuntimeState] = [:]
    @Published private(set) var matchedCounts: [UUID: Int] = [:]
    /// Current OCR placements in source-window normalized coordinates, grouped by saved rule ID.
    @Published private(set) var normalizedMatches: [UUID: [UnitRect]] = [:]
    /// Invalidates Share Preview's render snapshot for match, readiness, connection, or appearance
    /// changes. Pixels from an older revision are cleared before the next frame is accepted.
    @Published private(set) var sharePreviewRevision: UInt64 = 0

    private struct CaptureKey: Hashable {
        let identity: TextFollowWindowIdentity

        var windowID: CGWindowID { identity.windowID }
        var processID: pid_t { identity.processID }

        init?(candidate: WindowCandidate) {
            guard let identity = TextFollowWindowIdentity(candidate: candidate) else { return nil }
            self.identity = identity
        }

        func matches(_ anchor: WindowAnchor) -> Bool {
            TextFollowWindowIdentity(anchor: anchor) == identity
        }
    }

    private let store: MaskStore
    private let tracker: WindowTracker
    private var sessions: [CaptureKey: TextFollowCaptureSession] = [:]
    private var connections: [UUID: CaptureKey] = [:]
    /// Each saved rule owns at most one WindowServer overlay surface. Its match views are pooled
    /// only up to the current OCR occurrence count inside the full source-window panel.
    private var panels: [UUID: TextFollowOverlayPanel] = [:]
    private var detectionSignatures: [UUID: TextFollowDetectionSignature] = [:]
    private var windowAvailability: [UUID: TextFollowWindowAvailability] = [:]
    private var lastTrackedWindowFrames: [UUID: CGRect] = [:]
    private var acceptedEvents: [UUID: TextFollowEventCursor] = [:]
    /// OCR completions have a separate cursor because a useful result can finish after a newer
    /// damage/scanning event. Such a result is provisional for desktop unsafe mode, but it must
    /// still never overwrite a newer completed OCR result.
    private var acceptedCompletions: [UUID: TextFollowCompletionCursor] = [:]
    private var completedFrameTimes: [UUID: UInt64] = [:]
    private var timer: Timer?
    private var isStarted = false
    private var currentRules: [TextFollowRule]
    private var currentMasksEnabled: Bool
    private var currentSafetyCoverEnabled: Bool
    private var sharePreviewBatchDepth = 0
    private var sharePreviewRevisionPending = false
    private var cancellables: Set<AnyCancellable> = []

    init(store: MaskStore, tracker: WindowTracker) {
        self.store = store
        self.tracker = tracker
        currentRules = store.textRules
        currentMasksEnabled = store.masksEnabled
        currentSafetyCoverEnabled = store.textFollowSafetyCoverEnabled

        store.$textRules
            .combineLatest(store.$masksEnabled)
            .sink { [weak self] rules, masksEnabled in
                self?.synchronize(rules: rules, masksEnabled: masksEnabled)
            }
            .store(in: &cancellables)

        store.$textFollowSafetyCoverEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                // @Published emits during willSet, so retain the emitted value instead of reading
                // the store property from refreshPanels(). Share Preview remains fail-closed.
                self.currentSafetyCoverEnabled = enabled
                self.refreshPanels()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in self?.refreshPanels() }
            .store(in: &cancellables)
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPanels() }
        }
        timer.tolerance = 1.0 / 240.0
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        synchronize(rules: store.textRules, masksEnabled: store.masksEnabled)
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false
        timer?.invalidate()
        timer = nil
        synchronize(rules: store.textRules, masksEnabled: store.masksEnabled)
    }

    /// Connects one saved rule to the exact picker-authorized window for this process lifetime.
    /// Rules targeting the same selected window share one stream and one Vision request per frame.
    func connect(_ selection: PickedWindow, to ruleID: UUID) {
        guard var rule = store.textRules.first(where: { $0.id == ruleID }) else { return }
        guard let key = CaptureKey(candidate: selection.candidate) else {
            setState(.failed, for: ruleID)
            clearMatches(for: ruleID)
            return
        }

        let previousKey = connections[ruleID]
        rule.windowAnchor = selection.candidate.anchor
        tracker.bind(selection.candidate, to: ruleID)
        connections[ruleID] = key
        windowAvailability[ruleID] = nil
        lastTrackedWindowFrames[ruleID] = selection.candidate.appKitFrame
        setState(.connecting, for: ruleID)
        clearMatches(for: ruleID)

        if rule != store.textRules.first(where: { $0.id == ruleID }) {
            store.updateTextRule(rule)
        }

        if let previousKey, previousKey != key {
            removeUnusedSession(for: previousKey)
        }

        // An explicit picker selection is the newest authorization boundary. Replace even a
        // same-window session so reconnect never keeps relying on an older filter.
        if let replaced = sessions[key] {
            acceptedEvents[replaced.id] = nil
            acceptedCompletions[replaced.id] = nil
            replaced.invalidate()
        }
        sessions[key] = makeSession(selection: selection)
        synchronize(rules: store.textRules, masksEnabled: store.masksEnabled)
    }

    /// Releases this rule's process-lifetime capture connection without deleting the saved rule.
    /// Store deletion also performs this cleanup synchronously through the `textRules` publisher.
    func disconnect(ruleID: UUID) {
        let oldKey = connections.removeValue(forKey: ruleID)
        tracker.unbind(regionID: ruleID)
        detectionSignatures[ruleID] = nil
        windowAvailability[ruleID] = nil
        lastTrackedWindowFrames[ruleID] = nil
        if store.textRules.contains(where: { $0.id == ruleID }) {
            setState(.reconnectRequired, for: ruleID)
        } else {
            completedFrameTimes[ruleID] = nil
            states[ruleID] = nil
            bumpSharePreviewRevision()
        }
        clearMatches(for: ruleID)
        if let oldKey { removeUnusedSession(for: oldKey) }
        synchronize(rules: store.textRules, masksEnabled: store.masksEnabled)
    }

    func state(for ruleID: UUID) -> TextFollowRuntimeState {
        states[ruleID] ?? .reconnectRequired
    }

    func matchedCount(for ruleID: UUID) -> Int {
        matchedCounts[ruleID] ?? 0
    }

    func normalizedMatches(for ruleID: UUID) -> [UnitRect] {
        normalizedMatches[ruleID] ?? []
    }

    /// Restarts an already picker-authorized Text Follow stream after Share Preview observes its
    /// first source frame. A static window then receives a fresh comparable OCR display time.
    func requestFreshFrame(for source: TextFollowWindowIdentity) {
        let matchingConnections = connections.filter {
            $0.value.identity.representsSameWindow(as: source)
        }
        guard !matchingConnections.isEmpty else { return }

        for ruleID in matchingConnections.keys {
            setState(.scanning, for: ruleID)
        }
        refreshPanels()

        for key in Set(matchingConnections.values) {
            sessions[key]?.requestFreshFrame()
        }
    }

    /// Produces an atomic, fail-closed Share Preview input for one picker-authorized source.
    /// A recycled window ID cannot qualify without the same process and application identity.
    func sharePreviewSnapshot(
        for source: TextFollowWindowIdentity
    ) -> TextFollowSharePreviewSnapshot {
        let runtimes = connections.reduce(into: [UUID: TextFollowSharePreviewRuntime]()) {
            result, connection in
            let (ruleID, key) = connection
            result[ruleID] = TextFollowSharePreviewRuntime(
                identity: key.identity,
                state: state(for: ruleID),
                normalizedRects: normalizedMatches[ruleID] ?? [],
                completedFrameTime: completedFrameTimes[ruleID]
            )
        }
        return TextFollowSharePreviewResolver.resolve(
            source: source,
            masksEnabled: currentMasksEnabled && isStarted,
            safetyCoverEnabled: currentSafetyCoverEnabled,
            rules: currentRules,
            runtimes: runtimes
        )
    }

    private func makeSession(selection: PickedWindow) -> TextFollowCaptureSession {
        TextFollowCaptureSession(selection: selection) { [weak self] event in
            Task { @MainActor [weak self] in self?.receive(event) }
        }
    }

    private func synchronize(rules: [TextFollowRule], masksEnabled: Bool) {
        // Combine's @Published values arrive during willSet. Retain the emitted values before
        // invalidating Share Preview so appearance-only edits cannot render with stale store data.
        currentRules = rules
        currentMasksEnabled = masksEnabled
        bumpSharePreviewRevision()

        let rulesByID = Dictionary(uniqueKeysWithValues: rules.map { ($0.id, $0) })
        let savedIDs = Set(rulesByID.keys)

        for ruleID in Set(states.keys)
            .union(connections.keys)
            .union(completedFrameTimes.keys) where !savedIDs.contains(ruleID) {
            let oldKey = connections.removeValue(forKey: ruleID)
            tracker.unbind(regionID: ruleID)
            detectionSignatures[ruleID] = nil
            windowAvailability[ruleID] = nil
            lastTrackedWindowFrames[ruleID] = nil
            completedFrameTimes[ruleID] = nil
            states[ruleID] = nil
            matchedCounts[ruleID] = nil
            normalizedMatches[ruleID] = nil
            closePanels(for: ruleID)
            if let oldKey { removeUnusedSession(for: oldKey) }
        }

        for rule in rules {
            guard rule.isEnabled else {
                setState(.disabled, for: rule.id)
                clearMatches(for: rule.id)
                continue
            }

            guard masksEnabled, isStarted else {
                setState(.disabled, for: rule.id)
                clearMatches(for: rule.id)
                continue
            }

            guard let key = connections[rule.id], key.matches(rule.windowAnchor) else {
                if let oldKey = connections.removeValue(forKey: rule.id) {
                    removeUnusedSession(for: oldKey)
                }
                tracker.unbind(regionID: rule.id)
                lastTrackedWindowFrames[rule.id] = nil
                setState(.reconnectRequired, for: rule.id)
                clearMatches(for: rule.id)
                continue
            }

            let signature = TextFollowDetectionSignature(rule: rule)
            if detectionSignatures[rule.id] != signature {
                detectionSignatures[rule.id] = signature
                setState(.scanning, for: rule.id)
                clearMatches(for: rule.id)
            }
        }

        let activeByKey = Dictionary(grouping: rules.filter { rule in
            rule.isEnabled && masksEnabled && isStarted && connections[rule.id] != nil
        }) { connections[$0.id]! }

        for (key, session) in sessions {
            let specifications = (activeByKey[key] ?? []).compactMap { rule -> TextFollowProcessingSpecification? in
                do { return try TextFollowProcessingSpecification(rule: rule) }
                catch {
                    setState(.failed, for: rule.id)
                    clearMatches(for: rule.id)
                    return nil
                }
            }
            session.setActive(
                specifications: specifications,
                shouldCapture: !specifications.isEmpty
            )
        }

        if !masksEnabled || !isStarted { hideAllPanels() }
        refreshPanels()
    }

    private func receive(_ event: TextFollowCaptureEvent) {
        guard let session = sessions.values.first(where: { $0.id == event.sessionID }),
              session.currentGeneration == event.generation else { return }

        // Keep supersession validation and the MainActor model commit inside the session's pixel-
        // assessment gate. A newly delivered dirty frame cannot invalidate the mailbox between the
        // check and publishing completedFrameTime/following state. Panel refresh stays outside the
        // gate because it can restart a recovered session.
        let shouldRefresh = session.withFramePublicationGate(sequence: event.sequence) {
            superseded in
            receive(event, superseded: superseded)
        }
        if shouldRefresh { refreshPanels() }
    }

    private func receive(
        _ event: TextFollowCaptureEvent,
        superseded: Bool
    ) -> Bool {
        switch event.payload {
        case .provisionalMatches(let matches):
            return receiveProvisional(matches, event: event)
        case .matches(let matches) where superseded:
            // Pixels can change after the recognition worker publishes but before MainActor
            // receives the event. Downgrade here as well so stale geometry never becomes a
            // Share Preview completion or a desktop following state.
            return receiveProvisional(matches, event: event)
        default:
            break
        }

        var cursor = acceptedEvents[event.sessionID] ?? TextFollowEventCursor()
        let phase: TextFollowEventPhase = switch event.payload {
        case .scanning, .failClosed: .scanning
        case .matches, .provisionalMatches, .cleared: .result
        }
        if phase == .result, superseded { return false }
        guard cursor.accepts(
            generation: event.generation,
            sequence: event.sequence,
            phase: phase
        ) else { return false }

        var completionCursor = acceptedCompletions[event.sessionID]
            ?? TextFollowCompletionCursor()
        if phase == .result {
            guard completionCursor.accepts(
                generation: event.generation,
                sequence: event.sequence
            ) else { return false }
        }
        acceptedEvents[event.sessionID] = cursor
        if phase == .result { acceptedCompletions[event.sessionID] = completionCursor }

        switch event.payload {
        case .scanning(let ruleIDs):
            performSharePreviewRevisionBatch {
                for ruleID in ruleIDs where connections[ruleID] != nil {
                    setState(.scanning, for: ruleID)
                }
            }
            // Old per-text placements no longer describe the changed pixels. Desktop panels use
            // a temporary full-window Mosaic while Share Preview independently fails closed.

        case .failClosed(let ruleIDs):
            performSharePreviewRevisionBatch {
                for ruleID in ruleIDs where connections[ruleID] != nil {
                    setState(.failed, for: ruleID)
                }
            }
            // A result for this exact sequence remains eligible, allowing immediate recovery if the
            // final churn frame is already being recognized when the deadline is crossed.

        case .matches(let matches):
            let sessionRuleIDs = activeRuleIDs(forSessionID: event.sessionID)
            // Publish frame time, every rule's geometry, and all completed states as one coherent
            // MainActor snapshot. Share Preview must never observe new time with old rectangles.
            performSharePreviewRevisionBatch {
                for ruleID in sessionRuleIDs {
                    let rects = matches[ruleID] ?? []
                    setCompletedFrameTime(event.frameTime, for: ruleID)
                    setMatches(rects, for: ruleID)
                    setState(rects.isEmpty ? .noMatches : .following, for: ruleID)
                }
            }

        case .provisionalMatches:
            // Handled before the authoritative event cursor above.
            break

        case .cleared(let ruleIDs, let reason):
            performSharePreviewRevisionBatch {
                for ruleID in ruleIDs where connections[ruleID] != nil {
                    setState(reason == .failed ? .failed : .sourceUnavailable, for: ruleID)
                }
            }
            // Safe mode turns these states into a square-cornered full-window cover. Unsafe mode
            // deliberately keeps the last completed placements instead of dropping every mask.
        }
        return true
    }

    private func receiveProvisional(
        _ matches: [UUID: [UnitRect]],
        event: TextFollowCaptureEvent
    ) -> Bool {
        if let acceptedEvent = acceptedEvents[event.sessionID],
           acceptedEvent.generation == event.generation,
           acceptedEvent.phase == .scanning,
           acceptedEvent.sequence >= event.sequence,
           activeRuleIDs(forSessionID: event.sessionID).contains(where: {
               states[$0] == .failed
           }) {
            // A provisional result queued before the churn deadline must not revive the spinner
            // after fail-closed won the event cursor. Same/newer authoritative results remain valid.
            return false
        }
        var completionCursor = acceptedCompletions[event.sessionID]
            ?? TextFollowCompletionCursor()
        guard completionCursor.accepts(
            generation: event.generation,
            sequence: event.sequence
        ) else { return false }
        acceptedCompletions[event.sessionID] = completionCursor

        let sessionRuleIDs = activeRuleIDs(forSessionID: event.sessionID)
        performSharePreviewRevisionBatch {
            for ruleID in sessionRuleIDs {
                let rects = matches[ruleID] ?? []
                setMatches(TextFollowProvisionalGeometryPolicy.resolve(
                    retainedRects: normalizedMatches[ruleID] ?? [],
                    provisionalRects: rects
                ), for: ruleID)
                // This deliberately clears completedFrameTime. Safety mode and Share Preview stay
                // fully covered, while desktop unsafe mode can use the latest completed rectangles.
                setState(.scanning, for: ruleID)
            }
        }
        return true
    }

    private func activeRuleIDs(forSessionID sessionID: UUID) -> [UUID] {
        store.textRules.compactMap { rule -> UUID? in
            guard rule.isEnabled,
                  let key = connections[rule.id],
                  sessions[key]?.id == sessionID else { return nil }
            return rule.id
        }
    }

    private func refreshPanels() {
        guard isStarted, store.masksEnabled else {
            hideAllPanels()
            return
        }

        let enabledRules = store.textRules.filter { $0.isEnabled && connections[$0.id] != nil }
        let anchors = Dictionary(uniqueKeysWithValues: enabledRules.map { ($0.id, $0.windowAnchor) })
        let resolutions = tracker.resolutions(for: anchors)
        var desiredPanels: Set<UUID> = []
        var sessionsToRestart: Set<CaptureKey> = []

        for rule in enabledRules {
            guard let key = connections[rule.id] else { continue }
            let resolution = resolutions[rule.id] ?? .uncertain
            guard case .frame(let frame) = resolution else {
                guard resolution == .uncertain else {
                    // A complete lookup confirmed that no safe, unambiguous continuation exists.
                    // Hide the panel rather than covering unrelated content at an old location.
                    setState(.sourceUnavailable, for: rule.id)
                    windowAvailability[rule.id] = .confirmedUnavailable
                    continue
                }
                let allowsFallback = TextFollowWindowRecoveryPolicy
                    .allowsFallbackDuringUncertainty(after: windowAvailability[rule.id])
                // An incomplete batched WindowServer query is not evidence that the selected
                // window or last completed OCR result ceased to exist. Preserve the completed
                // geometry at the last trusted picker/window frame until a complete lookup decides.
                // Use a source-unavailable state only for this desktop placement: changing the
                // persisted runtime state or availability here would restart OCR when metadata
                // recovers. Confirmed loss remains sticky and cannot resurrect an old cover.
                let fallbackFrame = lastTrackedWindowFrames[rule.id]
                    ?? ScreenCoordinates.appKitRect(
                        fromQuartz: rule.windowAnchor.initialFrame.cgRect
                    )
                if let placement = TextFollowDesktopPanelPlacement.resolve(
                    state: .sourceUnavailable,
                    completedMatches: normalizedMatches[rule.id] ?? [],
                    safetyCoverEnabled: currentSafetyCoverEnabled,
                    windowResolution: .uncertain,
                    fallbackWindowFrame: fallbackFrame,
                    allowsUncertainFallback: allowsFallback
                ) {
                    presentPanel(for: rule, placement: placement, desiredPanels: &desiredPanels)
                }
                continue
            }

            guard frame.windowID == key.windowID,
                  frame.processID == key.processID else {
                // A positively observed different identity is not transient lookup uncertainty.
                // Never move an old OCR result or fallback cover onto a recycled/rebound window.
                setState(.reconnectRequired, for: rule.id)
                windowAvailability[rule.id] = .confirmedUnavailable
                clearMatches(for: rule.id)
                continue
            }

            guard frame.isOnScreen else {
                windowAvailability[rule.id] = .confirmedUnavailable
                setState(.sourceUnavailable, for: rule.id)
                // A minimized/other-Space source is explicitly not on this desktop. Retain its
                // completed geometry for recovery, but do not leave a panel over unrelated content.
                continue
            }

            if TextFollowWindowRecoveryPolicy.shouldRequestFreshFrame(
                whenVisibleAfter: windowAvailability[rule.id]
            ) {
                sessionsToRestart.insert(key)
                setState(.scanning, for: rule.id)
            }
            windowAvailability[rule.id] = .visible
            lastTrackedWindowFrames[rule.id] = frame.appKitFrame

            let runtimeState = state(for: rule.id)
            let completedMatches = normalizedMatches[rule.id] ?? []
            if let placement = TextFollowDesktopPanelPlacement.resolve(
                state: runtimeState,
                completedMatches: completedMatches,
                safetyCoverEnabled: currentSafetyCoverEnabled,
                windowResolution: .frame(frame),
                fallbackWindowFrame: nil
            ) {
                presentPanel(for: rule, placement: placement, desiredPanels: &desiredPanels)
            }
        }

        for (key, panel) in panels where !desiredPanels.contains(key) {
            panel.clearMatches()
            panel.hideIfNeeded()
        }
        for key in sessionsToRestart {
            sessions[key]?.requestFreshFrame()
        }
    }

    private func presentPanel(
        for rule: TextFollowRule,
        placement: TextFollowDesktopPanelPlacement,
        desiredPanels: inout Set<UUID>
    ) {
        desiredPanels.insert(rule.id)
        let panel = panels[rule.id] ?? {
            let panel = TextFollowOverlayPanel()
            panels[rule.id] = panel
            return panel
        }()
        panel.update(
            rule: rule,
            windowFrame: placement.windowFrame,
            normalizedRects: placement.normalizedRects,
            usesSafetyCover: placement.usesSafetyCover
        )
        panel.showIfNeeded()
    }

    private func setMatches(_ rects: [UnitRect], for ruleID: UUID) {
        let sorted = rects.sorted {
            if abs($0.y - $1.y) > 0.000_001 { return $0.y > $1.y }
            if abs($0.x - $1.x) > 0.000_001 { return $0.x < $1.x }
            if abs($0.width - $1.width) > 0.000_001 { return $0.width < $1.width }
            return $0.height < $1.height
        }
        if normalizedMatches[ruleID] != sorted {
            normalizedMatches[ruleID] = sorted
            bumpSharePreviewRevision()
        }
        if matchedCounts[ruleID] != sorted.count { matchedCounts[ruleID] = sorted.count }
    }

    private func clearMatches(for ruleID: UUID) {
        if normalizedMatches[ruleID] != [] {
            normalizedMatches[ruleID] = []
            bumpSharePreviewRevision()
        }
        if matchedCounts[ruleID] != 0 { matchedCounts[ruleID] = 0 }
        hidePanels(for: ruleID)
    }

    private func clearEveryMatch() {
        for ruleID in store.textRules.map(\.id) { clearMatches(for: ruleID) }
    }

    private func setState(_ state: TextFollowRuntimeState, for ruleID: UUID) {
        var changed = false
        if states[ruleID] != state {
            states[ruleID] = state
            changed = true
        }
        if state != .following, state != .noMatches,
           completedFrameTimes.removeValue(forKey: ruleID) != nil {
            changed = true
        }
        if changed { bumpSharePreviewRevision() }
    }

    private func setCompletedFrameTime(_ frameTime: UInt64?, for ruleID: UUID) {
        if completedFrameTimes[ruleID] != frameTime {
            completedFrameTimes[ruleID] = frameTime
            bumpSharePreviewRevision()
        }
    }

    private func bumpSharePreviewRevision() {
        if sharePreviewBatchDepth > 0 {
            sharePreviewRevisionPending = true
        } else {
            sharePreviewRevision &+= 1
        }
    }

    private func performSharePreviewRevisionBatch(_ updates: () -> Void) {
        sharePreviewBatchDepth += 1
        updates()
        sharePreviewBatchDepth -= 1
        if sharePreviewBatchDepth == 0, sharePreviewRevisionPending {
            sharePreviewRevisionPending = false
            sharePreviewRevision &+= 1
        }
    }

    private func hidePanels(for ruleID: UUID) {
        panels[ruleID]?.clearMatches()
        panels[ruleID]?.hideIfNeeded()
    }

    private func closePanels(for ruleID: UUID) {
        guard let panel = panels.removeValue(forKey: ruleID) else { return }
        panel.clearMatches()
        panel.close()
    }

    private func hideAllPanels() {
        panels.values.forEach {
            $0.clearMatches()
            $0.hideIfNeeded()
        }
    }

    private func removeUnusedSession(for key: CaptureKey) {
        guard !connections.values.contains(key), let session = sessions.removeValue(forKey: key) else {
            return
        }
        acceptedEvents[session.id] = nil
        acceptedCompletions[session.id] = nil
        session.invalidate()
    }
}

struct TextFollowRecognizedBlock: Equatable, Sendable {
    let candidates: [String]
    /// Vision-normalized coordinates in the complete output image (lower-left origin).
    let normalizedBoundingBox: CGRect
}

enum TextFollowRecognitionLanguagePolicy {
    struct Configuration: Equatable, Sendable {
        let recognitionLanguages: [String]
        let automaticallyDetectsLanguage: Bool
    }

    static let englishFirst = ["en-US", "ja-JP"]
    static let japaneseFirst = ["ja-JP", "en-US"]

    /// A literal pattern's script does not describe the whole OCR observation that contains it.
    /// For example, an English secret can appear inside a Japanese result title, and Vision's fixed
    /// English primary model can omit that complete mixed-script line. Always detect per observed
    /// block; the rules only choose which enabled language receives ordering priority.
    static func configuration(
        for rules: [(matchMode: TextMatchMode, pattern: String)],
        fallbackPrefersJapanese: Bool = Locale.preferredLanguages.first?.hasPrefix("ja") == true
    ) -> Configuration {
        var selectedLiteralScript: LiteralScript?
        var requiresFallbackLanguageOrder = rules.isEmpty

        for rule in rules {
            guard rule.matchMode != .regex else {
                requiresFallbackLanguageOrder = true
                continue
            }

            let script = literalScript(for: rule.pattern)
            guard script != .unknown else {
                requiresFallbackLanguageOrder = true
                continue
            }
            guard script != .mixed else {
                requiresFallbackLanguageOrder = true
                continue
            }
            if let existingScript = selectedLiteralScript, existingScript != script {
                requiresFallbackLanguageOrder = true
            } else {
                selectedLiteralScript = script
            }
        }

        if requiresFallbackLanguageOrder {
            return Configuration(
                recognitionLanguages: fallbackPrefersJapanese ? japaneseFirst : englishFirst,
                automaticallyDetectsLanguage: true
            )
        }

        switch selectedLiteralScript {
        case .japanese:
            return Configuration(
                recognitionLanguages: japaneseFirst,
                automaticallyDetectsLanguage: true
            )
        case .latin:
            return Configuration(
                recognitionLanguages: englishFirst,
                automaticallyDetectsLanguage: true
            )
        case .mixed, .unknown, nil:
            // All of these select the fallback order above. Keep a defensive result in case this
            // policy is extended with another script classification later.
            return Configuration(
                recognitionLanguages: fallbackPrefersJapanese ? japaneseFirst : englishFirst,
                automaticallyDetectsLanguage: true
            )
        }
    }

    private enum LiteralScript {
        case japanese
        case latin
        case mixed
        case unknown
    }

    private static func literalScript(for text: String) -> LiteralScript {
        let hasJapanese = containsJapaneseScript(text)
        let hasLatin = containsBasicLatinLetter(text)
        switch (hasJapanese, hasLatin) {
        case (true, true): return .mixed
        case (true, false): return .japanese
        case (false, true): return .latin
        case (false, false): return .unknown
        }
    }

    private static func containsBasicLatinLetter(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x41...0x5A).contains(scalar.value) || (0x61...0x7A).contains(scalar.value)
        }
    }

    private static func containsJapaneseScript(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF,   // Hiragana and Katakana
                 0x31F0...0x31FF,   // Katakana phonetic extensions
                 0x3400...0x4DBF,   // CJK unified ideographs extension A
                 0x4E00...0x9FFF,   // CJK unified ideographs
                 0xF900...0xFAFF,   // CJK compatibility ideographs
                 0xFF66...0xFF9D,   // Half-width Katakana
                 0x20000...0x2FA1F: // Supplementary CJK ideographs
                return true
            default:
                return false
            }
        }
    }
}

enum TextFollowCaptureSizePolicy {
    struct PixelSize: Equatable, Sendable {
        let width: Int
        let height: Int
    }

    /// Keep native source detail where possible while bounding each BGRA surface before Vision's
    /// working memory. A larger Vision input does not guarantee monotonic OCR recall, so this is a
    /// resource/detail ceiling rather than an accuracy claim.
    static let maximumPixelSize = PixelSize(width: 3_840, height: 2_160)

    /// One synchronous Vision call can time out without returning while its single replacement is
    /// active, and the latest-frame mailbox may retain one more surface. Keep one WindowServer slot
    /// beyond those three possible consumers so a final scroll/navigation frame can still arrive.
    /// ScreenCaptureKit documents three as the minimum queue depth and eight as the maximum.
    static let maximumRetainedSurfaceCount = 3
    static let streamQueueDepth = maximumRetainedSurfaceCount + 1

    static func outputPixelSize(
        sourceSize: CGSize,
        pointPixelScale: CGFloat
    ) -> PixelSize? {
        let values = [sourceSize.width, sourceSize.height, pointPixelScale]
        guard values.allSatisfy(\.isFinite),
              sourceSize.width > 1, sourceSize.height > 1,
              pointPixelScale > 0, pointPixelScale <= 4 else { return nil }

        let nativeWidth = sourceSize.width * pointPixelScale
        let nativeHeight = sourceSize.height * pointPixelScale
        guard nativeWidth.isFinite, nativeHeight.isFinite,
              nativeWidth > 1, nativeHeight > 1 else { return nil }
        let fit = min(
            1,
            CGFloat(maximumPixelSize.width) / nativeWidth,
            CGFloat(maximumPixelSize.height) / nativeHeight
        )

        func evenPixelCount(_ value: CGFloat) -> Int {
            let bounded = min(
                max(2, value.rounded(.down)),
                CGFloat(max(maximumPixelSize.width, maximumPixelSize.height))
            )
            let rounded = Int(bounded)
            return rounded.isMultiple(of: 2) ? rounded : rounded - 1
        }

        return PixelSize(
            width: evenPixelCount(nativeWidth * fit),
            height: evenPixelCount(nativeHeight * fit)
        )
    }

    /// `contentScale` maps original source points into the output surface's logical points.
    /// Reversing that transform lets a long-lived picker selection notice a larger window even
    /// though SCStream keeps emitting the dimensions configured when the user first connected it.
    static func originalSourceSize(
        contentRectInPoints: CGRect,
        contentScale: CGFloat
    ) -> CGSize? {
        let values = [
            contentRectInPoints.width, contentRectInPoints.height, contentScale
        ]
        guard values.allSatisfy(\.isFinite),
              contentRectInPoints.width > 1, contentRectInPoints.height > 1,
              contentScale > 0, contentScale <= 4 else { return nil }
        let size = CGSize(
            width: contentRectInPoints.width / contentScale,
            height: contentRectInPoints.height / contentScale
        )
        guard size.width.isFinite, size.height.isFinite,
              size.width > 1, size.height > 1 else { return nil }
        return size
    }

    /// Avoid configuration churn while a resize handle is moving. The first material increase is
    /// applied immediately; an in-flight update coalesces subsequent callbacks to the latest size.
    static func requiresResolutionIncrease(
        from current: PixelSize,
        to requested: PixelSize
    ) -> Bool {
        let widthThreshold = max(32, Int((Double(current.width) * 0.10).rounded(.up)))
        let heightThreshold = max(32, Int((Double(current.height) * 0.10).rounded(.up)))
        return requested.width >= current.width + widthThreshold
            || requested.height >= current.height + heightThreshold
    }

    static func matchesOutputSurface(
        width: Int,
        height: Int,
        expected: PixelSize
    ) -> Bool {
        width == expected.width && height == expected.height
    }
}

enum TextFollowCaptureSurfaceAuthorityPolicy {
    /// A callback from the old surface must never become authoritative while a larger
    /// updateConfiguration attempt (including its bounded backoff) is pending. After a successful
    /// update, only the first callback with the exact requested dimensions completes the handoff.
    static func isAuthoritative(
        actualWidth: Int,
        actualHeight: Int,
        updateTarget: TextFollowCaptureSizePolicy.PixelSize?,
        awaitedTarget: TextFollowCaptureSizePolicy.PixelSize?
    ) -> Bool {
        guard updateTarget == nil else { return false }
        guard let awaitedTarget else { return true }
        return TextFollowCaptureSizePolicy.matchesOutputSurface(
            width: actualWidth,
            height: actualHeight,
            expected: awaitedTarget
        )
    }
}

enum TextFollowFrameGeometry {
    /// A full OCR frame shares one regex budget across every block and saved rule. When the budget
    /// is exhausted, recognition fails closed instead of publishing an incomplete empty match set.
    static let frameRegexExecutionLimitNanoseconds: UInt64 = 50_000_000

    static func matchingNormalizedRects(
        blocks: [TextFollowRecognizedBlock],
        matcher: TextPatternMatcher,
        imageSize: CGSize,
        contentPixelRect: CGRect,
        paddingPixels: CGFloat
    ) -> [UnitRect] {
        matchingNormalizedRects(
            blocks: blocks,
            matcher: matcher,
            imageSize: imageSize,
            contentPixelRect: contentPixelRect,
            paddingPixels: paddingPixels,
            regexDeadlineUptimeNanoseconds: TextPatternMatcher.deadline(
                afterNanoseconds: TextPatternMatcher.defaultExecutionLimitNanoseconds
            )
        ) ?? []
    }

    /// Returns nil when regex evaluation exceeds its caller-owned deadline. A nil result must be
    /// treated as a failed scan, never as a completed frame containing no sensitive text.
    static func matchingNormalizedRects(
        blocks: [TextFollowRecognizedBlock],
        matcher: TextPatternMatcher,
        imageSize: CGSize,
        contentPixelRect: CGRect,
        paddingPixels: CGFloat,
        regexDeadlineUptimeNanoseconds: UInt64
    ) -> [UnitRect]? {
        let scalarValues = [
            imageSize.width, imageSize.height,
            contentPixelRect.minX, contentPixelRect.minY,
            contentPixelRect.width, contentPixelRect.height,
            paddingPixels
        ]
        guard scalarValues.allSatisfy(\.isFinite),
              imageSize.width > 1, imageSize.height > 1,
              contentPixelRect.width > 1, contentPixelRect.height > 1,
              paddingPixels >= 0 else { return [] }

        var acceptedPixelRects: [CGRect] = []
        for block in blocks {
            // One observation is one user-visible text block. Several matching OCR candidates or
            // several regex hits inside that candidate still produce exactly one block rectangle.
            var blockMatches = false
            for candidate in block.candidates {
                switch matcher.matchResult(
                    candidate,
                    deadlineUptimeNanoseconds: regexDeadlineUptimeNanoseconds
                ) {
                case .matched:
                    blockMatches = true
                case .notMatched:
                    continue
                case .timedOut:
                    return nil
                }
                if blockMatches { break }
            }
            guard blockMatches else { continue }
            let box = block.normalizedBoundingBox
            let values = [box.minX, box.minY, box.width, box.height]
            guard values.allSatisfy(\.isFinite), box.width > 0, box.height > 0 else { continue }

            let imageRect = CGRect(
                x: box.minX * imageSize.width,
                y: box.minY * imageSize.height,
                width: box.width * imageSize.width,
                height: box.height * imageSize.height
            )
            let expanded = imageRect.insetBy(dx: -paddingPixels, dy: -paddingPixels)
            let clipped = expanded.intersection(contentPixelRect)
            guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else { continue }

            // Vision can occasionally return the same observation twice. Only essentially
            // identical geometry is removed; separate, overlapping text blocks remain separate.
            guard !acceptedPixelRects.contains(where: { approximatelyEqual($0, clipped) }) else {
                continue
            }
            acceptedPixelRects.append(clipped)
        }

        return acceptedPixelRects.map { UnitRect(rect: $0, in: contentPixelRect) }
    }

    private static func approximatelyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        let tolerance: CGFloat = 0.5
        return abs(lhs.minX - rhs.minX) <= tolerance
            && abs(lhs.minY - rhs.minY) <= tolerance
            && abs(lhs.width - rhs.width) <= tolerance
            && abs(lhs.height - rhs.height) <= tolerance
    }
}

/// Classifies ScreenCaptureKit's damage metadata. A valid empty list proves no reported change for
/// this callback; every nonempty, missing, or malformed report requires exact pixel verification
/// before it may invalidate OCR. A separate low-frequency audit guards against a dropped report.
enum TextFollowDirtyFramePolicy {
    static let maximumDirtyRectCount = 256

    struct Assessment: Equatable, Sendable {
        let hasAnyChange: Bool
        let isUnclassified: Bool
    }

    static func assess(
        dirtyRects: [CGRect]?,
        contentPixelRect: CGRect
    ) -> Assessment {
        guard let coverage = coverage(
            of: dirtyRects,
            inside: contentPixelRect
        ) else {
            return Assessment(
                hasAnyChange: true,
                isUnclassified: true
            )
        }
        return Assessment(
            hasAnyChange: coverage > 0,
            isUnclassified: false
        )
    }

    /// Returns the exact union coverage of valid dirty rectangles clipped to captured content.
    /// Nil means that the metadata cannot be classified safely.
    static func coverage(
        of dirtyRects: [CGRect]?,
        inside contentPixelRect: CGRect
    ) -> CGFloat? {
        let contentValues = [
            contentPixelRect.minX, contentPixelRect.minY,
            contentPixelRect.width, contentPixelRect.height
        ]
        guard contentValues.allSatisfy(\.isFinite),
              contentPixelRect.width > 0,
              contentPixelRect.height > 0,
              let dirtyRects,
              dirtyRects.count <= maximumDirtyRectCount else { return nil }
        guard !dirtyRects.isEmpty else { return 0 }

        var clippedRects: [CGRect] = []
        clippedRects.reserveCapacity(dirtyRects.count)
        for dirtyRect in dirtyRects {
            let values = [dirtyRect.minX, dirtyRect.minY, dirtyRect.width, dirtyRect.height]
            guard values.allSatisfy(\.isFinite),
                  dirtyRect.width >= 0,
                  dirtyRect.height >= 0 else { return nil }
            guard dirtyRect.width > 0, dirtyRect.height > 0 else { continue }

            let clipped = dirtyRect.intersection(contentPixelRect)
            guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { continue }
            clippedRects.append(clipped)
        }

        guard !clippedRects.isEmpty else { return 0 }
        let xCoordinates = Set(clippedRects.flatMap { [$0.minX, $0.maxX] }).sorted()
        var unionArea: CGFloat = 0

        for index in 0..<(xCoordinates.count - 1) {
            let minX = xCoordinates[index]
            let maxX = xCoordinates[index + 1]
            let width = maxX - minX
            guard width > 0 else { continue }

            let intervals = clippedRects.compactMap { rect -> (min: CGFloat, max: CGFloat)? in
                guard rect.minX < maxX, rect.maxX > minX else { return nil }
                return (rect.minY, rect.maxY)
            }.sorted {
                if $0.min != $1.min { return $0.min < $1.min }
                return $0.max < $1.max
            }
            guard var current = intervals.first else { continue }
            var coveredHeight: CGFloat = 0
            for interval in intervals.dropFirst() {
                if interval.min <= current.max {
                    current.max = max(current.max, interval.max)
                } else {
                    coveredHeight += current.max - current.min
                    current = interval
                }
            }
            coveredHeight += current.max - current.min
            unionArea += width * coveredHeight
        }

        let contentArea = contentPixelRect.width * contentPixelRect.height
        guard contentArea.isFinite, contentArea > 0, unionArea.isFinite else { return nil }
        return min(max(unionArea / contentArea, 0), 1)
    }
}

struct TextFollowFrameProcessingAssessment: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case initial
        case unchanged
        case changed
        case unknown
    }

    let kind: Kind

    var shouldProcess: Bool { kind != .unchanged }
    var invalidatesInFlight: Bool { kind == .changed || kind == .unknown }
}

enum TextFollowFrameSubmissionPolicy {
    static func accepts(
        currentGeneration: UInt64,
        inputGeneration: UInt64,
        activeStreamIdentifier: ObjectIdentifier?,
        expectedStreamIdentifier: ObjectIdentifier,
        failed: Bool,
        hasSpecifications: Bool
    ) -> Bool {
        currentGeneration == inputGeneration
            && activeStreamIdentifier == expectedStreamIdentifier
            && !failed
            && hasSpecifications
    }
}

/// A transient 128-bit fingerprint over every valid BGRA byte in captured content. It distinguishes
/// real pixel changes from broad/unknown redraw metadata that reports an unchanged image. The
/// fingerprint cannot reconstruct the source image and is never persisted or logged.
struct TextFollowPixelFingerprint: Equatable, Sendable {
    let width: Int
    let height: Int
    let primary: UInt64
    let secondary: UInt64

    static func make(
        from pixelBuffer: CVPixelBuffer,
        contentPixelRect: CGRect
    ) -> TextFollowPixelFingerprint? {
        guard CVPixelBufferGetPixelFormatType(pixelBuffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
            return nil
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }

        let pixelWidth = CVPixelBufferGetWidth(pixelBuffer)
        let pixelHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let minX = max(0, Int(contentPixelRect.minX.rounded(.down)))
        let minY = max(0, Int(contentPixelRect.minY.rounded(.down)))
        let maxX = min(pixelWidth, Int(contentPixelRect.maxX.rounded(.up)))
        let maxY = min(pixelHeight, Int(contentPixelRect.maxY.rounded(.up)))
        guard maxX > minX, maxY > minY, bytesPerRow >= pixelWidth * 4 else { return nil }

        let width = maxX - minX
        let height = maxY - minY
        let bytesInRow = width * 4
        var hasher = SHA256()
        let header = [
            UInt64(minX).littleEndian,
            UInt64(minY).littleEndian,
            UInt64(width).littleEndian,
            UInt64(height).littleEndian
        ]
        header.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        if minX == 0, bytesInRow == bytesPerRow {
            // The common full-width capture is contiguous. One CryptoKit update avoids thousands
            // of row-level calls while preserving the exact same byte coverage.
            let start = baseAddress.advanced(by: minY * bytesPerRow)
            hasher.update(bufferPointer: UnsafeRawBufferPointer(
                start: start,
                count: height * bytesPerRow
            ))
        } else {
            for y in minY..<maxY {
                let row = baseAddress.advanced(by: y * bytesPerRow + minX * 4)
                hasher.update(bufferPointer: UnsafeRawBufferPointer(
                    start: row,
                    count: bytesInRow
                ))
            }
        }
        let digest = hasher.finalize()
        let words = digest.withUnsafeBytes { bytes in
            (
                UInt64(littleEndian: bytes.loadUnaligned(
                    fromByteOffset: 0,
                    as: UInt64.self
                )),
                UInt64(littleEndian: bytes.loadUnaligned(
                    fromByteOffset: MemoryLayout<UInt64>.size,
                    as: UInt64.self
                ))
            )
        }

        return TextFollowPixelFingerprint(
            width: width,
            height: height,
            primary: words.0,
            secondary: words.1
        )
    }
}

/// Compares exact hashes of consecutive captured frames. ScreenCaptureKit can report non-empty
/// dirty rectangles for an unchanged browser window, so metadata alone cannot invalidate every
/// in-flight OCR request without starving recognition forever.
struct TextFollowFrameChangeDetector: Sendable {
    private var hasPreviousFrame = false
    private var previousFingerprint: TextFollowPixelFingerprint?

    func requiresFingerprint(metadataReportsChange: Bool) -> Bool {
        !hasPreviousFrame || metadataReportsChange
    }

    mutating func assess(
        fingerprint: TextFollowPixelFingerprint?,
        metadataReportsChange: Bool
    ) -> TextFollowFrameProcessingAssessment {
        guard hasPreviousFrame else {
            hasPreviousFrame = true
            previousFingerprint = fingerprint
            return TextFollowFrameProcessingAssessment(kind: .initial)
        }
        guard metadataReportsChange else {
            // Outside a caller-requested periodic audit, a valid empty dirty list deliberately
            // omits hashing and preserves the last exact baseline for the next reported change.
            return TextFollowFrameProcessingAssessment(kind: .unchanged)
        }
        defer { previousFingerprint = fingerprint }

        switch (previousFingerprint, fingerprint) {
        case let (.some(previous), .some(current)):
            return TextFollowFrameProcessingAssessment(
                kind: previous == current ? .unchanged : .changed
            )
        case (.none, .none):
            return TextFollowFrameProcessingAssessment(kind: .unknown)
        case (.some, .none), (.none, .some):
            // Losing or gaining an exact fingerprint means continuity cannot be proven.
            return TextFollowFrameProcessingAssessment(kind: .unknown)
        }
    }

    mutating func invalidateBaseline() {
        hasPreviousFrame = false
        previousFingerprint = nil
    }
}

/// Scopes the exact-pixel baseline to one capture generation. A frame can finish hashing after a
/// reconnect or rule edit; tagging the detector prevents discarded work becoming the new baseline.
struct TextFollowGenerationFrameChangeDetector: Sendable {
    /// A valid empty dirty list is normally authoritative, but a low-frequency exact audit lets
    /// the session self-heal if WindowServer or a GPU driver ever omits one damage notification.
    static let periodicAuditIntervalNanoseconds: UInt64 = 1_000_000_000

    private var trackedGeneration: UInt64?
    private var detector = TextFollowFrameChangeDetector()
    private var lastFingerprintUptimeNanoseconds: UInt64?
    private var forcedAuditGeneration: UInt64?
    /// A scroll's last complete frame can carry an empty dirty list less than one second after an
    /// intermediate changed frame. Audit empty complete frames until exact pixels settle so that
    /// final frame cannot be stranded when ScreenCaptureKit switches directly to idle callbacks.
    private var requiresSettlingAudit = false

    mutating func requiresFingerprint(
        metadataReportsChange: Bool,
        generation: UInt64,
        nowUptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> Bool {
        guard let trackedGeneration else { return true }
        guard generation >= trackedGeneration else { return false }
        if generation != trackedGeneration
            || detector.requiresFingerprint(metadataReportsChange: metadataReportsChange) {
            return true
        }
        if requiresSettlingAudit { return true }
        guard let lastFingerprintUptimeNanoseconds else {
            forcedAuditGeneration = generation
            return true
        }
        let elapsed = nowUptimeNanoseconds >= lastFingerprintUptimeNanoseconds
            ? nowUptimeNanoseconds - lastFingerprintUptimeNanoseconds
            : UInt64.max
        guard elapsed >= Self.periodicAuditIntervalNanoseconds else { return false }
        forcedAuditGeneration = generation
        return true
    }

    mutating func assess(
        fingerprint: TextFollowPixelFingerprint?,
        metadataReportsChange: Bool,
        generation: UInt64,
        nowUptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> TextFollowFrameProcessingAssessment {
        if let trackedGeneration, generation < trackedGeneration {
            // Work from a retired stream must not roll the active generation's exact baseline back.
            return TextFollowFrameProcessingAssessment(kind: .unchanged)
        }
        if trackedGeneration != generation {
            trackedGeneration = generation
            detector = TextFollowFrameChangeDetector()
            lastFingerprintUptimeNanoseconds = nil
            forcedAuditGeneration = nil
            requiresSettlingAudit = false
        }
        let isForcedAudit = forcedAuditGeneration == generation
        forcedAuditGeneration = nil
        lastFingerprintUptimeNanoseconds = nowUptimeNanoseconds
        let isSettlingAudit = requiresSettlingAudit && !metadataReportsChange
        let assessment = detector.assess(
            fingerprint: fingerprint,
            // A periodic audit must compare the supplied exact fingerprint even when damage
            // metadata was empty. A settling audit does the same immediately after real changes.
            metadataReportsChange: metadataReportsChange || isForcedAudit || isSettlingAudit
        )
        if assessment.invalidatesInFlight {
            requiresSettlingAudit = true
        } else if isSettlingAudit {
            requiresSettlingAudit = false
        }
        return assessment
    }

    mutating func invalidateBaseline(generation: UInt64) {
        if let trackedGeneration, generation < trackedGeneration { return }
        trackedGeneration = generation
        detector.invalidateBaseline()
        lastFingerprintUptimeNanoseconds = nil
        forcedAuditGeneration = nil
        requiresSettlingAudit = false
    }
}

struct TextFollowLatestFrameMailbox<Value> {
    struct Item {
        let sequence: UInt64
        let value: Value

        fileprivate let epoch: UInt64

        var retryFrameCursor: TextFollowRetryFrameCursor {
            TextFollowRetryFrameCursor(sequence: sequence, epoch: epoch)
        }
    }

    struct Submission {
        let sequence: UInt64
        /// True only when the caller must enqueue a recognition turn.
        let shouldSchedule: Bool
    }

    private(set) var latestSequence: UInt64 = 0
    private(set) var latestInvalidatingSequence: UInt64 = 0
    private var epoch: UInt64 = 0
    private var pending: Item?
    private var turnScheduled = false

    @discardableResult
    mutating func submit(_ value: Value) -> Submission {
        enqueue(value, invalidatingInFlight: false)
    }

    /// Replaces the pending frame and makes work already executing in the previous epoch stale.
    /// Callers use this only after exact pixel comparison proves a change (or equality cannot be
    /// established); an initial baseline submission does not invalidate work in flight.
    @discardableResult
    mutating func submitInvalidatingInFlight(_ value: Value) -> Submission {
        enqueue(value, invalidatingInFlight: true)
    }

    private mutating func enqueue(
        _ value: Value,
        invalidatingInFlight: Bool
    ) -> Submission {
        latestSequence &+= 1
        if invalidatingInFlight {
            epoch &+= 1
            latestInvalidatingSequence = latestSequence
        }
        pending = Item(sequence: latestSequence, value: value, epoch: epoch)
        let shouldSchedule = !turnScheduled
        turnScheduled = true
        return Submission(
            sequence: latestSequence,
            shouldSchedule: shouldSchedule
        )
    }

    /// Takes at most one frame for the currently scheduled recognition turn.
    mutating func takeScheduledTurn() -> Item? {
        defer { pending = nil }
        return pending
    }

    /// A newer frame in the same epoch does not invalidate an in-flight result. Only an explicit
    /// cancellation/reconfiguration advances the epoch and makes that result stale.
    func canPublish(_ item: Item) -> Bool { item.epoch == epoch }

    func isCurrent(_ cursor: TextFollowRetryFrameCursor) -> Bool {
        cursor.epoch == epoch && cursor.sequence == latestSequence
    }

    /// Completes one recognition turn. Returning true tells the caller to append exactly one new
    /// turn to the shared queue's tail, preserving fairness between capture sessions.
    mutating func finishScheduledTurn() -> Bool {
        guard pending == nil else { return true }
        turnScheduled = false
        return false
    }

    @discardableResult
    mutating func cancel() -> UInt64 {
        latestSequence &+= 1
        latestInvalidatingSequence = latestSequence
        epoch &+= 1
        pending = nil
        return epoch
    }
}

enum TextFollowEventPhase: Int, Equatable, Sendable {
    case scanning
    case result
}

struct TextFollowEventCursor: Equatable, Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var sequence: UInt64 = 0
    private(set) var phase: TextFollowEventPhase = .scanning
    private var hasAcceptedEvent = false

    mutating func accepts(
        generation: UInt64,
        sequence: UInt64,
        phase: TextFollowEventPhase = .result
    ) -> Bool {
        if hasAcceptedEvent {
            guard generation >= self.generation else { return false }
            if generation == self.generation {
                guard sequence >= self.sequence else { return false }
                if sequence == self.sequence, phase.rawValue < self.phase.rawValue { return false }
            }
        }
        self.generation = generation
        self.sequence = sequence
        self.phase = phase
        hasAcceptedEvent = true
        return true
    }
}

/// Orders OCR completions independently from damage/scanning events. A completion from an older
/// frame can still improve desktop masking while a newer frame is being recognized, but an even
/// older completion must never roll geometry back after a newer completion was accepted.
struct TextFollowCompletionCursor: Equatable, Sendable {
    private(set) var generation: UInt64 = 0
    private(set) var sequence: UInt64 = 0
    private var hasAcceptedCompletion = false

    mutating func accepts(generation: UInt64, sequence: UInt64) -> Bool {
        if hasAcceptedCompletion {
            guard generation > self.generation
                    || (generation == self.generation && sequence > self.sequence) else {
                return false
            }
        }
        self.generation = generation
        self.sequence = sequence
        hasAcceptedCompletion = true
        return true
    }
}

struct TextFollowBoundedRetryPolicy: Equatable, Sendable {
    let delaysNanoseconds: [UInt64]

    func delayNanoseconds(forAttempt attempt: Int) -> UInt64? {
        guard attempt > 0, attempt <= delaysNanoseconds.count else { return nil }
        return delaysNanoseconds[attempt - 1]
    }

    static let recognitionFailure = TextFollowBoundedRetryPolicy(
        delaysNanoseconds: [250_000_000, 750_000_000, 1_500_000_000]
    )
    static let streamFailure = TextFollowBoundedRetryPolicy(
        delaysNanoseconds: [500_000_000, 1_000_000_000, 2_000_000_000]
    )
    static let configurationUpdate = TextFollowBoundedRetryPolicy(
        delaysNanoseconds: [250_000_000, 750_000_000, 1_500_000_000]
    )
}

struct TextFollowRetryTicket: Equatable, Sendable {
    let generation: UInt64
    let frameCursor: TextFollowRetryFrameCursor?
    let attempt: Int
    let revision: UInt64
    let delayNanoseconds: UInt64
}

struct TextFollowRetryFrameCursor: Equatable, Sendable {
    let sequence: UInt64
    let epoch: UInt64

    func isNewer(than other: TextFollowRetryFrameCursor) -> Bool {
        epoch > other.epoch || (epoch == other.epoch && sequence > other.sequence)
    }
}

enum TextFollowRetryScheduleResult: Equatable, Sendable {
    case scheduled(TextFollowRetryTicket)
    case alreadyPending
    case exhausted
    case stale
}

struct TextFollowBoundedRetryCursor: Equatable, Sendable {
    private(set) var generation: UInt64?
    private(set) var attempts = 0
    private(set) var pendingTicket: TextFollowRetryTicket?
    private var revision: UInt64 = 0

    mutating func schedule(
        generation: UInt64,
        frameCursor: TextFollowRetryFrameCursor? = nil,
        policy: TextFollowBoundedRetryPolicy
    ) -> TextFollowRetryScheduleResult {
        if let currentGeneration = self.generation, generation < currentGeneration { return .stale }
        if self.generation != generation {
            self.generation = generation
            attempts = 0
            pendingTicket = nil
            revision &+= 1
        }
        if let pendingTicket {
            guard let frameCursor,
                  let pendingCursor = pendingTicket.frameCursor,
                  frameCursor.isNewer(than: pendingCursor) else { return .alreadyPending }
            revision &+= 1
            let replacement = TextFollowRetryTicket(
                generation: generation,
                frameCursor: frameCursor,
                attempt: pendingTicket.attempt,
                revision: revision,
                delayNanoseconds: pendingTicket.delayNanoseconds
            )
            self.pendingTicket = replacement
            return .scheduled(replacement)
        }
        guard let delay = policy.delayNanoseconds(forAttempt: attempts + 1) else {
            return .exhausted
        }
        attempts += 1
        revision &+= 1
        let ticket = TextFollowRetryTicket(
            generation: generation,
            frameCursor: frameCursor,
            attempt: attempts,
            revision: revision,
            delayNanoseconds: delay
        )
        pendingTicket = ticket
        return .scheduled(ticket)
    }

    mutating func consume(_ ticket: TextFollowRetryTicket) -> Bool {
        guard pendingTicket == ticket else { return false }
        pendingTicket = nil
        return true
    }

    mutating func reset(generation: UInt64) {
        if let currentGeneration = self.generation, generation < currentGeneration { return }
        self.generation = generation
        attempts = 0
        pendingTicket = nil
        revision &+= 1
    }
}

struct TextFollowRecognitionWatchdogKey: Equatable, Sendable {
    let requestID: UInt64
    let generation: UInt64
    let epoch: UInt64
}

struct TextFollowRecognitionWatchdogCursor: Equatable, Sendable {
    private var nextRequestID: UInt64 = 0
    private(set) var activeKey: TextFollowRecognitionWatchdogKey?
    private var activeRequestTimedOut = false

    mutating func begin(generation: UInt64, epoch: UInt64) -> TextFollowRecognitionWatchdogKey {
        nextRequestID &+= 1
        let key = TextFollowRecognitionWatchdogKey(
            requestID: nextRequestID,
            generation: generation,
            epoch: epoch
        )
        activeKey = key
        activeRequestTimedOut = false
        return key
    }

    mutating func markTimedOut(_ key: TextFollowRecognitionWatchdogKey) -> Bool {
        guard activeKey == key, !activeRequestTimedOut else { return false }
        activeRequestTimedOut = true
        return true
    }

    mutating func finish(_ key: TextFollowRecognitionWatchdogKey) -> Bool? {
        guard activeKey == key else { return nil }
        let timedOut = activeRequestTimedOut
        activeKey = nil
        activeRequestTimedOut = false
        return timedOut
    }
}

/// Distinguishes a normally-running Vision worker from one whose synchronous `perform` call has
/// exceeded its deadline. The pool normally runs one worker at a time. Only a timed-out worker can
/// open the single reserve slot, so ordinary OCR remains serialized while one uncooperative Vision
/// request cannot stop every other selected window forever.
struct TextFollowRecognitionWorkerLease: Hashable, Sendable {
    fileprivate let id: UInt64
}

struct TextFollowRecognitionWorkerPoolCursor: Equatable, Sendable {
    private enum WorkerState: Equatable, Sendable {
        case active
        case orphaned
    }

    let maximumOutstandingWorkers: Int
    private var nextLeaseID: UInt64 = 0
    private var workers: [TextFollowRecognitionWorkerLease: WorkerState] = [:]

    init(maximumOutstandingWorkers: Int = 2) {
        precondition(maximumOutstandingWorkers > 0)
        self.maximumOutstandingWorkers = maximumOutstandingWorkers
    }

    var activeWorkerCount: Int {
        workers.values.filter { $0 == .active }.count
    }

    var orphanedWorkerCount: Int {
        workers.values.filter { $0 == .orphaned }.count
    }

    var outstandingWorkerCount: Int { workers.count }

    var isExhaustedByOrphans: Bool {
        activeWorkerCount == 0
            && orphanedWorkerCount >= maximumOutstandingWorkers
    }

    /// Starts normal work only when no other normal worker is active. A timed-out worker remains in
    /// the outstanding count until its call really returns, which is what bounds leaked threads and
    /// retained pixel buffers even if Vision ignores cancellation indefinitely.
    mutating func beginIfPossible() -> TextFollowRecognitionWorkerLease? {
        guard activeWorkerCount == 0,
              outstandingWorkerCount < maximumOutstandingWorkers else { return nil }
        nextLeaseID &+= 1
        let lease = TextFollowRecognitionWorkerLease(id: nextLeaseID)
        workers[lease] = .active
        return lease
    }

    /// Retires the logical slot but keeps the physical worker accounted for as an orphan. This may
    /// make exactly one replacement eligible while the timed-out synchronous call is still blocked.
    mutating func markTimedOut(_ lease: TextFollowRecognitionWorkerLease) -> Bool {
        guard workers[lease] == .active else { return false }
        workers[lease] = .orphaned
        return true
    }

    /// A late worker completion releases only its own physical lease and cannot affect the newer
    /// active request. Returning false makes duplicate/unknown completions explicit in tests.
    mutating func finish(_ lease: TextFollowRecognitionWorkerLease) -> Bool {
        workers.removeValue(forKey: lease) != nil
    }
}

/// Tracks an endless succession of materially different frames while no current-frame OCR result
/// can complete. Accepting an old full-frame result would expose text that appeared later, so after
/// a bounded interval the UI stays fail-closed instead of displaying an infinite spinner. Capture
/// and latest-frame OCR continue; an authoritative completion resets the episode automatically.
struct TextFollowContinuousInvalidationCursor: Equatable, Sendable {
    enum Action: Equatable, Sendable {
        case scanning
        case enterFailClosed
        case remainFailClosed
    }

    static let failClosedAfterNanoseconds: UInt64 = 3_000_000_000

    private var generation: UInt64?
    private var firstInvalidationUptimeNanoseconds: UInt64?
    private(set) var isFailClosed = false

    mutating func recordInvalidation(
        generation: UInt64,
        nowUptimeNanoseconds: UInt64 = DispatchTime.now().uptimeNanoseconds
    ) -> Action {
        if self.generation != generation {
            reset(generation: generation)
        }
        if isFailClosed { return .remainFailClosed }
        guard let firstInvalidationUptimeNanoseconds else {
            self.firstInvalidationUptimeNanoseconds = nowUptimeNanoseconds
            return .scanning
        }
        let elapsed = nowUptimeNanoseconds >= firstInvalidationUptimeNanoseconds
            ? nowUptimeNanoseconds - firstInvalidationUptimeNanoseconds
            : UInt64.max
        guard elapsed >= Self.failClosedAfterNanoseconds else { return .scanning }
        isFailClosed = true
        return .enterFailClosed
    }

    mutating func recordAuthoritativeCompletion(generation: UInt64) {
        guard self.generation == generation else { return }
        firstInvalidationUptimeNanoseconds = nil
        isFailClosed = false
    }

    mutating func reset(generation: UInt64? = nil) {
        self.generation = generation
        firstInvalidationUptimeNanoseconds = nil
        isFailClosed = false
    }
}

private final class TextFollowRecognitionWorkerPool: @unchecked Sendable {
    typealias Work = @Sendable (TextFollowRecognitionWorkerLease) -> Void
    typealias Rejection = @Sendable () -> Void

    private struct PendingWork {
        let work: Work
        let rejection: Rejection
    }

    private static let maximumPendingWork = 64
    private let lock = NSLock()
    private var cursor = TextFollowRecognitionWorkerPoolCursor()
    private var pending: [PendingWork] = []
    private let queue = DispatchQueue(
        label: "com.hinoshiba.blurfollow.text-follow.recognition.worker",
        qos: .userInitiated,
        attributes: .concurrent
    )

    @discardableResult
    func submit(
        _ work: @escaping Work,
        onRejected rejection: @escaping Rejection
    ) -> Bool {
        lock.lock()
        guard !cursor.isExhaustedByOrphans,
              pending.count < Self.maximumPendingWork else {
            lock.unlock()
            return false
        }
        pending.append(PendingWork(work: work, rejection: rejection))
        let starts = takeStartableWorkWhileLocked()
        lock.unlock()
        dispatch(starts)
        return true
    }

    @discardableResult
    func markTimedOut(_ lease: TextFollowRecognitionWorkerLease) -> Bool {
        lock.lock()
        let marked = cursor.markTimedOut(lease)
        let starts = marked ? takeStartableWorkWhileLocked() : []
        let rejections: [Rejection]
        if marked, cursor.isExhaustedByOrphans {
            rejections = pending.map(\.rejection)
            pending.removeAll(keepingCapacity: true)
        } else {
            rejections = []
        }
        lock.unlock()
        dispatch(starts)
        for rejection in rejections { rejection() }
        return marked
    }

    private func finish(_ lease: TextFollowRecognitionWorkerLease) {
        lock.lock()
        _ = cursor.finish(lease)
        let starts = takeStartableWorkWhileLocked()
        lock.unlock()
        dispatch(starts)
    }

    private func takeStartableWorkWhileLocked() -> [(TextFollowRecognitionWorkerLease, Work)] {
        var starts: [(TextFollowRecognitionWorkerLease, Work)] = []
        while !pending.isEmpty, let lease = cursor.beginIfPossible() {
            starts.append((lease, pending.removeFirst().work))
        }
        return starts
    }

    private func dispatch(_ starts: [(TextFollowRecognitionWorkerLease, Work)]) {
        for (lease, work) in starts {
            queue.async { [self] in
                work(lease)
                finish(lease)
            }
        }
    }
}

enum TextFollowRecognitionCompletionPolicy {
    static func isCurrent(
        currentGeneration: UInt64,
        inputGeneration: UInt64,
        sessionFailed: Bool
    ) -> Bool {
        currentGeneration == inputGeneration && !sessionFailed
    }
}

struct TextFollowStreamStartupWatchdogKey: Equatable, Sendable {
    let generation: UInt64
    let attemptID: UInt64
}

struct TextFollowStreamStartupWatchdogCursor: Equatable, Sendable {
    private var nextAttemptID: UInt64 = 0
    private(set) var activeKey: TextFollowStreamStartupWatchdogKey?

    mutating func begin(generation: UInt64) -> TextFollowStreamStartupWatchdogKey {
        nextAttemptID &+= 1
        let key = TextFollowStreamStartupWatchdogKey(
            generation: generation,
            attemptID: nextAttemptID
        )
        activeKey = key
        return key
    }

    mutating func complete(generation: UInt64) -> Bool {
        guard activeKey?.generation == generation else { return false }
        activeKey = nil
        return true
    }

    mutating func expire(_ key: TextFollowStreamStartupWatchdogKey) -> Bool {
        guard activeKey == key else { return false }
        activeKey = nil
        return true
    }

    mutating func cancel() {
        activeKey = nil
    }
}

struct TextFollowStreamHeartbeatKey: Equatable, Sendable {
    let generation: UInt64
    let attemptID: UInt64
}

enum TextFollowStreamCallbackKind: Equatable, Sendable {
    case malformed
    case completeOrStarted(hasUsableFrame: Bool, awaitsConfiguredSurface: Bool)
    case idle
    case blankOrSuspended
    case stoppedOrUnknown
}

enum TextFollowStreamCallbackDisposition: Equatable, Sendable {
    case acceptUsableFrame
    case observeIdle
    case beginInterruptionGrace
    case failImmediately
    case deferToSurfaceWatchdog
}

enum TextFollowStreamCallbackDispositionPolicy {
    static func resolve(
        _ kind: TextFollowStreamCallbackKind
    ) -> TextFollowStreamCallbackDisposition {
        switch kind {
        case .malformed:
            return .beginInterruptionGrace
        case .completeOrStarted(let hasUsableFrame, let awaitsConfiguredSurface):
            guard hasUsableFrame else { return .beginInterruptionGrace }
            return awaitsConfiguredSurface ? .deferToSurfaceWatchdog : .acceptUsableFrame
        case .idle:
            return .observeIdle
        case .blankOrSuspended:
            return .beginInterruptionGrace
        case .stoppedOrUnknown:
            return .failImmediately
        }
    }
}

enum TextFollowStreamHeartbeatDecision: Equatable, Sendable {
    case stale
    case rearm(afterNanoseconds: UInt64)
    case expired
}

/// A single sliding timer can supervise a high-frequency SCStream without enqueueing one timer per
/// callback. Complete/started and idle callbacks only advance `lastCallbackUptimeNanoseconds`; the
/// outstanding timer either expires the exact stream attempt or rearms for its remaining interval.
struct TextFollowStreamHeartbeatCursor: Equatable, Sendable {
    private var nextAttemptID: UInt64 = 0
    private(set) var activeKey: TextFollowStreamHeartbeatKey?
    private(set) var lastCallbackUptimeNanoseconds: UInt64?

    mutating func begin(
        generation: UInt64,
        nowUptimeNanoseconds: UInt64
    ) -> TextFollowStreamHeartbeatKey {
        nextAttemptID &+= 1
        let key = TextFollowStreamHeartbeatKey(
            generation: generation,
            attemptID: nextAttemptID
        )
        activeKey = key
        lastCallbackUptimeNanoseconds = nowUptimeNanoseconds
        return key
    }

    @discardableResult
    mutating func observe(
        generation: UInt64,
        nowUptimeNanoseconds: UInt64
    ) -> Bool {
        guard activeKey?.generation == generation,
              lastCallbackUptimeNanoseconds != nil else { return false }
        lastCallbackUptimeNanoseconds = nowUptimeNanoseconds
        return true
    }

    mutating func evaluate(
        _ key: TextFollowStreamHeartbeatKey,
        nowUptimeNanoseconds: UInt64,
        timeoutNanoseconds: UInt64
    ) -> TextFollowStreamHeartbeatDecision {
        guard timeoutNanoseconds > 0,
              activeKey == key,
              let lastCallbackUptimeNanoseconds else { return .stale }
        let elapsed = nowUptimeNanoseconds >= lastCallbackUptimeNanoseconds
            ? nowUptimeNanoseconds - lastCallbackUptimeNanoseconds
            : 0
        guard elapsed >= timeoutNanoseconds else {
            return .rearm(afterNanoseconds: timeoutNanoseconds - elapsed)
        }
        activeKey = nil
        self.lastCallbackUptimeNanoseconds = nil
        return .expired
    }

    mutating func cancel() {
        activeKey = nil
        lastCallbackUptimeNanoseconds = nil
    }
}

struct TextFollowCaptureConfigurationWatchdogKey: Equatable, Sendable {
    let generation: UInt64
    let targetPixelSize: TextFollowCaptureSizePolicy.PixelSize
    let attemptID: UInt64
}

/// Distinguishes repeated updateConfiguration attempts for the same target. Without an attempt ID,
/// the first attempt's late timeout can retire a healthy retry which happens to share its size.
struct TextFollowCaptureConfigurationWatchdogCursor: Equatable, Sendable {
    private var nextAttemptID: UInt64 = 0
    private(set) var activeKey: TextFollowCaptureConfigurationWatchdogKey?

    mutating func begin(
        generation: UInt64,
        targetPixelSize: TextFollowCaptureSizePolicy.PixelSize
    ) -> TextFollowCaptureConfigurationWatchdogKey {
        nextAttemptID &+= 1
        let key = TextFollowCaptureConfigurationWatchdogKey(
            generation: generation,
            targetPixelSize: targetPixelSize,
            attemptID: nextAttemptID
        )
        activeKey = key
        return key
    }

    mutating func complete(_ key: TextFollowCaptureConfigurationWatchdogKey) -> Bool {
        guard activeKey == key else { return false }
        activeKey = nil
        return true
    }

    mutating func expire(_ key: TextFollowCaptureConfigurationWatchdogKey) -> Bool {
        complete(key)
    }

    mutating func cancel() {
        activeKey = nil
    }
}

private struct TextFollowDetectionSignature: Equatable {
    let matchMode: TextMatchMode
    let pattern: String
    let windowAnchor: WindowAnchor
    let padding: Double

    init(rule: TextFollowRule) {
        matchMode = rule.matchMode
        pattern = rule.pattern
        windowAnchor = rule.windowAnchor
        padding = rule.padding
    }
}

private struct TextFollowProcessingSpecification: @unchecked Sendable {
    struct Fingerprint: Equatable, Sendable {
        let ruleID: UUID
        let matchMode: TextMatchMode
        let pattern: String
        let windowAnchor: WindowAnchor
        let padding: Double
    }

    let ruleID: UUID
    let matcher: TextPatternMatcher
    let padding: Double
    let fingerprint: Fingerprint

    init(rule: TextFollowRule) throws {
        ruleID = rule.id
        matcher = try TextPatternMatcher(mode: rule.matchMode, pattern: rule.pattern)
        padding = rule.padding
        fingerprint = Fingerprint(
            ruleID: rule.id,
            matchMode: rule.matchMode,
            pattern: rule.pattern,
            windowAnchor: rule.windowAnchor,
            padding: rule.padding
        )
    }
}

private enum TextFollowCaptureClearReason: Sendable {
    case unavailable
    case failed
}

private struct TextFollowCaptureEvent: Sendable {
    enum Payload: Sendable {
        case scanning(ruleIDs: [UUID])
        /// Continuous pixel churn prevented a current-frame OCR completion. This is ordered like a
        /// scanning event so the same frame may still recover with an authoritative result.
        case failClosed(ruleIDs: [UUID])
        case matches([UUID: [UnitRect]])
        /// Successful OCR for a frame superseded by newer pixels. This may update only the last
        /// desktop geometry while state remains scanning; Share Preview must stay fail-closed.
        case provisionalMatches([UUID: [UnitRect]])
        case cleared(ruleIDs: [UUID], reason: TextFollowCaptureClearReason)
    }

    let sessionID: UUID
    let generation: UInt64
    let sequence: UInt64
    let frameTime: UInt64?
    let payload: Payload

    init(
        sessionID: UUID,
        generation: UInt64,
        sequence: UInt64,
        frameTime: UInt64? = nil,
        payload: Payload
    ) {
        self.sessionID = sessionID
        self.generation = generation
        self.sequence = sequence
        self.frameTime = frameTime
        self.payload = payload
    }
}

private final class TextFollowCaptureSession: NSObject, SCStreamOutput, SCStreamDelegate,
    @unchecked Sendable {
    static let captureQueue = DispatchQueue(
        label: "com.hinoshiba.blurfollow.text-follow.capture",
        qos: .userInitiated
    )
    /// Mailbox turns enter the bounded worker pool in FIFO order across capture sessions.
    private static let recognitionSchedulerQueue = DispatchQueue(
        label: "com.hinoshiba.blurfollow.text-follow.recognition.scheduler",
        qos: .userInitiated
    )
    private static let recognitionWorkerPool = TextFollowRecognitionWorkerPool()
    private static let watchdogQueue = DispatchQueue(
        label: "com.hinoshiba.blurfollow.text-follow.watchdog",
        qos: .utility
    )
    private static let recognitionTimeoutNanoseconds: UInt64 = 8_000_000_000
    private static let firstUsableFrameTimeoutNanoseconds: UInt64 = 3_000_000_000
    private static let streamHeartbeatTimeoutNanoseconds: UInt64 = 4_000_000_000
    private static let transientInterruptionGraceNanoseconds: UInt64 = 500_000_000
    private static let configurationUpdateTimeoutNanoseconds: UInt64 = 3_000_000_000

    private struct PendingFreshStreamConfiguration {
        let sourceSize: CGSize
        let targetPixelSize: TextFollowCaptureSizePolicy.PixelSize
    }

    let id = UUID()
    private let filter: SCContentFilter
    /// Latest source size whose higher-resolution configuration completed successfully.
    /// Access is protected by stateLock because resize metadata arrives on captureQueue.
    private var sourceSize: CGSize
    private let deliver: @Sendable (TextFollowCaptureEvent) -> Void

    private let stateLock = NSLock()
    private var generation: UInt64 = 0
    private var specifications: [TextFollowProcessingSpecification] = []
    private var fingerprints: [TextFollowProcessingSpecification.Fingerprint] = []
    private var streamIdentifier: ObjectIdentifier?
    private var configuredOutputPixelSize: TextFollowCaptureSizePolicy.PixelSize
    private var configurationUpdateTargetPixelSize: TextFollowCaptureSizePolicy.PixelSize?
    private var configurationUpdateSourceSize: CGSize?
    private var pendingConfigurationSourceSize: CGSize?
    /// After updateConfiguration succeeds, already-queued buffers from the prior surface remain
    /// stale until a callback has exactly the requested output dimensions.
    private var awaitedOutputPixelSize: TextFollowCaptureSizePolicy.PixelSize?
    /// A timed-out updateConfiguration cannot be cancelled. Its desired surface is carried to a
    /// newly-created stream so a late completion on the retired stream cannot roll dimensions back.
    private var pendingFreshStreamConfiguration: PendingFreshStreamConfiguration?
    private var captureConfigurationWatchdog = TextFollowCaptureConfigurationWatchdogCursor()
    /// Protected by stateLock. A new stream is not healthy until one usable complete/started frame
    /// reaches the mailbox; idle-only and silent starts are expired by this cursor.
    private var streamStartupWatchdog = TextFollowStreamStartupWatchdogCursor()
    /// Starts only after the first usable frame, then stays alive on complete/started and idle
    /// callbacks. A single sliding timer detects a silently wedged stream.
    private var streamHeartbeat = TextFollowStreamHeartbeatCursor()
    /// Blank/suspended or malformed callbacks may be transient during compositor changes. Claiming
    /// this grace retires the older heartbeat deadline; only a usable authoritative frame cancels
    /// recovery and starts a fresh heartbeat, while idle cannot prove that pixels are usable again.
    private var streamInterruptionWatchdog = TextFollowStreamStartupWatchdogCursor()
    private var failed = false

    private let mailboxLock = NSLock()
    private var mailbox = TextFollowLatestFrameMailbox<FrameInput>()
    /// Protected by mailboxLock so invalidation, authoritative completion, and cancellation share
    /// the same ordering as their corresponding mailbox sequence.
    private var continuousInvalidation = TextFollowContinuousInvalidationCursor()

    private struct ActiveRecognitionRequest {
        let request: VNRecognizeTextRequest
        let watchdogKey: TextFollowRecognitionWatchdogKey
    }

    private enum RecognitionOutcome {
        case success([UUID: [UnitRect]])
        case supersededBeforePerform
        case failed
        /// The watchdog already completed this logical turn. A physical Vision worker returning
        /// later must release only its pool lease and publish nothing.
        case retired
    }

    private let recognitionRequestLock = NSLock()
    private var activeRecognitionRequest: ActiveRecognitionRequest?
    private var recognitionWatchdog = TextFollowRecognitionWatchdogCursor()

    private enum RecoveryKind: Equatable, Sendable {
        case recognitionFailure
        case streamFailure
    }

    private let recoveryLock = NSLock()
    private var recognitionFailureRetries = TextFollowBoundedRetryCursor()
    private var streamFailureRetries = TextFollowBoundedRetryCursor()
    private var configurationFailureRetries = TextFollowBoundedRetryCursor()

    private let frameInvalidationLock = NSLock()
    private var frameChangeDetector = TextFollowGenerationFrameChangeDetector()
    /// Serializes pixel assessment with both worker- and MainActor-side completion checks. Without
    /// this gate, an older OCR result could be published as authoritative while a newly delivered
    /// dirty frame was still being hashed and had not yet invalidated the mailbox.
    private let frameAssessmentPublicationLock = NSLock()

    private var stream: SCStream?

    var currentGeneration: UInt64 {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation
    }

    var hasFailed: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return failed
    }

    private final class FrameInput: @unchecked Sendable {
        let sampleBuffer: CMSampleBuffer
        let contentRectInPoints: CGRect
        let scaleFactor: CGFloat
        let contentScale: CGFloat
        let displayTime: UInt64?
        let generation: UInt64
        let specifications: [TextFollowProcessingSpecification]

        init(
            sampleBuffer: CMSampleBuffer,
            contentRectInPoints: CGRect,
            scaleFactor: CGFloat,
            contentScale: CGFloat,
            displayTime: UInt64?,
            generation: UInt64,
            specifications: [TextFollowProcessingSpecification]
        ) {
            self.sampleBuffer = sampleBuffer
            self.contentRectInPoints = contentRectInPoints
            self.scaleFactor = scaleFactor
            self.contentScale = contentScale
            self.displayTime = displayTime
            self.generation = generation
            self.specifications = specifications
        }
    }

    init(
        selection: PickedWindow,
        deliver: @escaping @Sendable (TextFollowCaptureEvent) -> Void
    ) {
        filter = selection.filter
        let initialSourceSize = selection.filter.contentRect.size == .zero
            ? selection.candidate.quartzFrame.size
            : selection.filter.contentRect.size
        sourceSize = initialSourceSize
        configuredOutputPixelSize = TextFollowCaptureSizePolicy.outputPixelSize(
            sourceSize: initialSourceSize,
            pointPixelScale: max(1, CGFloat(selection.filter.pointPixelScale))
        ) ?? TextFollowCaptureSizePolicy.PixelSize(width: 2, height: 2)
        self.deliver = deliver
        super.init()
    }

    func setActive(
        specifications: [TextFollowProcessingSpecification],
        shouldCapture: Bool
    ) {
        let ordered = specifications.sorted { $0.ruleID.uuidString < $1.ruleID.uuidString }
        let newFingerprints = ordered.map(\.fingerprint)
        frameAssessmentPublicationLock.lock()
        stateLock.lock()
        let changed = fingerprints != newFingerprints
        if changed {
            generation &+= 1
            self.specifications = ordered
            fingerprints = newFingerprints
            failed = false
            // Retire the old callback identity atomically with its generation. Otherwise an old
            // stream can seed the new generation's fingerprint baseline before stopStream runs.
            preservePendingConfigurationForFreshStream()
            streamIdentifier = nil
            streamStartupWatchdog.cancel()
            streamHeartbeat.cancel()
            streamInterruptionWatchdog.cancel()
            captureConfigurationWatchdog.cancel()
        }
        let currentGeneration = generation
        stateLock.unlock()

        if changed {
            resetRecoveryCursors(generation: currentGeneration)
            cancelPendingRecognitionWhileHoldingFramePublicationGate()
        }
        frameAssessmentPublicationLock.unlock()
        if changed { stopStream() }

        guard shouldCapture, !ordered.isEmpty else {
            if !changed { stopStream() }
            return
        }

        if changed || stream == nil {
            guard startStream() else { return }
            deliver(TextFollowCaptureEvent(
                sessionID: id,
                generation: currentGeneration,
                sequence: 0,
                payload: .scanning(ruleIDs: ordered.map(\.ruleID))
            ))
        }
    }

    func requestFreshFrame() {
        frameAssessmentPublicationLock.lock()
        stateLock.lock()
        generation &+= 1
        failed = false
        preservePendingConfigurationForFreshStream()
        streamIdentifier = nil
        streamStartupWatchdog.cancel()
        streamHeartbeat.cancel()
        streamInterruptionWatchdog.cancel()
        captureConfigurationWatchdog.cancel()
        let currentGeneration = generation
        let ruleIDs = specifications.map(\.ruleID)
        stateLock.unlock()
        resetRecoveryCursors(generation: currentGeneration)
        cancelPendingRecognitionWhileHoldingFramePublicationGate()
        frameAssessmentPublicationLock.unlock()
        stopStream()
        guard !ruleIDs.isEmpty else { return }
        guard startStream() else { return }
        deliver(TextFollowCaptureEvent(
            sessionID: id,
            generation: currentGeneration,
            sequence: 0,
            payload: .scanning(ruleIDs: ruleIDs)
        ))
    }

    func invalidate() {
        frameAssessmentPublicationLock.lock()
        stateLock.lock()
        generation &+= 1
        specifications = []
        fingerprints = []
        streamIdentifier = nil
        streamStartupWatchdog.cancel()
        streamHeartbeat.cancel()
        streamInterruptionWatchdog.cancel()
        captureConfigurationWatchdog.cancel()
        pendingFreshStreamConfiguration = nil
        configurationUpdateTargetPixelSize = nil
        configurationUpdateSourceSize = nil
        pendingConfigurationSourceSize = nil
        awaitedOutputPixelSize = nil
        let currentGeneration = generation
        stateLock.unlock()
        resetRecoveryCursors(generation: currentGeneration)
        cancelPendingRecognitionWhileHoldingFramePublicationGate()
        frameAssessmentPublicationLock.unlock()
        stopStream()
    }

    @discardableResult
    private func startStream() -> Bool {
        guard stream == nil else { return true }
        stateLock.lock()
        let pendingFreshConfiguration = pendingFreshStreamConfiguration
        let configuredSourceSize = pendingFreshConfiguration?.sourceSize ?? sourceSize
        stateLock.unlock()
        let configuration = Self.configuration(
            sourceSize: configuredSourceSize,
            filter: filter,
            outputPixelSize: pendingFreshConfiguration?.targetPixelSize
        )
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: Self.captureQueue)
        } catch {
            publishFailure()
            return false
        }

        stateLock.lock()
        let currentGeneration = generation
        streamIdentifier = ObjectIdentifier(stream)
        configuredOutputPixelSize = pendingFreshConfiguration?.targetPixelSize
            ?? TextFollowCaptureSizePolicy.outputPixelSize(
                sourceSize: configuredSourceSize,
                pointPixelScale: max(1, CGFloat(filter.pointPixelScale))
            )
            ?? TextFollowCaptureSizePolicy.PixelSize(
                width: configuration.width,
                height: configuration.height
            )
        configurationUpdateTargetPixelSize = nil
        configurationUpdateSourceSize = nil
        pendingConfigurationSourceSize = nil
        awaitedOutputPixelSize = pendingFreshConfiguration?.targetPixelSize
        captureConfigurationWatchdog.cancel()
        streamHeartbeat.cancel()
        streamInterruptionWatchdog.cancel()
        let startupWatchdogKey = streamStartupWatchdog.begin(generation: currentGeneration)
        stateLock.unlock()
        self.stream = stream
        stream.startCapture { [weak self, weak stream] error in
            guard let self, let stream, let error else { return }
            self.publishFailure(for: stream, error: error)
        }
        armFirstUsableFrameWatchdog(
            for: stream,
            key: startupWatchdogKey
        )
        return true
    }

    private func stopStream() {
        guard let stream else { return }
        self.stream = nil
        stateLock.lock()
        if streamIdentifier == ObjectIdentifier(stream) {
            if let configurationUpdateTargetPixelSize,
               let configurationUpdateSourceSize {
                pendingFreshStreamConfiguration = PendingFreshStreamConfiguration(
                    sourceSize: configurationUpdateSourceSize,
                    targetPixelSize: configurationUpdateTargetPixelSize
                )
            }
            streamIdentifier = nil
            streamStartupWatchdog.cancel()
            streamHeartbeat.cancel()
            streamInterruptionWatchdog.cancel()
            captureConfigurationWatchdog.cancel()
            configurationUpdateTargetPixelSize = nil
            configurationUpdateSourceSize = nil
            pendingConfigurationSourceSize = nil
            awaitedOutputPixelSize = nil
        }
        stateLock.unlock()
        stream.stopCapture { _ in
            try? stream.removeStreamOutput(self, type: .screen)
        }
    }

    nonisolated func stream(_ stoppedStream: SCStream, didStopWithError error: Error) {
        publishFailure(for: stoppedStream, error: error)
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen else { return }
        var shouldPublishImmediateStreamFailure = false
        var shouldBeginTransientInterruptionGrace = false
        var callbackGeneration: UInt64?
        frameAssessmentPublicationLock.lock()
        defer {
            frameAssessmentPublicationLock.unlock()
            if shouldPublishImmediateStreamFailure {
                publishFailure(for: stream)
            } else if shouldBeginTransientInterruptionGrace,
                      let callbackGeneration {
                beginTransientInterruptionGrace(
                    for: stream,
                    generation: callbackGeneration
                )
            }
        }

        guard let snapshot = stateSnapshot(for: stream) else { return }
        callbackGeneration = snapshot.generation

        @discardableResult
        func applyLivenessDisposition(_ kind: TextFollowStreamCallbackKind) -> Bool {
            switch TextFollowStreamCallbackDispositionPolicy.resolve(kind) {
            case .acceptUsableFrame:
                markStreamUsable(stream, generation: snapshot.generation)
                return false
            case .observeIdle:
                observeStreamCallback(
                    stream,
                    generation: snapshot.generation,
                    clearsInterruption: false
                )
                return true
            case .beginInterruptionGrace:
                clear(for: stream, reason: .unavailable)
                shouldBeginTransientInterruptionGrace = true
                return true
            case .failImmediately:
                clear(for: stream, reason: .unavailable)
                shouldPublishImmediateStreamFailure = true
                return true
            case .deferToSurfaceWatchdog:
                return true
            }
        }

        guard sampleBuffer.isValid,
              CMSampleBufferDataIsReady(sampleBuffer) else {
            applyLivenessDisposition(.malformed)
            return
        }

        guard let attachments = Self.attachments(from: sampleBuffer),
              let statusNumber = attachments[.status] as? NSNumber,
              let status = SCFrameStatus(rawValue: statusNumber.intValue) else {
            applyLivenessDisposition(.malformed)
            return
        }

        switch status {
        case .complete, .started:
            guard let contentRect = Self.rect(from: attachments[.contentRect]),
                  let scaleFactor = Self.scalar(from: attachments[.scaleFactor]),
                  let contentScale = Self.scalar(from: attachments[.contentScale]),
                  SharePreviewFrameGeometry.appearanceScale(
                      scaleFactor: scaleFactor,
                      contentScale: contentScale
                  ) != nil,
                  let pixelBuffer = sampleBuffer.imageBuffer,
                  let contentPixelRect = SharePreviewFrameGeometry.contentPixelRect(
                      contentRectInPoints: contentRect,
                      scaleFactor: scaleFactor,
                      extent: CGRect(
                          x: 0,
                          y: 0,
                          width: CVPixelBufferGetWidth(pixelBuffer),
                          height: CVPixelBufferGetHeight(pixelBuffer)
                      )
                  ) else {
                applyLivenessDisposition(.completeOrStarted(
                    hasUsableFrame: false,
                    awaitsConfiguredSurface: false
                ))
                return
            }
            let awaitsConfiguredSurface = shouldDeferFrameUntilConfiguredSurface(
                sampleBuffer,
                stream: stream,
                generation: snapshot.generation
            )
            if applyLivenessDisposition(.completeOrStarted(
                hasUsableFrame: true,
                awaitsConfiguredSurface: awaitsConfiguredSurface
            )) {
                return
            }
            // Only a geometrically usable frame from the authoritative output surface may refresh
            // liveness or clear a preceding interruption. Resize-transition buffers are supervised
            // by their configuration/first-frame watchdogs instead.
            if let observedSourceSize = TextFollowCaptureSizePolicy.originalSourceSize(
                contentRectInPoints: contentRect,
                contentScale: contentScale
            ), requestCaptureResolutionIncreaseIfNeeded(
                observedSourceSize: observedSourceSize,
                observedScaleFactor: scaleFactor,
                stream: stream,
                generation: snapshot.generation
            ) {
                // Do not let a frame from the undersized surface become authoritative. The
                // configuration completion invalidates the fingerprint baseline, and the first
                // frame from the enlarged surface will start a fresh OCR pass.
                return
            }
            let dirtyAssessment = TextFollowDirtyFramePolicy.assess(
                dirtyRects: Self.rects(from: attachments[.dirtyRects]),
                contentPixelRect: contentPixelRect
            )
            // Chrome can report a nonempty dirty rectangle for an unchanged composited frame.
            // Verify every reported change against the exact content bytes so such redraws neither
            // restart Vision nor invalidate the result already in flight. A valid empty dirty list
            // skips the per-frame hash after this generation establishes its baseline, while a
            // an immediate post-change settling audit and a one-second recovery audit catch an
            // omitted final WindowServer damage notification.
            let metadataReportsChange = dirtyAssessment.hasAnyChange
            guard requiresFrameFingerprint(
                metadataReportsChange: metadataReportsChange,
                generation: snapshot.generation
            ) else {
                return
            }
            let pixelFingerprint = TextFollowPixelFingerprint.make(
                from: pixelBuffer,
                contentPixelRect: contentPixelRect
            )
            let frameAssessment = assessFrameChange(
                fingerprint: pixelFingerprint,
                metadataReportsChange: metadataReportsChange,
                generation: snapshot.generation
            )
            guard frameAssessment.shouldProcess else { return }

            // Hashing can overlap a lifecycle change. Recheck the exact stream/generation before
            // constructing mailbox work; submit performs one final atomic generation check.
            guard let latestSnapshot = stateSnapshot(for: stream),
                  latestSnapshot.generation == snapshot.generation else { return }
            submit(FrameInput(
                sampleBuffer: sampleBuffer,
                contentRectInPoints: contentRect,
                scaleFactor: scaleFactor,
                contentScale: contentScale,
                displayTime: Self.unsignedInteger(from: attachments[.displayTime]),
                generation: latestSnapshot.generation,
                specifications: latestSnapshot.specifications
            ),
            invalidatesInFlight: frameAssessment.invalidatesInFlight,
            expectedStreamIdentifier: ObjectIdentifier(stream)
            )
        case .idle:
            applyLivenessDisposition(.idle)
        case .blank, .suspended:
            applyLivenessDisposition(.blankOrSuspended)
        case .stopped:
            applyLivenessDisposition(.stoppedOrUnknown)
        @unknown default:
            applyLivenessDisposition(.stoppedOrUnknown)
        }
    }

    /// Called while frameAssessmentPublicationLock is held. SCStream's configuration completion
    /// does not guarantee that buffers already queued on sampleHandlerQueue use the new surface.
    /// Keep the generation scanning until an exact-dimension callback proves the transition.
    private func shouldDeferFrameUntilConfiguredSurface(
        _ sampleBuffer: CMSampleBuffer,
        stream: SCStream,
        generation expectedGeneration: UInt64
    ) -> Bool {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return false }
        let actualWidth = CVPixelBufferGetWidth(pixelBuffer)
        let actualHeight = CVPixelBufferGetHeight(pixelBuffer)
        stateLock.lock()
        defer { stateLock.unlock() }
        guard streamIdentifier == ObjectIdentifier(stream),
              generation == expectedGeneration else { return false }
        guard TextFollowCaptureSurfaceAuthorityPolicy.isAuthoritative(
            actualWidth: actualWidth,
            actualHeight: actualHeight,
            updateTarget: configurationUpdateTargetPixelSize,
            awaitedTarget: awaitedOutputPixelSize
        ) else { return true }
        if let awaitedOutputPixelSize {
            self.awaitedOutputPixelSize = nil
            if pendingFreshStreamConfiguration?.targetPixelSize == awaitedOutputPixelSize {
                sourceSize = pendingFreshStreamConfiguration?.sourceSize ?? sourceSize
                pendingFreshStreamConfiguration = nil
            }
        }
        return false
    }

    /// Called while frameAssessmentPublicationLock is held. A long-lived selected window may be
    /// much larger than it was at picker time; SCStream otherwise keeps scaling that larger source
    /// into the old surface for the rest of the session. Only resolution increases are applied so
    /// dragging a resize handle cannot oscillate allocation sizes.
    private func requestCaptureResolutionIncreaseIfNeeded(
        observedSourceSize: CGSize,
        observedScaleFactor: CGFloat,
        stream: SCStream,
        generation expectedGeneration: UInt64
    ) -> Bool {
        let preferredScale = max(
            max(1, CGFloat(filter.pointPixelScale)),
            observedScaleFactor
        )
        guard let requestedPixelSize = TextFollowCaptureSizePolicy.outputPixelSize(
            sourceSize: observedSourceSize,
            pointPixelScale: preferredScale
        ) else { return false }

        let expectedStreamIdentifier = ObjectIdentifier(stream)
        stateLock.lock()
        guard streamIdentifier == expectedStreamIdentifier,
              generation == expectedGeneration else {
            stateLock.unlock()
            return false
        }

        if let updateTarget = configurationUpdateTargetPixelSize {
            if TextFollowCaptureSizePolicy.requiresResolutionIncrease(
                from: updateTarget,
                to: requestedPixelSize
            ) {
                pendingConfigurationSourceSize = observedSourceSize
            }
            stateLock.unlock()
            // While an update is in flight, every callback still belongs to the old or an
            // intermediate surface. None may publish as the completed resize result.
            return true
        }

        guard TextFollowCaptureSizePolicy.requiresResolutionIncrease(
            from: configuredOutputPixelSize,
            to: requestedPixelSize
        ) else {
            stateLock.unlock()
            return false
        }

        generation &+= 1
        let resizedGeneration = generation
        // Heartbeat keys are generation-scoped. Retire the old generation's key atomically with
        // the resize transition; otherwise its timer becomes stale while the non-nil key prevents
        // markStreamUsable from starting supervision for the reconfigured surface.
        streamHeartbeat.cancel()
        configurationUpdateTargetPixelSize = requestedPixelSize
        configurationUpdateSourceSize = observedSourceSize
        pendingConfigurationSourceSize = nil
        let ruleIDs = specifications.map(\.ruleID)
        stateLock.unlock()

        resetRecoveryCursors(generation: resizedGeneration)
        cancelPendingRecognitionWhileHoldingFramePublicationGate()
        invalidateFrameFingerprintBaseline(generation: resizedGeneration)
        let sequence = currentMailboxSequence
        deliver(TextFollowCaptureEvent(
            sessionID: id,
            generation: resizedGeneration,
            sequence: sequence,
            payload: .scanning(ruleIDs: ruleIDs)
        ))
        Self.captureQueue.async { [weak self, weak stream] in
            guard let self, let stream else { return }
            self.applyCaptureConfiguration(
                sourceSize: observedSourceSize,
                targetPixelSize: requestedPixelSize,
                stream: stream,
                generation: resizedGeneration
            )
        }
        return true
    }

    private func applyCaptureConfiguration(
        sourceSize targetSourceSize: CGSize,
        targetPixelSize: TextFollowCaptureSizePolicy.PixelSize,
        stream: SCStream,
        generation expectedGeneration: UInt64
    ) {
        let expectedStreamIdentifier = ObjectIdentifier(stream)
        stateLock.lock()
        guard streamIdentifier == expectedStreamIdentifier,
              generation == expectedGeneration,
              configurationUpdateTargetPixelSize == targetPixelSize,
              !failed else {
            stateLock.unlock()
            return
        }
        let watchdogKey = captureConfigurationWatchdog.begin(
            generation: expectedGeneration,
            targetPixelSize: targetPixelSize
        )
        stateLock.unlock()

        let configuration = Self.configuration(
            sourceSize: targetSourceSize,
            filter: filter,
            outputPixelSize: targetPixelSize
        )
        stream.updateConfiguration(configuration) { [weak self, weak stream] error in
            guard let self, let stream else { return }
            self.captureConfigurationDidFinish(
                error: error,
                sourceSize: targetSourceSize,
                targetPixelSize: targetPixelSize,
                stream: stream,
                generation: expectedGeneration,
                watchdogKey: watchdogKey
            )
        }
        armCaptureConfigurationWatchdog(
            sourceSize: targetSourceSize,
            stream: stream,
            watchdogKey: watchdogKey
        )
    }

    private func armCaptureConfigurationWatchdog(
        sourceSize targetSourceSize: CGSize,
        stream: SCStream,
        watchdogKey: TextFollowCaptureConfigurationWatchdogKey
    ) {
        let delay = DispatchTimeInterval.nanoseconds(
            Int(Self.configurationUpdateTimeoutNanoseconds)
        )
        Self.watchdogQueue.asyncAfter(deadline: .now() + delay) { [weak self, weak stream] in
            guard let self, let stream else { return }
            self.timeoutCaptureConfigurationIfPending(
                sourceSize: targetSourceSize,
                stream: stream,
                watchdogKey: watchdogKey
            )
        }
    }

    private func timeoutCaptureConfigurationIfPending(
        sourceSize targetSourceSize: CGSize,
        stream: SCStream,
        watchdogKey: TextFollowCaptureConfigurationWatchdogKey
    ) {
        let expectedStreamIdentifier = ObjectIdentifier(stream)
        frameAssessmentPublicationLock.lock()
        stateLock.lock()
        guard streamIdentifier == expectedStreamIdentifier,
              generation == watchdogKey.generation,
              configurationUpdateTargetPixelSize == watchdogKey.targetPixelSize,
              captureConfigurationWatchdog.expire(watchdogKey) else {
            stateLock.unlock()
            frameAssessmentPublicationLock.unlock()
            return
        }

        // SCStream has no cancellation API for an updateConfiguration call. Retire this stream
        // instead of issuing another update against an operation that may still complete late and
        // roll the output dimensions back. Carry the desired surface into bounded recovery so a
        // fresh stream starts at the target rather than briefly trusting the undersized surface.
        failed = true
        let currentGeneration = generation
        let ruleIDs = specifications.map(\.ruleID)
        let failedStreamIdentifier = streamIdentifier
        let recoveryConfiguration: PendingFreshStreamConfiguration
        if let pendingSourceSize = pendingConfigurationSourceSize,
           let pendingPixelSize = TextFollowCaptureSizePolicy.outputPixelSize(
               sourceSize: pendingSourceSize,
               pointPixelScale: max(1, CGFloat(filter.pointPixelScale))
           ), TextFollowCaptureSizePolicy.requiresResolutionIncrease(
               from: watchdogKey.targetPixelSize,
               to: pendingPixelSize
           ) {
            recoveryConfiguration = PendingFreshStreamConfiguration(
                sourceSize: pendingSourceSize,
                targetPixelSize: pendingPixelSize
            )
        } else {
            recoveryConfiguration = PendingFreshStreamConfiguration(
                sourceSize: targetSourceSize,
                targetPixelSize: watchdogKey.targetPixelSize
            )
        }
        pendingFreshStreamConfiguration = recoveryConfiguration
        streamIdentifier = nil
        streamStartupWatchdog.cancel()
        streamHeartbeat.cancel()
        streamInterruptionWatchdog.cancel()
        configurationUpdateTargetPixelSize = nil
        configurationUpdateSourceSize = nil
        pendingConfigurationSourceSize = nil
        awaitedOutputPixelSize = nil
        stateLock.unlock()
        cancelPendingRecognitionWhileHoldingFramePublicationGate()
        let sequence = currentMailboxSequence
        frameAssessmentPublicationLock.unlock()
        deliver(TextFollowCaptureEvent(
            sessionID: id,
            generation: currentGeneration,
            sequence: sequence,
            payload: .cleared(ruleIDs: ruleIDs, reason: .failed)
        ))
        scheduleStreamFailureRecovery(
            generation: currentGeneration,
            failedStreamIdentifier: failedStreamIdentifier,
            shouldRetry: !ruleIDs.isEmpty
        )
    }

    private func captureConfigurationDidFinish(
        error: Error?,
        sourceSize targetSourceSize: CGSize,
        targetPixelSize: TextFollowCaptureSizePolicy.PixelSize,
        stream: SCStream,
        generation expectedGeneration: UInt64,
        watchdogKey: TextFollowCaptureConfigurationWatchdogKey
    ) {
        let expectedStreamIdentifier = ObjectIdentifier(stream)
        var nextUpdate: (CGSize, TextFollowCaptureSizePolicy.PixelSize)?
        var firstReconfiguredFrameWatchdogKey: TextFollowStreamStartupWatchdogKey?
        var shouldScheduleRetry = false

        frameAssessmentPublicationLock.lock()
        stateLock.lock()
        guard streamIdentifier == expectedStreamIdentifier,
              generation == expectedGeneration,
              configurationUpdateTargetPixelSize == targetPixelSize,
              captureConfigurationWatchdog.complete(watchdogKey) else {
            stateLock.unlock()
            frameAssessmentPublicationLock.unlock()
            return
        }

        if error == nil {
            configuredOutputPixelSize = targetPixelSize
            sourceSize = targetSourceSize
        } else {
            // Keep the transition active during backoff. requestCaptureResolutionIncreaseIfNeeded
            // and shouldDeferFrameUntilConfiguredSurface therefore reject every callback from the
            // still-undersized surface until this exact target succeeds.
            shouldScheduleRetry = true
        }

        if error == nil,
           let pendingSourceSize = pendingConfigurationSourceSize,
           let pendingPixelSize = TextFollowCaptureSizePolicy.outputPixelSize(
               sourceSize: pendingSourceSize,
               pointPixelScale: max(1, CGFloat(filter.pointPixelScale))
           ),
           TextFollowCaptureSizePolicy.requiresResolutionIncrease(
               from: targetPixelSize,
               to: pendingPixelSize
           ) {
            configurationUpdateTargetPixelSize = pendingPixelSize
            configurationUpdateSourceSize = pendingSourceSize
            awaitedOutputPixelSize = nil
            nextUpdate = (pendingSourceSize, pendingPixelSize)
        } else if error == nil {
            configurationUpdateTargetPixelSize = nil
            configurationUpdateSourceSize = nil
            awaitedOutputPixelSize = targetPixelSize
            firstReconfiguredFrameWatchdogKey = streamStartupWatchdog.begin(
                generation: expectedGeneration
            )
        }
        if error == nil { pendingConfigurationSourceSize = nil }
        stateLock.unlock()

        if error == nil {
            // Make the first callback from the new surface establish a new exact-pixel baseline
            // before any OCR completion can be accepted.
            invalidateFrameFingerprintBaseline(generation: expectedGeneration)
        }
        frameAssessmentPublicationLock.unlock()

        if shouldScheduleRetry {
            scheduleCaptureConfigurationRetry(
                sourceSize: targetSourceSize,
                targetPixelSize: targetPixelSize,
                stream: stream,
                generation: expectedGeneration
            )
        } else {
            resetConfigurationFailureRetries(generation: expectedGeneration)
        }
        if let nextUpdate {
            applyCaptureConfiguration(
                sourceSize: nextUpdate.0,
                targetPixelSize: nextUpdate.1,
                stream: stream,
                generation: expectedGeneration
            )
        } else if let firstReconfiguredFrameWatchdogKey {
            armFirstUsableFrameWatchdog(
                for: stream,
                key: firstReconfiguredFrameWatchdogKey
            )
        }
    }

    private func scheduleCaptureConfigurationRetry(
        sourceSize targetSourceSize: CGSize,
        targetPixelSize: TextFollowCaptureSizePolicy.PixelSize,
        stream: SCStream,
        generation expectedGeneration: UInt64
    ) {
        recoveryLock.lock()
        let result = configurationFailureRetries.schedule(
            generation: expectedGeneration,
            policy: .configurationUpdate
        )
        recoveryLock.unlock()

        switch result {
        case .scheduled(let ticket):
            Task { @MainActor [weak self, weak stream] in
                do { try await Task.sleep(nanoseconds: ticket.delayNanoseconds) }
                catch { return }
                guard let self, let stream else { return }
                self.performScheduledCaptureConfigurationRetry(
                    ticket,
                    sourceSize: targetSourceSize,
                    targetPixelSize: targetPixelSize,
                    stream: stream
                )
            }
        case .exhausted:
            stopAfterExhaustedCaptureConfigurationRetries(
                sourceSize: targetSourceSize,
                targetPixelSize: targetPixelSize,
                stream: stream,
                generation: expectedGeneration
            )
        case .alreadyPending, .stale:
            break
        }
    }

    @MainActor
    private func performScheduledCaptureConfigurationRetry(
        _ ticket: TextFollowRetryTicket,
        sourceSize targetSourceSize: CGSize,
        targetPixelSize: TextFollowCaptureSizePolicy.PixelSize,
        stream: SCStream
    ) {
        let expectedStreamIdentifier = ObjectIdentifier(stream)
        frameAssessmentPublicationLock.lock()
        stateLock.lock()
        let canRetry = generation == ticket.generation
            && streamIdentifier == expectedStreamIdentifier
            && configurationUpdateTargetPixelSize == targetPixelSize
            && !failed
            && !specifications.isEmpty
        recoveryLock.lock()
        let consumed = configurationFailureRetries.consume(ticket)
        recoveryLock.unlock()
        stateLock.unlock()
        frameAssessmentPublicationLock.unlock()
        guard consumed, canRetry else { return }
        applyCaptureConfiguration(
            sourceSize: targetSourceSize,
            targetPixelSize: targetPixelSize,
            stream: stream,
            generation: ticket.generation
        )
    }

    private func stopAfterExhaustedCaptureConfigurationRetries(
        sourceSize targetSourceSize: CGSize,
        targetPixelSize: TextFollowCaptureSizePolicy.PixelSize,
        stream: SCStream,
        generation expectedGeneration: UInt64
    ) {
        Task { @MainActor [weak self, weak stream] in
            guard let self, let stream else { return }
            self.performStopAfterExhaustedCaptureConfigurationRetries(
                sourceSize: targetSourceSize,
                targetPixelSize: targetPixelSize,
                stream: stream,
                generation: expectedGeneration
            )
        }
    }

    @MainActor
    private func performStopAfterExhaustedCaptureConfigurationRetries(
        sourceSize targetSourceSize: CGSize,
        targetPixelSize: TextFollowCaptureSizePolicy.PixelSize,
        stream: SCStream,
        generation expectedGeneration: UInt64
    ) {
        let expectedStreamIdentifier = ObjectIdentifier(stream)
        frameAssessmentPublicationLock.lock()
        stateLock.lock()
        guard generation == expectedGeneration,
              streamIdentifier == expectedStreamIdentifier,
              configurationUpdateTargetPixelSize == targetPixelSize,
              !failed,
              !specifications.isEmpty else {
            stateLock.unlock()
            frameAssessmentPublicationLock.unlock()
            return
        }
        failed = true
        let ruleIDs = specifications.map(\.ruleID)
        let failedStreamIdentifier = streamIdentifier
        pendingFreshStreamConfiguration = PendingFreshStreamConfiguration(
            sourceSize: targetSourceSize,
            targetPixelSize: targetPixelSize
        )
        streamIdentifier = nil
        streamStartupWatchdog.cancel()
        streamHeartbeat.cancel()
        streamInterruptionWatchdog.cancel()
        captureConfigurationWatchdog.cancel()
        configurationUpdateTargetPixelSize = nil
        configurationUpdateSourceSize = nil
        pendingConfigurationSourceSize = nil
        awaitedOutputPixelSize = nil
        stateLock.unlock()
        cancelPendingRecognitionWhileHoldingFramePublicationGate()
        let sequence = currentMailboxSequence
        frameAssessmentPublicationLock.unlock()

        deliver(TextFollowCaptureEvent(
            sessionID: id,
            generation: expectedGeneration,
            sequence: sequence,
            payload: .cleared(ruleIDs: ruleIDs, reason: .failed)
        ))
        detachFailedStream(matching: failedStreamIdentifier)
    }

    private func submit(
        _ input: FrameInput,
        invalidatesInFlight: Bool,
        expectedStreamIdentifier: ObjectIdentifier
    ) {
        // Keep generation validation and mailbox insertion in one lock order. A stop/reconnect
        // cannot cancel the mailbox and then have this old frame reinsert itself.
        stateLock.lock()
        guard TextFollowFrameSubmissionPolicy.accepts(
            currentGeneration: generation,
            inputGeneration: input.generation,
            activeStreamIdentifier: streamIdentifier,
            expectedStreamIdentifier: expectedStreamIdentifier,
            failed: failed,
            hasSpecifications: !specifications.isEmpty
        ) else {
            stateLock.unlock()
            return
        }
        mailboxLock.lock()
        let submission = invalidatesInFlight
            ? mailbox.submitInvalidatingInFlight(input)
            : mailbox.submit(input)
        let invalidationAction = invalidatesInFlight
            ? continuousInvalidation.recordInvalidation(generation: input.generation)
            : nil
        mailboxLock.unlock()
        stateLock.unlock()

        switch invalidationAction {
        case .some(.scanning):
            deliver(TextFollowCaptureEvent(
                sessionID: id,
                generation: input.generation,
                sequence: submission.sequence,
                payload: .scanning(ruleIDs: input.specifications.map(\.ruleID))
            ))
        case .some(.enterFailClosed):
            // A current-frame result still has to finish before per-text geometry is trustworthy.
            // Safe mode covers the full selected window; relaxed mode retains its last completed
            // placements. Continued frames keep replacing the mailbox but cannot revive scanning.
            deliver(TextFollowCaptureEvent(
                sessionID: id,
                generation: input.generation,
                sequence: submission.sequence,
                payload: .failClosed(ruleIDs: input.specifications.map(\.ruleID))
            ))
        case .some(.remainFailClosed), .none:
            break
        }
        if submission.shouldSchedule {
            scheduleRecognitionTurn()
        }
    }

    private func scheduleRecognitionTurn() {
        Self.recognitionSchedulerQueue.async { [weak self] in self?.processNextFrame() }
    }

    private func processNextFrame() {
        mailboxLock.lock()
        guard let item = mailbox.takeScheduledTurn() else {
            let shouldScheduleNext = mailbox.finishScheduledTurn()
            mailboxLock.unlock()
            if shouldScheduleNext { scheduleRecognitionTurn() }
            return
        }
        mailboxLock.unlock()

        let submitted = Self.recognitionWorkerPool.submit(
            { [weak self] workerLease in
                guard let self else { return }
                let outcome = autoreleasepool {
                    self.recognize(
                        item.value,
                        mailboxItem: item,
                        workerLease: workerLease
                    )
                }
                if case .retired = outcome { return }
                self.completeRecognitionTurn(item, outcome: outcome)
            },
            onRejected: { [weak self] in
                self?.completeRecognitionTurn(item, outcome: .failed)
            }
        )
        if !submitted {
            // The bounded pending queue should be unreachable with the supported rule count. If it
            // is exhausted, fail this logical turn closed instead of retaining it indefinitely.
            completeRecognitionTurn(item, outcome: .failed)
        }
    }

    private func completeRecognitionTurn(
        _ item: TextFollowLatestFrameMailbox<FrameInput>.Item,
        outcome: RecognitionOutcome
    ) {
        frameAssessmentPublicationLock.lock()
        mailboxLock.lock()
        let canPublish = mailbox.canPublish(item)
        if canPublish, case .success = outcome {
            continuousInvalidation.recordAuthoritativeCompletion(
                generation: item.value.generation
            )
        }
        let suppressProvisionalResult = continuousInvalidation.isFailClosed
        let shouldScheduleNext = mailbox.finishScheduledTurn()
        mailboxLock.unlock()

        stateLock.lock()
        let isCurrent = TextFollowRecognitionCompletionPolicy.isCurrent(
            currentGeneration: generation,
            inputGeneration: item.value.generation,
            sessionFailed: failed
        )
        stateLock.unlock()

        var payload: TextFollowCaptureEvent.Payload?
        var recognitionSucceeded = false
        var shouldRetryRecognitionFailure = false
        if isCurrent {
            switch outcome {
            case .success(let matches):
                recognitionSucceeded = canPublish
                if canPublish {
                    payload = .matches(matches)
                } else if !suppressProvisionalResult {
                    payload = .provisionalMatches(matches)
                }
            case .supersededBeforePerform:
                break
            case .failed:
                // A failed stale result says nothing about the newest frame. A failed current result
                // retains the exact-pixel baseline. Only a claimed bounded recovery invalidates it,
                // preventing repeated callbacks from bypassing the automatic retry limit.
                if canPublish {
                    shouldRetryRecognitionFailure = true
                    payload = .cleared(
                        ruleIDs: item.value.specifications.map(\.ruleID),
                        reason: .failed
                    )
                }
            case .retired:
                break
            }
        }
        frameAssessmentPublicationLock.unlock()

        // Requeue at the scheduler's tail before publishing. The bounded pool normally runs one
        // Vision worker; only a watchdog-retired orphan permits its single reserve worker to start.
        if shouldScheduleNext { scheduleRecognitionTurn() }
        if recognitionSucceeded {
            resetRecognitionFailureRetries(generation: item.value.generation)
        } else if shouldRetryRecognitionFailure {
            scheduleRecovery(
                .recognitionFailure,
                generation: item.value.generation,
                frameCursor: item.retryFrameCursor
            )
        }
        guard let payload else { return }
        deliver(TextFollowCaptureEvent(
            sessionID: id,
            generation: item.value.generation,
            sequence: item.sequence,
            frameTime: item.value.displayTime,
            payload: payload
        ))
    }

    private func recognize(
        _ input: FrameInput,
        mailboxItem: TextFollowLatestFrameMailbox<FrameInput>.Item,
        workerLease: TextFollowRecognitionWorkerLease
    ) -> RecognitionOutcome {
        guard let pixelBuffer = input.sampleBuffer.imageBuffer else { return .failed }
        let imageSize = CGSize(
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer)
        )
        guard let contentPixelRect = SharePreviewFrameGeometry.contentPixelRect(
            contentRectInPoints: input.contentRectInPoints,
            scaleFactor: input.scaleFactor,
            extent: CGRect(origin: .zero, size: imageSize)
        ), let appearanceScale = SharePreviewFrameGeometry.appearanceScale(
            scaleFactor: input.scaleFactor,
            contentScale: input.contentScale
        ) else { return .failed }

        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let languageConfiguration = TextFollowRecognitionLanguagePolicy.configuration(
            for: input.specifications.map { specification in
                (
                    matchMode: specification.fingerprint.matchMode,
                    pattern: specification.fingerprint.pattern
                )
            }
        )
        request.automaticallyDetectsLanguage = languageConfiguration.automaticallyDetectsLanguage
        request.recognitionLanguages = languageConfiguration.recognitionLanguages
        request.minimumTextHeight = 0
        request.customWords = input.specifications.compactMap { specification in
            specification.fingerprint.matchMode == .regex ? nil : specification.fingerprint.pattern
        }.prefix(64).map { $0 }

        recognitionRequestLock.lock()
        let watchdogKey = recognitionWatchdog.begin(
            generation: input.generation,
            epoch: mailboxItem.epoch
        )
        activeRecognitionRequest = ActiveRecognitionRequest(
            request: request,
            watchdogKey: watchdogKey
        )
        recognitionRequestLock.unlock()

        // An invalidating frame can arrive after this queue took the old item but before Vision
        // registered its request. Skip work that has not started yet. Once Vision is performing,
        // content changes never cancel it: letting that turn finish guarantees forward progress,
        // while the mailbox epoch still prevents its stale result from being published.
        frameAssessmentPublicationLock.lock()
        mailboxLock.lock()
        let shouldPerform = mailbox.canPublish(mailboxItem)
        mailboxLock.unlock()
        frameAssessmentPublicationLock.unlock()
        guard shouldPerform else {
            _ = finishActiveRecognition(request, key: watchdogKey)
            return .supersededBeforePerform
        }

        armRecognitionWatchdog(
            for: request,
            key: watchdogKey,
            workerLease: workerLease,
            mailboxItem: mailboxItem
        )

        let handler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        do { try handler.perform([request]) }
        catch {
            guard let timedOut = finishActiveRecognition(request, key: watchdogKey) else {
                return .retired
            }
            return timedOut ? .retired : .failed
        }
        guard let timedOut = finishActiveRecognition(request, key: watchdogKey),
              !timedOut else {
            return .retired
        }

        let blocks = (request.results ?? []).map { observation in
            TextFollowRecognizedBlock(
                candidates: observation.topCandidates(10).map(\.string),
                normalizedBoundingBox: observation.boundingBox
            )
        }
        var result: [UUID: [UnitRect]] = [:]
        result.reserveCapacity(input.specifications.count)
        let regexDeadline = TextPatternMatcher.deadline(
            afterNanoseconds: TextFollowFrameGeometry.frameRegexExecutionLimitNanoseconds
        )
        for specification in input.specifications {
            guard let rects = TextFollowFrameGeometry.matchingNormalizedRects(
                blocks: blocks,
                matcher: specification.matcher,
                imageSize: imageSize,
                contentPixelRect: contentPixelRect,
                paddingPixels: CGFloat(specification.padding) * appearanceScale,
                regexDeadlineUptimeNanoseconds: regexDeadline
            ) else { return .failed }
            result[specification.ruleID] = rects
        }
        return .success(result)
    }

    private func clear(for stream: SCStream, reason: TextFollowCaptureClearReason) {
        guard let snapshot = stateSnapshot(for: stream) else { return }
        // Every stream callback enters through frameAssessmentPublicationLock, so cancellation and
        // the resulting clear event are one publication-barrier transition.
        cancelPendingRecognitionWhileHoldingFramePublicationGate()
        // The next valid callback must retry OCR even if ScreenCaptureKit reports an empty dirty
        // list. Retaining the prior baseline here would leave sourceUnavailable stuck forever.
        invalidateFrameFingerprintBaseline(generation: snapshot.generation)
        let sequence = currentMailboxSequence
        deliver(TextFollowCaptureEvent(
            sessionID: id,
            generation: snapshot.generation,
            sequence: sequence,
            payload: .cleared(
                ruleIDs: snapshot.specifications.map(\.ruleID),
                reason: reason
            )
        ))
    }

    private func publishFailure(
        for stream: SCStream? = nil,
        error: Error? = nil,
        expectedStartupWatchdogKey: TextFollowStreamStartupWatchdogKey? = nil,
        expectedInterruptionWatchdogKey: TextFollowStreamStartupWatchdogKey? = nil
    ) {
        // The error is intentionally not surfaced: future system descriptions may contain a
        // source title or other private context. Consumers receive only a generic failed state.
        _ = error
        frameAssessmentPublicationLock.lock()
        stateLock.lock()
        if let stream, streamIdentifier != ObjectIdentifier(stream) {
            stateLock.unlock()
            frameAssessmentPublicationLock.unlock()
            return
        }
        if let expectedStartupWatchdogKey {
            guard streamStartupWatchdog.expire(expectedStartupWatchdogKey) else {
                stateLock.unlock()
                frameAssessmentPublicationLock.unlock()
                return
            }
        } else if let expectedInterruptionWatchdogKey {
            guard streamInterruptionWatchdog.expire(expectedInterruptionWatchdogKey) else {
                stateLock.unlock()
                frameAssessmentPublicationLock.unlock()
                return
            }
        } else {
            streamStartupWatchdog.cancel()
        }
        failed = true
        let currentGeneration = generation
        let ruleIDs = specifications.map(\.ruleID)
        let failedStreamIdentifier = stream.map(ObjectIdentifier.init)
        preservePendingConfigurationForFreshStream()
        if let stream, streamIdentifier == ObjectIdentifier(stream) { streamIdentifier = nil }
        streamStartupWatchdog.cancel()
        streamHeartbeat.cancel()
        streamInterruptionWatchdog.cancel()
        captureConfigurationWatchdog.cancel()
        configurationUpdateTargetPixelSize = nil
        configurationUpdateSourceSize = nil
        pendingConfigurationSourceSize = nil
        awaitedOutputPixelSize = nil
        stateLock.unlock()
        cancelPendingRecognitionWhileHoldingFramePublicationGate()
        let sequence = currentMailboxSequence
        frameAssessmentPublicationLock.unlock()
        deliver(TextFollowCaptureEvent(
            sessionID: id,
            generation: currentGeneration,
            sequence: sequence,
            payload: .cleared(ruleIDs: ruleIDs, reason: .failed)
        ))
        scheduleStreamFailureRecovery(
            generation: currentGeneration,
            failedStreamIdentifier: failedStreamIdentifier,
            shouldRetry: !ruleIDs.isEmpty
        )
    }

    /// Requires stateLock. A failed stream must not forget a resize transition and briefly accept
    /// its old surface after recovery.
    private func preservePendingConfigurationForFreshStream() {
        guard let configurationUpdateTargetPixelSize,
              let configurationUpdateSourceSize else { return }
        pendingFreshStreamConfiguration = PendingFreshStreamConfiguration(
            sourceSize: configurationUpdateSourceSize,
            targetPixelSize: configurationUpdateTargetPixelSize
        )
    }

    private func stateSnapshot(
        for stream: SCStream
    ) -> (generation: UInt64, specifications: [TextFollowProcessingSpecification])? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard streamIdentifier == ObjectIdentifier(stream), !specifications.isEmpty else { return nil }
        return (generation, specifications)
    }

    /// Requires frameAssessmentPublicationLock. All mailbox invalidations participate in the same
    /// gate as MainActor's authoritative result commit.
    private func cancelPendingRecognitionWhileHoldingFramePublicationGate() {
        mailboxLock.lock()
        let newEpoch = mailbox.cancel()
        continuousInvalidation.reset()
        mailboxLock.unlock()
        cancelActiveRecognition(olderThan: newEpoch)
    }

    private func cancelActiveRecognition(olderThan epoch: UInt64) {
        recognitionRequestLock.lock()
        let request = activeRecognitionRequest.flatMap { active in
            active.watchdogKey.epoch < epoch ? active.request : nil
        }
        recognitionRequestLock.unlock()
        request?.cancel()
    }

    private func armRecognitionWatchdog(
        for request: VNRecognizeTextRequest,
        key: TextFollowRecognitionWatchdogKey,
        workerLease: TextFollowRecognitionWorkerLease,
        mailboxItem: TextFollowLatestFrameMailbox<FrameInput>.Item
    ) {
        let delay = DispatchTimeInterval.nanoseconds(Int(Self.recognitionTimeoutNanoseconds))
        Self.watchdogQueue.asyncAfter(deadline: .now() + delay) { [weak self, weak request] in
            guard let self, let request else { return }
            self.timeoutRecognitionIfActive(
                request,
                key: key,
                workerLease: workerLease,
                mailboxItem: mailboxItem
            )
        }
    }

    private func timeoutRecognitionIfActive(
        _ request: VNRecognizeTextRequest,
        key: TextFollowRecognitionWatchdogKey,
        workerLease: TextFollowRecognitionWorkerLease,
        mailboxItem: TextFollowLatestFrameMailbox<FrameInput>.Item
    ) {
        recognitionRequestLock.lock()
        let shouldRetire = activeRecognitionRequest?.request === request
            && activeRecognitionRequest?.watchdogKey == key
            && recognitionWatchdog.markTimedOut(key)
        if shouldRetire {
            _ = recognitionWatchdog.finish(key)
            activeRecognitionRequest = nil
        }
        recognitionRequestLock.unlock()
        guard shouldRetire else { return }

        // Never hold the request lock while entering the global pool or publication gate. The
        // physical worker remains accounted for until `perform` really returns, while its logical
        // mailbox turn completes now so the reserve worker can process a newer frame/window.
        _ = Self.recognitionWorkerPool.markTimedOut(workerLease)
        request.cancel()
        completeRecognitionTurn(mailboxItem, outcome: .failed)
    }

    private func finishActiveRecognition(
        _ request: VNRecognizeTextRequest,
        key: TextFollowRecognitionWatchdogKey
    ) -> Bool? {
        recognitionRequestLock.lock()
        defer { recognitionRequestLock.unlock() }
        guard activeRecognitionRequest?.request === request,
              activeRecognitionRequest?.watchdogKey == key else { return nil }
        let timedOut = recognitionWatchdog.finish(key)
        activeRecognitionRequest = nil
        return timedOut
    }

    private func armFirstUsableFrameWatchdog(
        for stream: SCStream,
        key: TextFollowStreamStartupWatchdogKey
    ) {
        let delay = DispatchTimeInterval.nanoseconds(Int(Self.firstUsableFrameTimeoutNanoseconds))
        Self.watchdogQueue.asyncAfter(deadline: .now() + delay) { [weak self, weak stream] in
            guard let self, let stream else { return }
            self.publishFailure(
                for: stream,
                expectedStartupWatchdogKey: key
            )
        }
    }

    /// Called while the publication gate is held by a stream callback. Idle proves callback
    /// liveness but does not prove that a preceding blank/suspended source became usable again.
    private func observeStreamCallback(
        _ stream: SCStream,
        generation expectedGeneration: UInt64,
        clearsInterruption: Bool
    ) {
        let now = DispatchTime.now().uptimeNanoseconds
        stateLock.lock()
        guard streamIdentifier == ObjectIdentifier(stream),
              generation == expectedGeneration,
              !failed else {
            stateLock.unlock()
            return
        }
        if clearsInterruption { streamInterruptionWatchdog.cancel() }
        _ = streamHeartbeat.observe(
            generation: expectedGeneration,
            nowUptimeNanoseconds: now
        )
        stateLock.unlock()
    }

    private func beginTransientInterruptionGrace(
        for stream: SCStream,
        generation expectedGeneration: UInt64
    ) {
        stateLock.lock()
        guard streamIdentifier == ObjectIdentifier(stream),
              generation == expectedGeneration,
              !failed else {
            stateLock.unlock()
            return
        }
        guard streamInterruptionWatchdog.activeKey == nil else {
            stateLock.unlock()
            return
        }
        // The interruption deadline must own liveness for this episode. A nearly-expired heartbeat
        // from the preceding usable frame must not fail the stream before the full grace elapses.
        // The next authoritative usable callback cancels this key and begins a new heartbeat.
        streamHeartbeat.cancel()
        let key = streamInterruptionWatchdog.begin(generation: expectedGeneration)
        stateLock.unlock()

        let delay = DispatchTimeInterval.nanoseconds(
            Int(Self.transientInterruptionGraceNanoseconds)
        )
        Self.watchdogQueue.asyncAfter(deadline: .now() + delay) { [weak self, weak stream] in
            guard let self, let stream else { return }
            self.publishFailure(
                for: stream,
                expectedInterruptionWatchdogKey: key
            )
        }
    }

    private func armStreamHeartbeat(
        for stream: SCStream,
        key: TextFollowStreamHeartbeatKey,
        afterNanoseconds: UInt64 = TextFollowCaptureSession.streamHeartbeatTimeoutNanoseconds
    ) {
        let delay = DispatchTimeInterval.nanoseconds(Int(afterNanoseconds))
        Self.watchdogQueue.asyncAfter(deadline: .now() + delay) { [weak self, weak stream] in
            guard let self, let stream else { return }
            self.evaluateStreamHeartbeat(for: stream, key: key)
        }
    }

    private func evaluateStreamHeartbeat(
        for stream: SCStream,
        key: TextFollowStreamHeartbeatKey
    ) {
        let expectedStreamIdentifier = ObjectIdentifier(stream)
        let now = DispatchTime.now().uptimeNanoseconds
        frameAssessmentPublicationLock.lock()
        stateLock.lock()
        guard streamIdentifier == expectedStreamIdentifier,
              generation == key.generation,
              !failed else {
            stateLock.unlock()
            frameAssessmentPublicationLock.unlock()
            return
        }

        switch streamHeartbeat.evaluate(
            key,
            nowUptimeNanoseconds: now,
            timeoutNanoseconds: Self.streamHeartbeatTimeoutNanoseconds
        ) {
        case .stale:
            stateLock.unlock()
            frameAssessmentPublicationLock.unlock()
        case .rearm(let remaining):
            stateLock.unlock()
            frameAssessmentPublicationLock.unlock()
            armStreamHeartbeat(for: stream, key: key, afterNanoseconds: remaining)
        case .expired:
            // Claim the exact stream attempt while the publication gate is held. A callback racing
            // the deadline can either refresh first or be rejected after this fail-closed commit.
            failed = true
            let currentGeneration = generation
            let ruleIDs = specifications.map(\.ruleID)
            let failedStreamIdentifier = streamIdentifier
            preservePendingConfigurationForFreshStream()
            streamIdentifier = nil
            streamStartupWatchdog.cancel()
            streamInterruptionWatchdog.cancel()
            captureConfigurationWatchdog.cancel()
            configurationUpdateTargetPixelSize = nil
            configurationUpdateSourceSize = nil
            pendingConfigurationSourceSize = nil
            awaitedOutputPixelSize = nil
            stateLock.unlock()
            cancelPendingRecognitionWhileHoldingFramePublicationGate()
            let sequence = currentMailboxSequence
            frameAssessmentPublicationLock.unlock()

            deliver(TextFollowCaptureEvent(
                sessionID: id,
                generation: currentGeneration,
                sequence: sequence,
                payload: .cleared(ruleIDs: ruleIDs, reason: .failed)
            ))
            scheduleStreamFailureRecovery(
                generation: currentGeneration,
                failedStreamIdentifier: failedStreamIdentifier,
                shouldRetry: !ruleIDs.isEmpty
            )
        }
    }

    /// Called while the publication gate is held by the stream callback.
    private func markStreamUsable(_ stream: SCStream, generation: UInt64) {
        let now = DispatchTime.now().uptimeNanoseconds
        stateLock.lock()
        guard streamIdentifier == ObjectIdentifier(stream),
              self.generation == generation,
              !failed else {
            stateLock.unlock()
            return
        }
        let completedStartup = streamStartupWatchdog.complete(generation: generation)
        streamInterruptionWatchdog.cancel()
        let heartbeatKey: TextFollowStreamHeartbeatKey?
        if streamHeartbeat.activeKey == nil {
            heartbeatKey = streamHeartbeat.begin(
                generation: generation,
                nowUptimeNanoseconds: now
            )
        } else {
            _ = streamHeartbeat.observe(
                generation: generation,
                nowUptimeNanoseconds: now
            )
            heartbeatKey = nil
        }
        let completedRequestedSurface = pendingFreshStreamConfiguration == nil
        stateLock.unlock()
        if completedStartup { resetStreamFailureRetries(generation: generation) }
        if completedRequestedSurface {
            // A fresh stream reached its requested surface. Resize failure history no longer needs
            // to constrain a later independent transition in this generation.
            resetConfigurationFailureRetries(generation: generation)
        }
        if let heartbeatKey { armStreamHeartbeat(for: stream, key: heartbeatKey) }
    }

    private func resetRecoveryCursors(generation: UInt64) {
        recoveryLock.lock()
        recognitionFailureRetries.reset(generation: generation)
        streamFailureRetries.reset(generation: generation)
        configurationFailureRetries.reset(generation: generation)
        recoveryLock.unlock()
    }

    private func resetRecognitionFailureRetries(generation: UInt64) {
        recoveryLock.lock()
        recognitionFailureRetries.reset(generation: generation)
        recoveryLock.unlock()
    }

    private func resetStreamFailureRetries(generation: UInt64) {
        recoveryLock.lock()
        streamFailureRetries.reset(generation: generation)
        recoveryLock.unlock()
    }

    private func resetConfigurationFailureRetries(generation: UInt64) {
        recoveryLock.lock()
        configurationFailureRetries.reset(generation: generation)
        recoveryLock.unlock()
    }

    private func scheduleRecovery(
        _ kind: RecoveryKind,
        generation: UInt64,
        frameCursor: TextFollowRetryFrameCursor? = nil
    ) {
        recoveryLock.lock()
        let result: TextFollowRetryScheduleResult
        switch kind {
        case .recognitionFailure:
            result = recognitionFailureRetries.schedule(
                generation: generation,
                frameCursor: frameCursor,
                policy: .recognitionFailure
            )
        case .streamFailure:
            result = streamFailureRetries.schedule(
                generation: generation,
                policy: .streamFailure
            )
        }
        recoveryLock.unlock()
        guard case .scheduled(let ticket) = result else {
            if case .exhausted = result,
               kind == .recognitionFailure,
               let frameCursor {
                stopAfterExhaustedRecognitionRetries(
                    generation: generation,
                    frameCursor: frameCursor
                )
            }
            return
        }

        Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: ticket.delayNanoseconds) }
            catch { return }
            self?.performScheduledRecovery(kind, ticket: ticket)
        }
    }

    private func stopAfterExhaustedRecognitionRetries(
        generation: UInt64,
        frameCursor: TextFollowRetryFrameCursor
    ) {
        Task { @MainActor [weak self] in
            self?.performStopAfterExhaustedRecognitionRetries(
                generation: generation,
                frameCursor: frameCursor
            )
        }
    }

    @MainActor
    private func performStopAfterExhaustedRecognitionRetries(
        generation: UInt64,
        frameCursor: TextFollowRetryFrameCursor
    ) {
        frameAssessmentPublicationLock.lock()
        stateLock.lock()
        mailboxLock.lock()
        let isCurrentFrame = mailbox.isCurrent(frameCursor)
        mailboxLock.unlock()
        guard self.generation == generation,
              !failed,
              !specifications.isEmpty,
              isCurrentFrame else {
            stateLock.unlock()
            frameAssessmentPublicationLock.unlock()
            return
        }
        failed = true
        let failedStreamIdentifier = streamIdentifier
        preservePendingConfigurationForFreshStream()
        streamIdentifier = nil
        streamStartupWatchdog.cancel()
        streamHeartbeat.cancel()
        streamInterruptionWatchdog.cancel()
        captureConfigurationWatchdog.cancel()
        configurationUpdateTargetPixelSize = nil
        configurationUpdateSourceSize = nil
        pendingConfigurationSourceSize = nil
        awaitedOutputPixelSize = nil
        stateLock.unlock()
        frameAssessmentPublicationLock.unlock()
        detachFailedStream(matching: failedStreamIdentifier)
    }

    private func scheduleStreamFailureRecovery(
        generation: UInt64,
        failedStreamIdentifier: ObjectIdentifier?,
        shouldRetry: Bool
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.detachFailedStream(matching: failedStreamIdentifier)
            if shouldRetry { self.scheduleRecovery(.streamFailure, generation: generation) }
        }
    }

    @MainActor
    private func detachFailedStream(matching failedStreamIdentifier: ObjectIdentifier?) {
        guard let failedStreamIdentifier,
              let stream,
              ObjectIdentifier(stream) == failedStreamIdentifier else { return }
        stopStream()
    }

    private func consumeRecoveryTicket(
        _ ticket: TextFollowRetryTicket,
        kind: RecoveryKind
    ) -> Bool {
        recoveryLock.lock()
        defer { recoveryLock.unlock() }
        switch kind {
        case .recognitionFailure:
            return recognitionFailureRetries.consume(ticket)
        case .streamFailure:
            return streamFailureRetries.consume(ticket)
        }
    }

    @MainActor
    private func performScheduledRecovery(
        _ kind: RecoveryKind,
        ticket: TextFollowRetryTicket
    ) {
        frameAssessmentPublicationLock.lock()
        stateLock.lock()
        var canRetry = generation == ticket.generation
            && !specifications.isEmpty
            && (kind == .streamFailure ? failed : !failed)
        if kind == .recognitionFailure, let frameCursor = ticket.frameCursor {
            mailboxLock.lock()
            canRetry = canRetry && mailbox.isCurrent(frameCursor)
            mailboxLock.unlock()
        }
        guard consumeRecoveryTicket(ticket, kind: kind) else {
            stateLock.unlock()
            frameAssessmentPublicationLock.unlock()
            return
        }
        guard canRetry else {
            stateLock.unlock()
            frameAssessmentPublicationLock.unlock()
            return
        }
        failed = false
        preservePendingConfigurationForFreshStream()
        streamIdentifier = nil
        streamStartupWatchdog.cancel()
        streamHeartbeat.cancel()
        streamInterruptionWatchdog.cancel()
        captureConfigurationWatchdog.cancel()
        configurationUpdateTargetPixelSize = nil
        configurationUpdateSourceSize = nil
        pendingConfigurationSourceSize = nil
        awaitedOutputPixelSize = nil
        let currentGeneration = generation
        let ruleIDs = specifications.map(\.ruleID)
        stateLock.unlock()
        cancelPendingRecognitionWhileHoldingFramePublicationGate()
        invalidateFrameFingerprintBaseline(generation: currentGeneration)
        let sequence = currentMailboxSequence
        frameAssessmentPublicationLock.unlock()

        stopStream()
        guard startStream() else { return }
        deliver(TextFollowCaptureEvent(
            sessionID: id,
            generation: currentGeneration,
            sequence: sequence,
            payload: .scanning(ruleIDs: ruleIDs)
        ))
    }

    func withFramePublicationGate<Result>(
        sequence: UInt64,
        _ body: (_ superseded: Bool) -> Result
    ) -> Result {
        frameAssessmentPublicationLock.lock()
        defer { frameAssessmentPublicationLock.unlock() }
        mailboxLock.lock()
        let superseded = sequence < mailbox.latestInvalidatingSequence
        mailboxLock.unlock()
        return body(superseded)
    }

    private func assessFrameChange(
        fingerprint: TextFollowPixelFingerprint?,
        metadataReportsChange: Bool,
        generation: UInt64
    ) -> TextFollowFrameProcessingAssessment {
        frameInvalidationLock.lock()
        defer { frameInvalidationLock.unlock() }
        return frameChangeDetector.assess(
            fingerprint: fingerprint,
            metadataReportsChange: metadataReportsChange,
            generation: generation
        )
    }

    private func requiresFrameFingerprint(
        metadataReportsChange: Bool,
        generation: UInt64
    ) -> Bool {
        frameInvalidationLock.lock()
        defer { frameInvalidationLock.unlock() }
        return frameChangeDetector.requiresFingerprint(
            metadataReportsChange: metadataReportsChange,
            generation: generation
        )
    }

    private func invalidateFrameFingerprintBaseline(generation: UInt64) {
        frameInvalidationLock.lock()
        frameChangeDetector.invalidateBaseline(generation: generation)
        frameInvalidationLock.unlock()
    }

    private var currentMailboxSequence: UInt64 {
        mailboxLock.lock()
        defer { mailboxLock.unlock() }
        return mailbox.latestSequence
    }

    private static func configuration(
        sourceSize: CGSize,
        filter: SCContentFilter,
        outputPixelSize: TextFollowCaptureSizePolicy.PixelSize? = nil
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let scale = max(1, CGFloat(filter.pointPixelScale))
        let resolvedPixelSize = outputPixelSize
            ?? TextFollowCaptureSizePolicy.outputPixelSize(
                sourceSize: sourceSize,
                pointPixelScale: scale
            )
            ?? TextFollowCaptureSizePolicy.PixelSize(width: 2, height: 2)

        configuration.width = resolvedPixelSize.width
        configuration.height = resolvedPixelSize.height
        // Damage callbacks run faster than Vision. The latest-frame mailbox still bounds OCR to
        // one request at a time, while 15 Hz reduces the interval before the desktop safety cover
        // notices navigation or a scroll.
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = TextFollowCaptureSizePolicy.streamQueueDepth
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.capturesAudio = false
        configuration.shouldBeOpaque = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        // Independent windows can otherwise be captured at a nominal backing resolution before
        // being scaled into the requested surface, irreversibly discarding small glyph detail.
        configuration.captureResolution = .best
        configuration.streamName = "BlurFollow Text Follow"
        // Child windows can extend outside the tracked parent's CGWindow bounds. Excluding them
        // keeps Vision's normalized content rectangle aligned with WindowTracker's parent frame.
        if #available(macOS 14.2, *) { configuration.includeChildWindows = false }
        return configuration
    }

    private static func attachments(from sampleBuffer: CMSampleBuffer) -> [SCStreamFrameInfo: Any]? {
        guard let array = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]] else { return nil }
        return array.first
    }

    private static func rect(from value: Any?) -> CGRect? {
        if let rect = value as? CGRect { return rect }
        if let value = value as? NSValue { return value.rectValue }
        if let dictionary = value as? NSDictionary {
            return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
        }
        return nil
    }

    private static func rects(from value: Any?) -> [CGRect]? {
        if let rects = value as? [CGRect] { return rects }
        if let values = value as? [NSValue] { return values.map(\.rectValue) }
        guard let values = value as? NSArray else { return nil }
        var rects: [CGRect] = []
        rects.reserveCapacity(values.count)
        for value in values {
            guard let rect = rect(from: value) else { return nil }
            rects.append(rect)
        }
        return rects
    }

    private static func scalar(from value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        return nil
    }

    private static func unsignedInteger(from value: Any?) -> UInt64? {
        if let value = value as? UInt64 { return value }
        if let value = value as? UInt { return UInt64(value) }
        if let number = value as? NSNumber, number.doubleValue >= 0 {
            return number.uint64Value
        }
        return nil
    }
}
