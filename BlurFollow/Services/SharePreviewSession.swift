import AppKit
import Combine
import CoreImage
import CoreMedia
import CoreVideo
import QuartzCore
import ScreenCaptureKit

/// A layer-backed pixel surface for Share Preview. Replacing `CALayer.contents` avoids routing the
/// 30 fps stream through SwiftUI observation and view diffing.
@MainActor
final class SharePreviewPixelView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.masksToBounds = true
        layer?.actions = ["contents": NSNull()]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present(_ image: CGImage?) {
        layer?.contents = image
    }
}

/// Owns pixels independently from the session's semantic state. The presenter updates only its
/// attached AppKit surface, so every frame does not rebuild Share Preview's SwiftUI controls.
@MainActor
final class SharePreviewFramePresenter {
    private(set) var image: CGImage?
    private weak var surface: SharePreviewPixelView?

    func present(_ image: CGImage?) {
        if image == nil, self.image == nil { return }
        self.image = image
        surface?.present(image)
    }

    func attach(_ surface: SharePreviewPixelView) {
        self.surface = surface
        surface.present(image)
    }
}

@MainActor
final class SharePreviewSession: NSObject, ObservableObject, SCStreamDelegate {
    let framePresenter = SharePreviewFramePresenter()

    /// Kept as a read-only convenience for diagnostics and tests. The live view attaches directly
    /// to `framePresenter` so pixel delivery does not invalidate the session's SwiftUI hierarchy.
    var frameImage: NSImage? {
        guard let image = framePresenter.image else { return nil }
        return NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }

    @Published private(set) var hasFrame = false
    @Published private(set) var frameIsCovered = true
    @Published private(set) var isPreparing = false
    @Published private(set) var isRunning = false
    @Published private(set) var sourceName = String(localized: "No source selected")
    @Published private(set) var sourceWindowID: CGWindowID?
    @Published private(set) var appliedMaskCount = 0
    @Published private(set) var hasRenderableConfiguration = false
    @Published private(set) var relevantTextFollowRuleCount = 0
    @Published private(set) var dynamicRuleNeedsAttention = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var savedDataNeedsReview = false
    /// Changes whenever a user-visible condition requires the mask positions to be checked again.
    @Published private(set) var reviewRevision: UInt64 = 0

    var hasRenderablePreview: Bool {
        !savedDataNeedsReview
            && isRunning && hasRenderableConfiguration && hasFrame && !frameIsCovered
    }

    private let store: MaskStore
    private let tracker: WindowTracker
    private let textFollow: TextFollowCoordinator
    private let onAccessDenied: @MainActor () -> Void
    private let processor = SharePreviewFrameProcessor()
    private var stream: SCStream?
    private var cancellables: Set<AnyCancellable> = []
    private var freshnessTimer: Timer?
    private var lastFrameDate = Date.distantPast
    private var captureGeneration: UInt64 = 0
    private var activeMaskRevision: UInt64 = 0
    private var sourceBundleIdentifier = ""
    private var sourceApplicationName = ""
    private var sourceProcessID: pid_t = 0
    private var activeMaskSnapshot: ActiveMaskSnapshot?

    private struct ActiveMaskSnapshot: Equatable {
        struct Appearance: Equatable {
            let id: UUID
            let normalizedRect: UnitRect
            let style: MaskStyle
            let strength: Double
            let granularity: Double
            let tint: MaskTint
            let borderEnabled: Bool
            let cornerRadius: Double
            let isEnabled: Bool

            init(_ region: MaskRegion) {
                id = region.id
                normalizedRect = region.normalizedRect
                style = region.style
                strength = region.strength
                granularity = region.granularity
                tint = region.tint
                borderEnabled = region.borderEnabled
                cornerRadius = region.cornerRadius
                isEnabled = region.isEnabled
            }
        }

        let appearances: [Appearance]
        let savedDataNeedsReview: Bool
        let requiresFullCover: Bool
        let hasRenderableConfiguration: Bool
        let relevantTextFollowRuleCount: Int
        let dynamicRuleNeedsAttention: Bool

        init(
            regions: [MaskRegion],
            savedDataNeedsReview: Bool,
            requiresFullCover: Bool,
            hasRenderableConfiguration: Bool,
            relevantTextFollowRuleCount: Int,
            dynamicRuleNeedsAttention: Bool
        ) {
            appearances = regions.map(Appearance.init)
            self.savedDataNeedsReview = savedDataNeedsReview
            self.requiresFullCover = requiresFullCover
            self.hasRenderableConfiguration = hasRenderableConfiguration
            self.relevantTextFollowRuleCount = relevantTextFollowRuleCount
            self.dynamicRuleNeedsAttention = dynamicRuleNeedsAttention
        }
    }

    init(
        store: MaskStore,
        tracker: WindowTracker,
        textFollow: TextFollowCoordinator,
        onAccessDenied: @escaping @MainActor () -> Void = {}
    ) {
        self.store = store
        self.tracker = tracker
        self.textFollow = textFollow
        self.onAccessDenied = onAccessDenied
        super.init()

        processor.onDelivery = { [weak self] delivery in
            guard let self else { return }
            switch delivery {
            case .frame(let image, let generation, let maskRevision, let isBlocked):
                guard self.captureGeneration == generation,
                      self.activeMaskRevision == maskRevision,
                      self.sourceWindowID != nil else { return }
                self.setFrameImage(image)
                if self.frameIsCovered != isBlocked {
                    self.invalidateReview()
                    self.frameIsCovered = isBlocked
                }
                self.lastFrameDate = Date()
            case .heartbeat(let generation, let maskRevision):
                guard self.captureGeneration == generation,
                      self.activeMaskRevision == maskRevision,
                      self.sourceWindowID != nil else { return }
                self.lastFrameDate = Date()
            case .clear(let generation, let maskRevision):
                guard self.captureGeneration == generation,
                      self.activeMaskRevision == maskRevision else { return }
                if self.hasFrame || !self.frameIsCovered { self.invalidateReview() }
                self.setFrameImage(nil)
                if !self.frameIsCovered { self.frameIsCovered = true }
            }
        }

        processor.onFirstSourceFrame = { [weak self] generation in
            guard let self,
                  self.captureGeneration == generation,
                  let sourceIdentity = self.sourceTextFollowIdentity else { return }
            self.textFollow.requestFreshFrame(for: sourceIdentity)
        }

        Publishers.CombineLatest3(
            store.$regions,
            store.$recoveryIssue,
            textFollow.$sharePreviewRevision
        ).sink { [weak self] regions, recoveryIssue, _ in
            self?.updateProcessor(regions: regions, recoveryIssue: recoveryIssue)
        }.store(in: &cancellables)

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.clearStaleFrameIfNeeded() }
        }
        RunLoop.main.add(timer, forMode: .common)
        freshnessTimer = timer
    }

    func start(_ selection: PickedWindow) async {
        captureGeneration &+= 1
        let generation = captureGeneration
        let previousStream = detachCurrentCapture()
        if let previousStream {
            try? await stopCapture(previousStream)
        }
        // Another start/stop may have taken ownership while the old stream was stopping.
        guard captureGeneration == generation else { return }

        isPreparing = true
        errorMessage = nil
        // The preview window itself may be shared. Never echo a source title here: document names,
        // mail subjects, customer names, and URLs commonly appear in window titles.
        sourceName = selection.candidate.applicationName
        sourceWindowID = selection.candidate.id
        sourceBundleIdentifier = selection.candidate.bundleIdentifier
        sourceApplicationName = selection.candidate.applicationName
        sourceProcessID = selection.candidate.processID
        lastFrameDate = .distantPast
        setFrameImage(nil)
        if !frameIsCovered { frameIsCovered = true }

        let activeMasks = resolveActiveMasks(
            regions: store.regions,
            needsReview: store.recoveryIssue != nil
        )
        if appliedMaskCount != activeMasks.regions.count {
            appliedMaskCount = activeMasks.regions.count
        }
        if hasRenderableConfiguration != activeMasks.hasRenderableConfiguration {
            hasRenderableConfiguration = activeMasks.hasRenderableConfiguration
        }
        relevantTextFollowRuleCount = activeMasks.relevantTextFollowRuleCount
        dynamicRuleNeedsAttention = activeMasks.dynamicRuleNeedsAttention
        activeMaskSnapshot = ActiveMaskSnapshot(
            regions: activeMasks.regions,
            savedDataNeedsReview: store.recoveryIssue != nil,
            requiresFullCover: activeMasks.requiresFullCover,
            hasRenderableConfiguration: activeMasks.hasRenderableConfiguration,
            relevantTextFollowRuleCount: activeMasks.relevantTextFollowRuleCount,
            dynamicRuleNeedsAttention: activeMasks.dynamicRuleNeedsAttention
        )

        let configuration = Self.configuration(for: selection)
        let newStream = SCStream(filter: selection.filter, configuration: configuration, delegate: self)

        // Retain and authorize the stream before awaiting startCapture. MainActor methods can be
        // re-entered while awaiting; generation + stream identity prevent A's frames using B's masks.
        stream = newStream
        activeMaskRevision = processor.activate(
            stream: newStream,
            generation: generation,
            regions: activeMasks.regions,
            requiresFullCover: activeMasks.requiresFullCover,
            hasRenderableConfiguration: activeMasks.hasRenderableConfiguration,
            relevantTextFollowRuleCount: activeMasks.relevantTextFollowRuleCount,
            minimumCompletedTextFollowFrameTime: activeMasks.minimumCompletedTextFollowFrameTime,
            maximumCompletedTextFollowFrameTime: activeMasks.maximumCompletedTextFollowFrameTime
        )

        do {
            try newStream.addStreamOutput(
                processor,
                type: .screen,
                sampleHandlerQueue: SharePreviewFrameProcessor.queue
            )
            try await startCapture(newStream)
            guard captureGeneration == generation, stream === newStream else {
                try? await stopCapture(newStream)
                return
            }
            isRunning = true
            isPreparing = false
        } catch {
            guard captureGeneration == generation, stream === newStream else { return }
            if ScreenCapturePermission.isUserDeclinedError(error) {
                onAccessDenied()
            }
            processor.deactivate()
            activeMaskSnapshot = nil
            stream = nil
            setFrameImage(nil)
            if !frameIsCovered { frameIsCovered = true }
            errorMessage = error.localizedDescription
            isPreparing = false
            isRunning = false
        }
    }

    func stop() async {
        captureGeneration &+= 1
        let stopGeneration = captureGeneration
        let oldStream = detachCurrentCapture()

        if let oldStream {
            do {
                try await stopCapture(oldStream)
            } catch where captureGeneration == stopGeneration {
                errorMessage = error.localizedDescription
            } catch {
                // A newer operation owns the UI state; ignore an obsolete stream's stop result.
            }
        }
    }

    private func detachCurrentCapture() -> SCStream? {
        invalidateReview()
        processor.deactivate()
        activeMaskRevision = 0
        activeMaskSnapshot = nil
        let oldStream = stream
        stream = nil
        isPreparing = false
        isRunning = false
        setFrameImage(nil)
        if !frameIsCovered { frameIsCovered = true }
        sourceWindowID = nil
        sourceBundleIdentifier = ""
        sourceApplicationName = ""
        sourceProcessID = 0
        appliedMaskCount = 0
        hasRenderableConfiguration = false
        relevantTextFollowRuleCount = 0
        dynamicRuleNeedsAttention = false
        sourceName = String(localized: "No source selected")
        return oldStream
    }

    nonisolated func stream(_ stoppedStream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stoppedStream else { return }
            if ScreenCapturePermission.isUserDeclinedError(error) {
                self.onAccessDenied()
            }
            self.captureGeneration &+= 1
            self.processor.deactivate()
            self.activeMaskSnapshot = nil
            self.stream = nil
            self.setFrameImage(nil)
            if !self.frameIsCovered { self.frameIsCovered = true }
            self.isPreparing = false
            self.isRunning = false
            self.sourceWindowID = nil
            self.sourceBundleIdentifier = ""
            self.sourceApplicationName = ""
            self.sourceProcessID = 0
            self.appliedMaskCount = 0
            self.hasRenderableConfiguration = false
            self.relevantTextFollowRuleCount = 0
            self.dynamicRuleNeedsAttention = false
            self.errorMessage = error.localizedDescription
            self.invalidateReview()
        }
    }

    private struct MatchingWindowPins {
        let regions: [MaskRegion]
        let requiresFullCover: Bool
    }

    private func matchingRegions(in regions: [MaskRegion]) -> MatchingWindowPins {
        guard let sourceWindowID, sourceProcessID != 0 else {
            return MatchingWindowPins(regions: [], requiresFullCover: true)
        }
        let candidates = regions.filter { region in
            guard region.isEnabled,
                  region.mode == .window,
                  let anchor = region.windowAnchor else { return false }

            return SharePreviewWindowPinApplicationPolicy.isPlausibleCandidate(
                anchor: anchor,
                sourceBundleIdentifier: sourceBundleIdentifier,
                sourceApplicationName: sourceApplicationName
            )
        }
        // Resolve all matching masks against one WindowServer lookup cache. Several masks often
        // follow the same browser window; querying it once per mask makes live edits visibly stall.
        let anchors = Dictionary(uniqueKeysWithValues: candidates.compactMap { region in
            region.windowAnchor.map { (region.id, $0) }
        })
        let resolutions = tracker.resolutions(for: anchors)
        var matches: [MaskRegion] = []
        var requiresFullCover = false
        for region in candidates {
            switch SharePreviewWindowPinResolutionPolicy.decision(
                for: resolutions[region.id] ?? .uncertain,
                sourceWindowID: sourceWindowID,
                sourceProcessID: sourceProcessID
            ) {
            case .include:
                matches.append(region)
            case .unrelated:
                break
            case .cover:
                // A same-application pin can plausibly belong to the selected source until it is
                // positively resolved elsewhere. Never silently omit its mask on a query failure,
                // title transition, or ambiguous rebind while another mask keeps output renderable.
                requiresFullCover = true
            }
        }
        return MatchingWindowPins(regions: matches, requiresFullCover: requiresFullCover)
    }

    private struct ActiveMasks {
        let regions: [MaskRegion]
        let requiresFullCover: Bool
        let hasRenderableConfiguration: Bool
        let relevantTextFollowRuleCount: Int
        let minimumCompletedTextFollowFrameTime: UInt64?
        let maximumCompletedTextFollowFrameTime: UInt64?
        let dynamicRuleNeedsAttention: Bool
    }

    private var sourceTextFollowIdentity: TextFollowWindowIdentity? {
        guard let sourceWindowID else { return nil }
        return TextFollowWindowIdentity(
            windowID: sourceWindowID,
            processID: sourceProcessID,
            bundleIdentifier: sourceBundleIdentifier,
            applicationName: sourceApplicationName
        )
    }

    private func resolveActiveMasks(regions: [MaskRegion], needsReview: Bool) -> ActiveMasks {
        guard !needsReview else {
            return ActiveMasks(
                regions: [],
                requiresFullCover: true,
                hasRenderableConfiguration: false,
                relevantTextFollowRuleCount: 0,
                minimumCompletedTextFollowFrameTime: nil,
                maximumCompletedTextFollowFrameTime: nil,
                dynamicRuleNeedsAttention: false
            )
        }

        let windowPins = matchingRegions(in: regions)
        guard let sourceIdentity = sourceTextFollowIdentity else {
            // Identity uncertainty must not allow a dynamic rule to silently disappear from the
            // preview. Picker-selected windows normally always supply these fields.
            return ActiveMasks(
                regions: windowPins.regions,
                requiresFullCover: true,
                hasRenderableConfiguration: !windowPins.regions.isEmpty
                    || windowPins.requiresFullCover,
                relevantTextFollowRuleCount: 0,
                minimumCompletedTextFollowFrameTime: nil,
                maximumCompletedTextFollowFrameTime: nil,
                dynamicRuleNeedsAttention: false
            )
        }
        let dynamic = textFollow.sharePreviewSnapshot(for: sourceIdentity)
        return ActiveMasks(
            regions: windowPins.regions + dynamic.regions,
            requiresFullCover: windowPins.requiresFullCover || dynamic.requiresFullCover,
            // A completed Text Follow scan remains a valid preview configuration when the latest
            // frame contains zero occurrences. Only the absence of both rule types keeps the
            // historical empty-configuration cover behavior.
            hasRenderableConfiguration: !windowPins.regions.isEmpty
                || windowPins.requiresFullCover
                || dynamic.relevantRuleCount > 0,
            relevantTextFollowRuleCount: dynamic.relevantRuleCount,
            minimumCompletedTextFollowFrameTime: dynamic.minimumCompletedFrameTime,
            maximumCompletedTextFollowFrameTime: dynamic.maximumCompletedFrameTime,
            dynamicRuleNeedsAttention: dynamic.relevantRuleCount > 0
                && dynamic.requiresFullCover
        )
    }

    private func updateProcessor(regions: [MaskRegion], recoveryIssue: String?) {
        // @Published emits in willSet. The emitted value, not a synchronous property re-read, is
        // authoritative here so a newly raised recovery issue covers the very next frame.
        let needsReview = recoveryIssue != nil
        if savedDataNeedsReview != needsReview { savedDataNeedsReview = needsReview }

        guard sourceWindowID != nil, stream != nil else {
            // There is no active processor revision to update, but an idle recovery issue still
            // clears any pixels retained by a presenter during an asynchronous stop.
            if needsReview {
                setFrameImage(nil)
                if !frameIsCovered { frameIsCovered = true }
            }
            return
        }

        let activeMasks = resolveActiveMasks(regions: regions, needsReview: needsReview)
        let snapshot = ActiveMaskSnapshot(
            regions: activeMasks.regions,
            savedDataNeedsReview: needsReview,
            requiresFullCover: activeMasks.requiresFullCover,
            hasRenderableConfiguration: activeMasks.hasRenderableConfiguration,
            relevantTextFollowRuleCount: activeMasks.relevantTextFollowRuleCount,
            dynamicRuleNeedsAttention: activeMasks.dynamicRuleNeedsAttention
        )
        guard snapshot != activeMaskSnapshot else {
            // OCR can finish a newer source frame without changing any match geometry or semantic
            // readiness. Keep that time out of snapshot equality while still letting the
            // cross-stream damage barrier advance and release a covered preview.
            processor.updateRecognitionTime(
                relevantTextFollowRuleCount: activeMasks.relevantTextFollowRuleCount,
                minimumCompletedTextFollowFrameTime: activeMasks.minimumCompletedTextFollowFrameTime,
                maximumCompletedTextFollowFrameTime: activeMasks.maximumCompletedTextFollowFrameTime
            )
            return
        }
        activeMaskSnapshot = snapshot

        invalidateReview()
        if appliedMaskCount != activeMasks.regions.count {
            appliedMaskCount = activeMasks.regions.count
        }
        if hasRenderableConfiguration != activeMasks.hasRenderableConfiguration {
            hasRenderableConfiguration = activeMasks.hasRenderableConfiguration
        }
        relevantTextFollowRuleCount = activeMasks.relevantTextFollowRuleCount
        dynamicRuleNeedsAttention = activeMasks.dynamicRuleNeedsAttention
        // Any geometry/style/recovery change invalidates the displayed pixels immediately. A frame
        // rendered with the previous revision must never survive until an idle callback.
        setFrameImage(nil)
        if !frameIsCovered { frameIsCovered = true }
        activeMaskRevision = processor.update(
            regions: activeMasks.regions,
            requiresFullCover: activeMasks.requiresFullCover,
            hasRenderableConfiguration: activeMasks.hasRenderableConfiguration,
            relevantTextFollowRuleCount: activeMasks.relevantTextFollowRuleCount,
            minimumCompletedTextFollowFrameTime: activeMasks.minimumCompletedTextFollowFrameTime,
            maximumCompletedTextFollowFrameTime: activeMasks.maximumCompletedTextFollowFrameTime
        )
    }

    private func clearStaleFrameIfNeeded() {
        guard isRunning, hasFrame else { return }
        if Date().timeIntervalSince(lastFrameDate) > 1.25 {
            // A minimized, closed, or suspended source must not leave a believable old frame.
            setFrameImage(nil)
            if !frameIsCovered { frameIsCovered = true }
            invalidateReview()
        }
    }

    private func setFrameImage(_ image: CGImage?) {
        framePresenter.present(image)
        let hasNewFrame = image != nil
        if hasFrame != hasNewFrame { hasFrame = hasNewFrame }
    }

    private func invalidateReview() {
        reviewRevision &+= 1
    }

    private static func configuration(for selection: PickedWindow) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        let sourceSize = selection.filter.contentRect.size == .zero
            ? selection.candidate.quartzFrame.size
            : selection.filter.contentRect.size
        let pointPixelScale = max(1, CGFloat(selection.filter.pointPixelScale))
        let nativeWidth = max(2, sourceSize.width * pointPixelScale)
        let nativeHeight = max(2, sourceSize.height * pointPixelScale)
        let fit = min(1, 2560 / nativeWidth, 1440 / nativeHeight)

        func evenPixelCount(_ value: CGFloat) -> Int {
            let rounded = max(2, Int(value.rounded(.down)))
            return rounded.isMultiple(of: 2) ? rounded : rounded - 1
        }

        configuration.width = evenPixelCount(nativeWidth * fit)
        configuration.height = evenPixelCount(nativeHeight * fit)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 2
        // Text Follow excludes cursor pixels. Keeping the preview source boundary identical avoids
        // cursor-only damage outrunning OCR and holding the fail-closed time barrier indefinitely.
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.capturesAudio = false
        configuration.shouldBeOpaque = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.streamName = String(localized: "BlurFollow Share Preview")
        if #available(macOS 14.2, *) {
            // Text Follow excludes child windows so its normalized Vision placements describe the
            // same content boundary that this preview composites.
            configuration.includeChildWindows = false
        }
        return configuration
    }

    private func startCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.startCapture { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    private func stopCapture(_ stream: SCStream) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stream.stopCapture { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }
}

enum SharePreviewDelivery {
    case frame(CGImage, generation: UInt64, maskRevision: UInt64, isBlocked: Bool)
    case heartbeat(generation: UInt64, maskRevision: UInt64)
    case clear(generation: UInt64, maskRevision: UInt64)
}

/// Compares exact source pixels only when ScreenCaptureKit reports damage (or cannot classify it).
/// Empty, valid dirty metadata preserves the last exact baseline without hashing every idle frame.
struct SharePreviewFrameChangeDetector: Sendable {
    enum Assessment: Equatable, Sendable {
        case initial
        case unchanged
        case changed
        case unknown

        var reportsDamage: Bool { self != .unchanged }
    }

    private var hasObservedFrame = false
    private var previousFingerprint: TextFollowPixelFingerprint?

    func requiresFingerprint(metadataReportsChange: Bool) -> Bool {
        !hasObservedFrame || metadataReportsChange
    }

    mutating func assess(
        fingerprint: TextFollowPixelFingerprint?,
        metadataReportsChange: Bool
    ) -> Assessment {
        guard hasObservedFrame else {
            hasObservedFrame = true
            previousFingerprint = fingerprint
            return .initial
        }
        guard metadataReportsChange else {
            // No source pixels changed, so a deliberately omitted hash must not erase the exact
            // baseline established by the most recent changed/initial frame.
            return .unchanged
        }
        defer { previousFingerprint = fingerprint }

        switch (previousFingerprint, fingerprint) {
        case let (.some(previous), .some(current)):
            return previous == current ? .unchanged : .changed
        case (.none, .none), (.some, .none), (.none, .some):
            // If either side cannot be hashed, equality cannot be proven. Advance the barrier and
            // keep Preview fail-closed until OCR has caught up with this sample.
            return .unknown
        }
    }

    mutating func reset() {
        hasObservedFrame = false
        previousFingerprint = nil
    }
}

/// Keeps Preview closed while exact pixel equality is still being established outside stateLock.
/// The generation tag prevents a delayed hash from releasing a newly activated stream.
struct SharePreviewFingerprintAssessmentGate: Sendable {
    private var pendingGeneration: UInt64?

    mutating func begin(generation: UInt64) {
        pendingGeneration = generation
    }

    @discardableResult
    mutating func complete(generation: UInt64) -> Bool {
        guard pendingGeneration == generation else { return false }
        pendingGeneration = nil
        return true
    }

    func requiresFullCover(generation: UInt64) -> Bool {
        pendingGeneration == generation
    }

    mutating func reset() {
        pendingGeneration = nil
    }
}

enum SharePreviewDynamicCoverPolicy {
    static func requiresFullCover(
        barrierRequiresFullCover: Bool,
        fingerprintAssessmentInFlight: Bool
    ) -> Bool {
        barrierRequiresFullCover || fingerprintAssessmentInFlight
    }
}

/// Orders damage observed by Share Preview's SCStream against completed OCR from Text Follow's
/// separate SCStream. Both timestamps are WindowServer mach absolute time, so geometry is trusted
/// only after every relevant rule has completed a frame at least as new as the latest damage.
struct SharePreviewDynamicContentBarrier: Sendable {
    static let maximumDirtyRectCount = 256

    struct Snapshot: Equatable, Sendable {
        let requiresFullCover: Bool
        let latestDamageFrameTime: UInt64?
        let latestObservedFrameTime: UInt64?
        let minimumCompletedTextFollowFrameTime: UInt64?
        let maximumCompletedTextFollowFrameTime: UInt64?
    }

    private var relevantTextFollowRuleCount = 0
    private var minimumCompletedTextFollowFrameTime: UInt64?
    private var maximumCompletedTextFollowFrameTime: UInt64?
    private var latestDamageFrameTime: UInt64?
    private var latestObservedFrameTime: UInt64?
    private var hasObservedFrame = false
    /// A changed frame without a comparable display time cannot be ordered safely. Keep the latch
    /// closed until the stream is reset instead of guessing that a later OCR callback covered it.
    private var hasDamageWithoutFrameTime = false

    init(
        relevantTextFollowRuleCount: Int = 0,
        minimumCompletedTextFollowFrameTime: UInt64? = nil,
        maximumCompletedTextFollowFrameTime: UInt64? = nil
    ) {
        reset(
            relevantTextFollowRuleCount: relevantTextFollowRuleCount,
            minimumCompletedTextFollowFrameTime: minimumCompletedTextFollowFrameTime,
            maximumCompletedTextFollowFrameTime: maximumCompletedTextFollowFrameTime
        )
    }

    mutating func reset(
        relevantTextFollowRuleCount: Int = 0,
        minimumCompletedTextFollowFrameTime: UInt64? = nil,
        maximumCompletedTextFollowFrameTime: UInt64? = nil
    ) {
        self.relevantTextFollowRuleCount = max(0, relevantTextFollowRuleCount)
        self.minimumCompletedTextFollowFrameTime = minimumCompletedTextFollowFrameTime
        self.maximumCompletedTextFollowFrameTime = maximumCompletedTextFollowFrameTime
            ?? minimumCompletedTextFollowFrameTime
        latestDamageFrameTime = nil
        latestObservedFrameTime = nil
        hasObservedFrame = false
        hasDamageWithoutFrameTime = false
    }

    /// Changes the current dynamic-rule set while preserving damage already observed on this
    /// Share Preview stream. A newly added or reset rule may legitimately move the minimum time
    /// backwards, so configuration updates replace rather than monotonically merge the value.
    mutating func updateConfiguration(
        relevantTextFollowRuleCount: Int,
        minimumCompletedTextFollowFrameTime: UInt64?,
        maximumCompletedTextFollowFrameTime: UInt64?
    ) {
        self.relevantTextFollowRuleCount = max(0, relevantTextFollowRuleCount)
        self.minimumCompletedTextFollowFrameTime = minimumCompletedTextFollowFrameTime
        self.maximumCompletedTextFollowFrameTime = maximumCompletedTextFollowFrameTime
    }

    /// Advances OCR time when mask geometry and semantic readiness are unchanged. This path cannot
    /// regress the barrier if callbacks are delivered out of order.
    @discardableResult
    mutating func advanceRecognitionTime(
        relevantTextFollowRuleCount: Int,
        minimumCompletedTextFollowFrameTime: UInt64?,
        maximumCompletedTextFollowFrameTime: UInt64?
    ) -> Bool {
        let wasCovered = snapshot.requiresFullCover
        let normalizedCount = max(0, relevantTextFollowRuleCount)
        guard normalizedCount == self.relevantTextFollowRuleCount else {
            updateConfiguration(
                relevantTextFollowRuleCount: normalizedCount,
                minimumCompletedTextFollowFrameTime: minimumCompletedTextFollowFrameTime,
                maximumCompletedTextFollowFrameTime: maximumCompletedTextFollowFrameTime
            )
            return wasCovered && !snapshot.requiresFullCover
        }
        guard normalizedCount > 0 else {
            self.minimumCompletedTextFollowFrameTime = nil
            self.maximumCompletedTextFollowFrameTime = nil
            return wasCovered && !snapshot.requiresFullCover
        }
        guard let minimumCompletedTextFollowFrameTime,
              let maximumCompletedTextFollowFrameTime else { return false }
        self.minimumCompletedTextFollowFrameTime = max(
            self.minimumCompletedTextFollowFrameTime ?? 0,
            minimumCompletedTextFollowFrameTime
        )
        self.maximumCompletedTextFollowFrameTime = max(
            self.maximumCompletedTextFollowFrameTime ?? 0,
            maximumCompletedTextFollowFrameTime
        )
        return wasCovered && !snapshot.requiresFullCover
    }

    @discardableResult
    mutating func observeFrame(
        dirtyRects: [CGRect]?,
        displayTime: UInt64?
    ) -> Snapshot {
        observeFrame(
            reportsPixelDamage: Self.hasChangedContent(dirtyRects),
            displayTime: displayTime
        )
    }

    @discardableResult
    mutating func observeFrame(
        reportsPixelDamage: Bool,
        displayTime: UInt64?
    ) -> Snapshot {
        // The first frame establishes this stream's content baseline. Even an empty dirty list is
        // relative only to ScreenCaptureKit's internal baseline, not to Text Follow's independent
        // stream, so it must be ordered against OCR before any source pixels are shown.
        let isInitialFrame = !hasObservedFrame
        hasObservedFrame = true
        if let displayTime {
            latestObservedFrameTime = max(latestObservedFrameTime ?? 0, displayTime)
        }
        if isInitialFrame || reportsPixelDamage {
            if let displayTime {
                latestDamageFrameTime = max(latestDamageFrameTime ?? 0, displayTime)
            } else {
                hasDamageWithoutFrameTime = true
            }
        }
        return snapshot
    }

    /// Idle samples contain no new pixels, but their WindowServer time proves the cached complete
    /// frame remained current through that point. This lets new OCR geometry rebase safely.
    @discardableResult
    mutating func observeIdleFrame(displayTime: UInt64?) -> Bool {
        let wasCovered = snapshot.requiresFullCover
        if let displayTime {
            latestObservedFrameTime = max(latestObservedFrameTime ?? 0, displayTime)
        }
        return wasCovered && !snapshot.requiresFullCover
    }

    var snapshot: Snapshot {
        let requiresFullCover: Bool
        if relevantTextFollowRuleCount == 0 {
            requiresFullCover = false
        } else if hasDamageWithoutFrameTime {
            requiresFullCover = true
        } else if let latestDamageFrameTime {
            guard let minimumCompletedTextFollowFrameTime,
                  let maximumCompletedTextFollowFrameTime,
                  let latestObservedFrameTime else {
                return Snapshot(
                    requiresFullCover: true,
                    latestDamageFrameTime: latestDamageFrameTime,
                    latestObservedFrameTime: latestObservedFrameTime,
                    minimumCompletedTextFollowFrameTime: minimumCompletedTextFollowFrameTime,
                    maximumCompletedTextFollowFrameTime: maximumCompletedTextFollowFrameTime
                )
            }
            requiresFullCover = minimumCompletedTextFollowFrameTime < latestDamageFrameTime
                || latestObservedFrameTime < maximumCompletedTextFollowFrameTime
        } else {
            requiresFullCover = false
        }
        return Snapshot(
            requiresFullCover: requiresFullCover,
            latestDamageFrameTime: latestDamageFrameTime,
            latestObservedFrameTime: latestObservedFrameTime,
            minimumCompletedTextFollowFrameTime: minimumCompletedTextFollowFrameTime,
            maximumCompletedTextFollowFrameTime: maximumCompletedTextFollowFrameTime
        )
    }

    static func hasChangedContent(_ dirtyRects: [CGRect]?) -> Bool {
        guard let dirtyRects,
              dirtyRects.count <= maximumDirtyRectCount else { return true }
        var hasNonemptyRect = false
        for rect in dirtyRects {
            let values = [rect.minX, rect.minY, rect.width, rect.height]
            guard values.allSatisfy(\.isFinite),
                  rect.width >= 0,
                  rect.height >= 0 else { return true }
            if rect.width > 0, rect.height > 0 { hasNonemptyRect = true }
        }
        return hasNonemptyRect
    }
}

enum SharePreviewRenderPolicy {
    static func isBlocked(
        requiresFullCover: Bool,
        hasRenderableConfiguration: Bool
    ) -> Bool {
        requiresFullCover || !hasRenderableConfiguration
    }
}

enum SharePreviewWindowPinResolutionPolicy {
    enum Decision: Equatable {
        case include
        case unrelated
        case cover
    }

    static func decision(
        for resolution: TrackedWindowResolution,
        sourceWindowID: CGWindowID,
        sourceProcessID: pid_t
    ) -> Decision {
        switch resolution {
        case .frame(let frame):
            return frame.windowID == sourceWindowID && frame.processID == sourceProcessID
                ? .include
                : .unrelated
        case .uncertain, .unavailable:
            return .cover
        }
    }
}

enum SharePreviewWindowPinApplicationPolicy {
    static func isPlausibleCandidate(
        anchor: WindowAnchor,
        sourceBundleIdentifier: String,
        sourceApplicationName: String
    ) -> Bool {
        WindowApplicationIdentityMatcher.compare(
            bundleIdentifier: anchor.bundleIdentifier,
            applicationName: anchor.applicationName,
            toBundleIdentifier: sourceBundleIdentifier,
            applicationName: sourceApplicationName
        ) != .different
    }
}

/// A one-element mailbox for expensive frame work. ScreenCaptureKit can deliver another sample
/// while the previous sample is still being composited; only the newest pending sample is useful
/// to the preview. Tokens also let the renderer reject work that was superseded while in flight.
struct LatestFrameSlot<Value> {
    struct Item {
        let sequence: UInt64
        let value: Value
    }

    private(set) var latestSequence: UInt64 = 0
    private var pending: Item?

    @discardableResult
    mutating func submit(_ value: Value) -> UInt64 {
        latestSequence &+= 1
        pending = Item(sequence: latestSequence, value: value)
        return latestSequence
    }

    mutating func take() -> Item? {
        defer { pending = nil }
        return pending
    }

    func isLatest(_ sequence: UInt64) -> Bool {
        sequence == latestSequence
    }

    mutating func cancel() {
        latestSequence &+= 1
        pending = nil
    }
}

enum SharePreviewRenderRebasePolicy {
    /// A rerender that captured an older state must never replace a cache already rebased to a
    /// newer mask revision. The processor also holds stateLock -> renderLock while applying this
    /// check, so the accepted revision remains current through the slot/cache mutation.
    @discardableResult
    static func replaceCacheAndSubmit<Value>(
        requestedRevision: UInt64,
        cachedRevision: UInt64,
        replacement: Value,
        cache: inout Value?,
        slot: inout LatestFrameSlot<Value>
    ) -> Bool {
        guard requestedRevision >= cachedRevision else { return false }
        cache = replacement
        slot.submit(replacement)
        return true
    }
}

enum SharePreviewCachedFrameFreshnessPolicy {
    /// OCR geometry may be newer than the cached pixels while a complete Preview callback is
    /// between damage observation and mailbox publication. Never rebase geometry onto a sample
    /// older than the latest damage already admitted to the barrier.
    static func canRebase(
        cachedDisplayTime: UInt64?,
        latestDamageFrameTime: UInt64?
    ) -> Bool {
        guard let latestDamageFrameTime else { return true }
        guard let cachedDisplayTime else { return false }
        return cachedDisplayTime >= latestDamageFrameTime
    }
}

final class SharePreviewFrameProcessor: NSObject, SCStreamOutput, @unchecked Sendable {
    static let queue = DispatchQueue(label: "com.hinoshiba.blurfollow.share-preview.frames", qos: .userInteractive)
    private static let renderQueue = DispatchQueue(
        label: "com.hinoshiba.blurfollow.share-preview.render",
        qos: .userInitiated
    )

    var onDelivery: (@MainActor (SharePreviewDelivery) -> Void)?
    var onFirstSourceFrame: (@MainActor (_ generation: UInt64) -> Void)?

    private struct State {
        var streamID: ObjectIdentifier?
        var generation: UInt64 = 0
        var maskRevision: UInt64 = 0
        var regions: [MaskRegion] = []
        var requiresFullCover = false
        var hasRenderableConfiguration = false
        var dynamicContentBarrier = SharePreviewDynamicContentBarrier()
        var frameChangeDetector = SharePreviewFrameChangeDetector()
        var fingerprintAssessmentGate = SharePreviewFingerprintAssessmentGate()
        var hasObservedSourceFrame = false
        var lastSourceActivityDate = Date.distantPast
        var lastExtent: CGRect?
        var lastHeartbeatDate = Date.distantPast
    }

    private let context = CIContext(options: [.cacheIntermediates: false])
    private let stateLock = NSLock()
    private var state = State()

    private let deliveryLock = NSLock()
    private var pendingDelivery: SharePreviewDelivery?
    private var deliveryScheduled = false

    private final class RenderInput: @unchecked Sendable {
        enum Kind {
            case complete
            case blocked
        }

        let kind: Kind
        let sampleBuffer: CMSampleBuffer
        let attachments: [SCStreamFrameInfo: Any]?
        let snapshot: State

        init(
            kind: Kind,
            sampleBuffer: CMSampleBuffer,
            attachments: [SCStreamFrameInfo: Any]?,
            snapshot: State
        ) {
            self.kind = kind
            self.sampleBuffer = sampleBuffer
            self.attachments = attachments
            self.snapshot = snapshot
        }
    }

    private let renderLock = NSLock()
    private var renderSlot = LatestFrameSlot<RenderInput>()
    private var renderScheduled = false
    /// Retains at most the newest valid source sample in memory so a timestamp-only OCR completion
    /// can release a static, already-covered frame without waiting for another damage callback.
    private var latestCompleteInput: RenderInput?

    @discardableResult
    func activate(
        stream: SCStream,
        generation: UInt64,
        regions: [MaskRegion],
        requiresFullCover: Bool,
        hasRenderableConfiguration: Bool,
        relevantTextFollowRuleCount: Int,
        minimumCompletedTextFollowFrameTime: UInt64?,
        maximumCompletedTextFollowFrameTime: UInt64?
    ) -> UInt64 {
        stateLock.lock()
        let revision = state.maskRevision &+ 1
        state = State(
            streamID: ObjectIdentifier(stream),
            generation: generation,
            maskRevision: revision,
            regions: regions,
            requiresFullCover: requiresFullCover,
            hasRenderableConfiguration: hasRenderableConfiguration,
            dynamicContentBarrier: SharePreviewDynamicContentBarrier(
                relevantTextFollowRuleCount: relevantTextFollowRuleCount,
                minimumCompletedTextFollowFrameTime: minimumCompletedTextFollowFrameTime,
                maximumCompletedTextFollowFrameTime: maximumCompletedTextFollowFrameTime
            ),
            frameChangeDetector: SharePreviewFrameChangeDetector(),
            fingerprintAssessmentGate: SharePreviewFingerprintAssessmentGate(),
            hasObservedSourceFrame: false,
            lastSourceActivityDate: .distantPast,
            lastExtent: nil,
            lastHeartbeatDate: .distantPast
        )
        stateLock.unlock()
        cancelPendingRender()
        return revision
    }

    @discardableResult
    func update(
        regions: [MaskRegion],
        requiresFullCover: Bool,
        hasRenderableConfiguration: Bool,
        relevantTextFollowRuleCount: Int,
        minimumCompletedTextFollowFrameTime: UInt64?,
        maximumCompletedTextFollowFrameTime: UInt64?
    ) -> UInt64 {
        stateLock.lock()
        state.maskRevision &+= 1
        state.regions = regions
        state.requiresFullCover = requiresFullCover
        state.hasRenderableConfiguration = hasRenderableConfiguration
        state.dynamicContentBarrier.updateConfiguration(
            relevantTextFollowRuleCount: relevantTextFollowRuleCount,
            minimumCompletedTextFollowFrameTime: minimumCompletedTextFollowFrameTime,
            maximumCompletedTextFollowFrameTime: maximumCompletedTextFollowFrameTime
        )
        let revision = state.maskRevision
        let shouldRerender = !state.requiresFullCover
            && state.hasRenderableConfiguration
            && !Self.dynamicContentRequiresFullCover(state)
        stateLock.unlock()
        cancelPendingRender(clearLatestFrame: false)
        if shouldRerender { rerenderLatestCompleteFrame() }
        return revision
    }

    /// Recognition can advance without changing mask geometry or semantic readiness. Keep the
    /// current revision and pending render work, but update the cross-stream ordering barrier.
    func updateRecognitionTime(
        relevantTextFollowRuleCount: Int,
        minimumCompletedTextFollowFrameTime: UInt64?,
        maximumCompletedTextFollowFrameTime: UInt64?
    ) {
        stateLock.lock()
        let shouldRerender = state.dynamicContentBarrier.advanceRecognitionTime(
            relevantTextFollowRuleCount: relevantTextFollowRuleCount,
            minimumCompletedTextFollowFrameTime: minimumCompletedTextFollowFrameTime,
            maximumCompletedTextFollowFrameTime: maximumCompletedTextFollowFrameTime
        ) && !state.requiresFullCover
            && state.hasRenderableConfiguration
            && !Self.fingerprintAssessmentIsInFlight(state)
        stateLock.unlock()
        if shouldRerender { rerenderLatestCompleteFrame() }
    }

    func deactivate() {
        stateLock.lock()
        state.maskRevision &+= 1
        state.streamID = nil
        state.regions = []
        state.requiresFullCover = false
        state.hasRenderableConfiguration = false
        state.dynamicContentBarrier.reset()
        state.frameChangeDetector.reset()
        state.fingerprintAssessmentGate.reset()
        state.hasObservedSourceFrame = false
        state.lastExtent = nil
        stateLock.unlock()
        cancelPendingRender()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, let snapshot = snapshot(for: stream) else { return }

        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else {
            scheduleRender(
                RenderInput(kind: .blocked, sampleBuffer: sampleBuffer, attachments: nil, snapshot: snapshot),
                clearImmediately: true
            )
            return
        }

        guard let attachments = Self.attachments(from: sampleBuffer),
              let statusNumber = attachments[.status] as? NSNumber,
              let status = SCFrameStatus(rawValue: statusNumber.intValue) else {
            scheduleRender(
                RenderInput(kind: .blocked, sampleBuffer: sampleBuffer, attachments: nil, snapshot: snapshot),
                clearImmediately: true
            )
            return
        }

        switch status {
        case .complete, .started:
            guard let observedSnapshot = observeDynamicContentFrame(
                sampleBuffer: sampleBuffer,
                attachments: attachments,
                for: stream
            ) else { return }
            scheduleRender(RenderInput(
                kind: .complete,
                sampleBuffer: sampleBuffer,
                attachments: attachments,
                snapshot: observedSnapshot
            ))
        case .idle:
            if observeDynamicContentIdleFrame(attachments: attachments, for: stream) {
                rerenderLatestCompleteFrame()
            }
            emitHeartbeatIfNeeded(
                generation: snapshot.generation,
                maskRevision: snapshot.maskRevision,
                streamID: snapshot.streamID
            )
        case .blank, .suspended, .stopped:
            scheduleRender(
                RenderInput(kind: .blocked, sampleBuffer: sampleBuffer, attachments: nil, snapshot: snapshot),
                clearImmediately: true
            )
        @unknown default:
            scheduleRender(
                RenderInput(kind: .blocked, sampleBuffer: sampleBuffer, attachments: nil, snapshot: snapshot),
                clearImmediately: true
            )
        }
    }

    private func observeDynamicContentFrame(
        sampleBuffer: CMSampleBuffer,
        attachments: [SCStreamFrameInfo: Any],
        for stream: SCStream
    ) -> State? {
        // Missing or malformed damage metadata is deliberately represented as nil; the barrier
        // treats it as changed content. Display time is WindowServer mach absolute time and is the
        // only safe ordering relation with Text Follow's independent capture stream.
        let dirtyRects = Self.rects(from: attachments[.dirtyRects])
        let displayTime = Self.machAbsoluteTime(from: attachments[.displayTime])
        let metadataReportsChange = SharePreviewDynamicContentBarrier.hasChangedContent(dirtyRects)

        // Establish an exact baseline on the first source frame. Afterwards a valid empty dirty
        // list needs no full-frame SHA; broad, non-empty, missing, and malformed metadata must
        // prove pixel equality before it is allowed to leave the existing OCR barrier untouched.
        stateLock.lock()
        guard state.streamID == ObjectIdentifier(stream) else {
            stateLock.unlock()
            return nil
        }
        let expectedGeneration = state.generation
        let requiresFingerprint = state.frameChangeDetector.requiresFingerprint(
            metadataReportsChange: metadataReportsChange
        )
        if requiresFingerprint {
            // Hashing the full content surface can overlap MainActor configuration/OCR updates.
            // Close every render path before releasing stateLock so newer geometry can never be
            // composited onto the older cached sample while this frame's damage is undecided.
            state.fingerprintAssessmentGate.begin(generation: expectedGeneration)
        }
        stateLock.unlock()

        let fingerprint = requiresFingerprint
            ? Self.pixelFingerprint(from: sampleBuffer, attachments: attachments)
            : nil

        stateLock.lock()
        guard state.streamID == ObjectIdentifier(stream),
              state.generation == expectedGeneration else {
            stateLock.unlock()
            return nil
        }
        let changeAssessment = state.frameChangeDetector.assess(
            fingerprint: fingerprint,
            metadataReportsChange: metadataReportsChange
        )
        let isFirstSourceFrame = !state.hasObservedSourceFrame
        state.hasObservedSourceFrame = true
        state.lastSourceActivityDate = Date()
        // Commit changed/unknown damage before releasing the assessment gate. Both mutations occur
        // under stateLock, so no renderer can observe an open interval between them.
        state.dynamicContentBarrier.observeFrame(
            reportsPixelDamage: changeAssessment.reportsDamage,
            displayTime: displayTime
        )
        if requiresFingerprint {
            _ = state.fingerprintAssessmentGate.complete(generation: expectedGeneration)
        }
        let snapshot = state
        stateLock.unlock()

        if isFirstSourceFrame {
            Task { @MainActor [weak self] in
                self?.onFirstSourceFrame?(snapshot.generation)
            }
        }
        return snapshot
    }

    private static func pixelFingerprint(
        from sampleBuffer: CMSampleBuffer,
        attachments: [SCStreamFrameInfo: Any]
    ) -> TextFollowPixelFingerprint? {
        guard let pixelBuffer = sampleBuffer.imageBuffer,
              let contentRectInPoints = rect(from: attachments[.contentRect]),
              let scaleFactor = scalar(from: attachments[.scaleFactor]),
              let contentPixelRect = SharePreviewFrameGeometry.contentPixelRect(
                contentRectInPoints: contentRectInPoints,
                scaleFactor: scaleFactor,
                extent: CGRect(
                    x: 0,
                    y: 0,
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )
              ) else { return nil }
        return TextFollowPixelFingerprint.make(
            from: pixelBuffer,
            contentPixelRect: contentPixelRect
        )
    }

    private func observeDynamicContentIdleFrame(
        attachments: [SCStreamFrameInfo: Any],
        for stream: SCStream
    ) -> Bool {
        let displayTime = Self.machAbsoluteTime(from: attachments[.displayTime])
        stateLock.lock()
        defer { stateLock.unlock() }
        guard state.streamID == ObjectIdentifier(stream) else { return false }
        state.lastSourceActivityDate = Date()
        return state.dynamicContentBarrier.observeIdleFrame(displayTime: displayTime)
            && !state.requiresFullCover
            && state.hasRenderableConfiguration
            && !Self.fingerprintAssessmentIsInFlight(state)
    }

    private func scheduleRender(_ input: RenderInput, clearImmediately: Bool = false) {
        // A callback can arrive after another source has activated. Validate while holding the
        // state→render lock order so an old stream can never erase the new stream's only cache or
        // replace its pending work between the check and mutation.
        stateLock.lock()
        guard state.streamID == input.snapshot.streamID,
              state.generation == input.snapshot.generation else {
            stateLock.unlock()
            return
        }
        let scheduledInput: RenderInput
        if state.maskRevision == input.snapshot.maskRevision {
            scheduledInput = input
        } else {
            // Geometry/readiness may change between frame observation and mailbox insertion. Rebase
            // the current source sample atomically so an old revision cannot supersede the only
            // render already queued for the new revision.
            scheduledInput = RenderInput(
                kind: input.kind,
                sampleBuffer: input.sampleBuffer,
                attachments: input.attachments,
                snapshot: state
            )
        }
        renderLock.lock()
        switch scheduledInput.kind {
        case .complete:
            latestCompleteInput = scheduledInput
        case .blocked:
            // Invalid/blank/stopped content makes the cached source sample untrustworthy.
            latestCompleteInput = nil
        }
        renderSlot.submit(scheduledInput)
        // Invalid, blank, suspended, and stopped samples clear synchronously with mailbox ordering.
        // Holding renderLock means an older in-flight render either publishes before this clear or
        // observes its stale token afterwards; it can never replace the clear after this point.
        if clearImmediately {
            enqueue(.clear(
                generation: scheduledInput.snapshot.generation,
                maskRevision: scheduledInput.snapshot.maskRevision
            ))
        }
        let shouldSchedule = !renderScheduled
        if shouldSchedule { renderScheduled = true }
        renderLock.unlock()
        stateLock.unlock()

        if shouldSchedule {
            Self.renderQueue.async { [weak self] in self?.drainRenderSlot() }
        }
    }

    private func cancelPendingRender(clearLatestFrame: Bool = true) {
        renderLock.lock()
        renderSlot.cancel()
        if clearLatestFrame { latestCompleteInput = nil }
        renderLock.unlock()
    }

    private func rerenderLatestCompleteFrame() {
        stateLock.lock()
        let barrierSnapshot = state.dynamicContentBarrier.snapshot
        guard state.streamID != nil,
              !state.requiresFullCover,
              state.hasRenderableConfiguration,
              Date().timeIntervalSince(state.lastSourceActivityDate) <= 1.25,
              !Self.dynamicContentRequiresFullCover(state) else {
            stateLock.unlock()
            return
        }
        // Keep the same state -> render lock order as scheduleRender. An idle callback that read an
        // old revision can no longer pause here, let a newer update fill the slot, and then replace
        // that newer cache/slot with its stale snapshot.
        renderLock.lock()
        guard let cached = latestCompleteInput,
              cached.snapshot.streamID == state.streamID,
              let attachments = cached.attachments,
              SharePreviewCachedFrameFreshnessPolicy.canRebase(
                  cachedDisplayTime: Self.machAbsoluteTime(from: attachments[.displayTime]),
                  latestDamageFrameTime: barrierSnapshot.latestDamageFrameTime
              ) else {
            renderLock.unlock()
            stateLock.unlock()
            return
        }
        let currentSnapshot = state
        let input = RenderInput(
            kind: .complete,
            sampleBuffer: cached.sampleBuffer,
            attachments: attachments,
            snapshot: currentSnapshot
        )
        guard SharePreviewRenderRebasePolicy.replaceCacheAndSubmit(
            requestedRevision: currentSnapshot.maskRevision,
            cachedRevision: cached.snapshot.maskRevision,
            replacement: input,
            cache: &latestCompleteInput,
            slot: &renderSlot
        ) else {
            renderLock.unlock()
            stateLock.unlock()
            return
        }
        let shouldSchedule = !renderScheduled
        if shouldSchedule { renderScheduled = true }
        renderLock.unlock()
        stateLock.unlock()

        if shouldSchedule {
            Self.renderQueue.async { [weak self] in self?.drainRenderSlot() }
        }
    }

    private func drainRenderSlot() {
        while true {
            renderLock.lock()
            guard let item = renderSlot.take() else {
                renderScheduled = false
                renderLock.unlock()
                return
            }
            renderLock.unlock()

            let delivery: SharePreviewDelivery
            switch item.value.kind {
            case .complete:
                guard let attachments = item.value.attachments else { continue }
                delivery = renderCompleteFrame(
                    item.value.sampleBuffer,
                    attachments: attachments,
                    snapshot: item.value.snapshot
                )
            case .blocked:
                delivery = renderBlocked(
                    pixelBuffer: item.value.sampleBuffer.imageBuffer,
                    snapshot: item.value.snapshot
                )
            }

            renderLock.lock()
            if renderSlot.isLatest(item.sequence) {
                // See scheduleRender: renderLock establishes ordering with an immediate clear.
                enqueue(delivery)
            }
            renderLock.unlock()
        }
    }

    private func snapshot(for stream: SCStream) -> State? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard state.streamID == ObjectIdentifier(stream) else { return nil }
        return state
    }

    private static func fingerprintAssessmentIsInFlight(_ state: State) -> Bool {
        state.fingerprintAssessmentGate.requiresFullCover(generation: state.generation)
    }

    private static func dynamicContentRequiresFullCover(_ state: State) -> Bool {
        SharePreviewDynamicCoverPolicy.requiresFullCover(
            barrierRequiresFullCover: state.dynamicContentBarrier.snapshot.requiresFullCover,
            fingerprintAssessmentInFlight: fingerprintAssessmentIsInFlight(state)
        )
    }

    private func renderCompleteFrame(
        _ sampleBuffer: CMSampleBuffer,
        attachments: [SCStreamFrameInfo: Any],
        snapshot: State
    ) -> SharePreviewDelivery {
        guard let pixelBuffer = sampleBuffer.imageBuffer else {
            return renderBlocked(pixelBuffer: nil, snapshot: snapshot)
        }

        let source = CIImage(cvPixelBuffer: pixelBuffer)
        remember(extent: source.extent, streamID: snapshot.streamID)

        guard let contentRectInPoints = Self.rect(from: attachments[.contentRect]),
              let scaleFactor = Self.scalar(from: attachments[.scaleFactor]),
              let contentScale = Self.scalar(from: attachments[.contentScale]),
              let appearanceScale = SharePreviewFrameGeometry.appearanceScale(
                scaleFactor: scaleFactor,
                contentScale: contentScale
              ),
              let contentPixelRect = SharePreviewFrameGeometry.contentPixelRect(
                contentRectInPoints: contentRectInPoints,
                scaleFactor: scaleFactor,
                extent: source.extent
              ) else {
            return renderBlocked(
                source: source,
                generation: snapshot.generation,
                maskRevision: snapshot.maskRevision
            )
        }

        let enabledRegions = snapshot.regions.filter(\.isEnabled)
        let isBlocked = dynamicContentBarrierRequiresFullCover(for: snapshot)
            || SharePreviewRenderPolicy.isBlocked(
                requiresFullCover: snapshot.requiresFullCover,
                hasRenderableConfiguration: snapshot.hasRenderableConfiguration
            )
        let composited: CIImage? = if isBlocked {
            nil
        } else if enabledRegions.isEmpty {
            // A completed zero-match Text Follow scan intentionally preserves the current frame.
            source
        } else {
            SharePreviewCompositor.applyingValidated(
                regions: enabledRegions,
                to: source,
                contentRect: contentPixelRect,
                // contentScale maps original content points into surface points; scaleFactor maps
                // those points into output pixels. Preserve point-sized appearance settings across
                // Retina and downscaled capture surfaces.
                appearanceScale: appearanceScale
            )
        }
        let result = composited ?? SharePreviewCompositor.blocked(source)
        let outputIsBlocked = isBlocked || composited == nil

        guard let image = context.createCGImage(result, from: source.extent) else {
            return .clear(generation: snapshot.generation, maskRevision: snapshot.maskRevision)
        }
        return .frame(
            image,
            generation: snapshot.generation,
            maskRevision: snapshot.maskRevision,
            isBlocked: outputIsBlocked
        )
    }

    private func dynamicContentBarrierRequiresFullCover(for snapshot: State) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard state.streamID == snapshot.streamID,
              state.generation == snapshot.generation,
              state.maskRevision == snapshot.maskRevision else { return true }
        return Self.dynamicContentRequiresFullCover(state)
    }

    private func renderBlocked(pixelBuffer: CVPixelBuffer?, snapshot: State) -> SharePreviewDelivery {
        if let pixelBuffer {
            let source = CIImage(cvPixelBuffer: pixelBuffer)
            remember(extent: source.extent, streamID: snapshot.streamID)
            return renderBlocked(
                source: source,
                generation: snapshot.generation,
                maskRevision: snapshot.maskRevision
            )
        }

        let extent = currentExtent(streamID: snapshot.streamID) ?? snapshot.lastExtent
        guard let extent else {
            return .clear(generation: snapshot.generation, maskRevision: snapshot.maskRevision)
        }
        let source = CIImage(color: .black).cropped(to: extent)
        return renderBlocked(
            source: source,
            generation: snapshot.generation,
            maskRevision: snapshot.maskRevision
        )
    }

    private func renderBlocked(
        source: CIImage,
        generation: UInt64,
        maskRevision: UInt64
    ) -> SharePreviewDelivery {
        let blocked = SharePreviewCompositor.blocked(source)
        guard let image = context.createCGImage(blocked, from: source.extent) else {
            return .clear(generation: generation, maskRevision: maskRevision)
        }
        return .frame(
            image,
            generation: generation,
            maskRevision: maskRevision,
            isBlocked: true
        )
    }

    private func emitHeartbeatIfNeeded(
        generation: UInt64,
        maskRevision: UInt64,
        streamID: ObjectIdentifier?
    ) {
        stateLock.lock()
        let now = Date()
        let isCurrent = state.streamID == streamID
            && state.generation == generation
            && state.maskRevision == maskRevision
        let shouldEmit = isCurrent && now.timeIntervalSince(state.lastHeartbeatDate) >= 0.4
        if shouldEmit { state.lastHeartbeatDate = now }
        stateLock.unlock()
        if shouldEmit {
            enqueue(.heartbeat(generation: generation, maskRevision: maskRevision))
        }
    }

    private func remember(extent: CGRect, streamID: ObjectIdentifier?) {
        stateLock.lock()
        if state.streamID == streamID { state.lastExtent = extent }
        stateLock.unlock()
    }

    private func currentExtent(streamID: ObjectIdentifier?) -> CGRect? {
        stateLock.lock()
        defer { stateLock.unlock() }
        return state.streamID == streamID ? state.lastExtent : nil
    }

    func enqueue(_ delivery: SharePreviewDelivery) {
        deliveryLock.lock()
        switch delivery {
        case .heartbeat:
            // A heartbeat carries no pixels. It may refresh an otherwise idle session, but it
            // must never erase a pending covered frame or clear event before MainActor sees it.
            if pendingDelivery == nil { pendingDelivery = delivery }
        case .frame, .clear:
            // Visual deliveries are ordered by recency and may replace any older pending item.
            pendingDelivery = delivery
        }
        let shouldSchedule = !deliveryScheduled
        if shouldSchedule { deliveryScheduled = true }
        deliveryLock.unlock()

        if shouldSchedule {
            Task { @MainActor [weak self] in self?.drainDelivery() }
        }
    }

    @MainActor
    private func drainDelivery() {
        deliveryLock.lock()
        let delivery = pendingDelivery
        pendingDelivery = nil
        deliveryLock.unlock()

        if let delivery { onDelivery?(delivery) }

        deliveryLock.lock()
        let needsAnotherPass = pendingDelivery != nil
        if !needsAnotherPass { deliveryScheduled = false }
        deliveryLock.unlock()

        if needsAnotherPass {
            Task { @MainActor [weak self] in self?.drainDelivery() }
        }
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

    private static func machAbsoluteTime(from value: Any?) -> UInt64? {
        if let value = value as? UInt64 { return value }
        if let value = value as? UInt { return UInt64(value) }
        if let value = value as? Int, value >= 0 { return UInt64(value) }
        guard let number = value as? NSNumber else { return nil }
        let decimal = number.decimalValue
        let time = number.uint64Value
        guard decimal >= 0, decimal == Decimal(time) else { return nil }
        return time
    }

    private static func scalar(from value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        return nil
    }
}
