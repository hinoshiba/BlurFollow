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
    @Published private(set) var errorMessage: String?
    @Published private(set) var savedDataNeedsReview = false
    /// Changes whenever a user-visible condition requires the mask positions to be checked again.
    @Published private(set) var reviewRevision: UInt64 = 0

    var hasRenderablePreview: Bool {
        !savedDataNeedsReview
            && isRunning && appliedMaskCount > 0 && hasFrame && !frameIsCovered
    }

    private let store: MaskStore
    private let tracker: WindowTracker
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
            let cornerRadius: Double
            let isEnabled: Bool

            init(_ region: MaskRegion) {
                id = region.id
                normalizedRect = region.normalizedRect
                style = region.style
                strength = region.strength
                cornerRadius = region.cornerRadius
                isEnabled = region.isEnabled
            }
        }

        let appearances: [Appearance]
        let savedDataNeedsReview: Bool

        init(regions: [MaskRegion], savedDataNeedsReview: Bool) {
            appearances = regions.map(Appearance.init)
            self.savedDataNeedsReview = savedDataNeedsReview
        }
    }

    init(store: MaskStore, tracker: WindowTracker) {
        self.store = store
        self.tracker = tracker
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

        store.$regions.combineLatest(store.$recoveryIssue).sink { [weak self] regions, recoveryIssue in
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

        let matching = store.recoveryIssue == nil ? matchingRegions(in: store.regions) : []
        if appliedMaskCount != matching.count { appliedMaskCount = matching.count }
        activeMaskSnapshot = ActiveMaskSnapshot(
            regions: matching,
            savedDataNeedsReview: store.recoveryIssue != nil
        )

        let configuration = Self.configuration(for: selection)
        let newStream = SCStream(filter: selection.filter, configuration: configuration, delegate: self)

        // Retain and authorize the stream before awaiting startCapture. MainActor methods can be
        // re-entered while awaiting; generation + stream identity prevent A's frames using B's masks.
        stream = newStream
        activeMaskRevision = processor.activate(
            stream: newStream,
            generation: generation,
            regions: matching
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
        sourceName = String(localized: "No source selected")
        return oldStream
    }

    nonisolated func stream(_ stoppedStream: SCStream, didStopWithError error: Error) {
        Task { @MainActor [weak self] in
            guard let self, self.stream === stoppedStream else { return }
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
            self.errorMessage = error.localizedDescription
            self.invalidateReview()
        }
    }

    private func matchingRegions(in regions: [MaskRegion]) -> [MaskRegion] {
        guard let sourceWindowID, sourceProcessID != 0 else { return [] }
        let candidates = regions.filter { region in
            guard region.isEnabled,
                  region.mode == .window,
                  let anchor = region.windowAnchor else { return false }

            let sameApplication = !sourceBundleIdentifier.isEmpty
                ? anchor.bundleIdentifier == sourceBundleIdentifier
                : anchor.applicationName == sourceApplicationName
            return sameApplication
        }
        // Resolve all matching masks against one WindowServer lookup cache. Several masks often
        // follow the same browser window; querying it once per mask makes live edits visibly stall.
        let trackedFrames = tracker.frames(for: candidates)
        return candidates.filter { region in
            guard let tracked = trackedFrames[region.id],
                  tracked.windowID == sourceWindowID,
                  tracked.processID == sourceProcessID else { return false }
            return true
        }
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

        let matching = needsReview ? [] : matchingRegions(in: regions)
        let snapshot = ActiveMaskSnapshot(
            regions: matching,
            savedDataNeedsReview: needsReview
        )
        guard snapshot != activeMaskSnapshot else { return }
        activeMaskSnapshot = snapshot

        invalidateReview()
        if appliedMaskCount != matching.count { appliedMaskCount = matching.count }
        // Any geometry/style/recovery change invalidates the displayed pixels immediately. A frame
        // rendered with the previous revision must never survive until an idle callback.
        setFrameImage(nil)
        if !frameIsCovered { frameIsCovered = true }
        activeMaskRevision = processor.update(regions: matching)
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
        configuration.showsCursor = true
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true
        configuration.capturesAudio = false
        configuration.shouldBeOpaque = true
        configuration.ignoreShadowsSingleWindow = true
        configuration.ignoreGlobalClipSingleWindow = true
        configuration.streamName = String(localized: "BlurFollow Share Preview")
        if #available(macOS 14.2, *) {
            configuration.includeChildWindows = true
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

final class SharePreviewFrameProcessor: NSObject, SCStreamOutput, @unchecked Sendable {
    static let queue = DispatchQueue(label: "blurfollow.hinoshiba.com.share-preview.frames", qos: .userInteractive)
    private static let renderQueue = DispatchQueue(
        label: "blurfollow.hinoshiba.com.share-preview.render",
        qos: .userInitiated
    )

    var onDelivery: (@MainActor (SharePreviewDelivery) -> Void)?

    private struct State {
        var streamID: ObjectIdentifier?
        var generation: UInt64 = 0
        var maskRevision: UInt64 = 0
        var regions: [MaskRegion] = []
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

    @discardableResult
    func activate(stream: SCStream, generation: UInt64, regions: [MaskRegion]) -> UInt64 {
        stateLock.lock()
        let revision = state.maskRevision &+ 1
        state = State(
            streamID: ObjectIdentifier(stream),
            generation: generation,
            maskRevision: revision,
            regions: regions,
            lastExtent: nil,
            lastHeartbeatDate: .distantPast
        )
        stateLock.unlock()
        cancelPendingRender()
        return revision
    }

    @discardableResult
    func update(regions: [MaskRegion]) -> UInt64 {
        stateLock.lock()
        state.maskRevision &+= 1
        state.regions = regions
        let revision = state.maskRevision
        stateLock.unlock()
        cancelPendingRender()
        return revision
    }

    func deactivate() {
        stateLock.lock()
        state.maskRevision &+= 1
        state.streamID = nil
        state.regions = []
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
            scheduleRender(RenderInput(
                kind: .complete,
                sampleBuffer: sampleBuffer,
                attachments: attachments,
                snapshot: snapshot
            ))
        case .idle:
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

    private func scheduleRender(_ input: RenderInput, clearImmediately: Bool = false) {
        renderLock.lock()
        renderSlot.submit(input)
        // Invalid, blank, suspended, and stopped samples clear synchronously with mailbox ordering.
        // Holding renderLock means an older in-flight render either publishes before this clear or
        // observes its stale token afterwards; it can never replace the clear after this point.
        if clearImmediately {
            enqueue(.clear(
                generation: input.snapshot.generation,
                maskRevision: input.snapshot.maskRevision
            ))
        }
        let shouldSchedule = !renderScheduled
        if shouldSchedule { renderScheduled = true }
        renderLock.unlock()

        if shouldSchedule {
            Self.renderQueue.async { [weak self] in self?.drainRenderSlot() }
        }
    }

    private func cancelPendingRender() {
        renderLock.lock()
        renderSlot.cancel()
        renderLock.unlock()
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
              contentScale.isFinite, contentScale > 0,
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
        let isBlocked = enabledRegions.isEmpty
        let composited = isBlocked ? nil : SharePreviewCompositor.applyingValidated(
            regions: enabledRegions,
            to: source,
            contentRect: contentPixelRect
        )
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

    private static func scalar(from value: Any?) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        if let value = value as? CGFloat { return value }
        if let value = value as? Double { return CGFloat(value) }
        return nil
    }
}
