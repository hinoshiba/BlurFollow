import CoreImage
import XCTest
@testable import BlurFollow

@MainActor
final class SharePreviewSessionTests: XCTestCase {
    func testFramePresenterUpdatesAttachedLayerAndClearsIt() throws {
        let presenter = SharePreviewFramePresenter()
        let surface = SharePreviewPixelView(frame: CGRect(x: 0, y: 0, width: 32, height: 32))
        presenter.attach(surface)
        let extent = CGRect(x: 0, y: 0, width: 2, height: 2)
        let image = try XCTUnwrap(
            CIContext(options: [.useSoftwareRenderer: true]).createCGImage(
                CIImage(color: .red).cropped(to: extent),
                from: extent
            )
        )

        presenter.present(image)

        XCTAssertNotNil(presenter.image)
        XCTAssertNotNil(surface.layer?.contents)

        presenter.present(nil)

        XCTAssertNil(presenter.image)
        XCTAssertNil(surface.layer?.contents)
    }

    func testLatestFrameSlotKeepsOnlyNewestPendingFrame() {
        var slot = LatestFrameSlot<String>()

        slot.submit("first")
        let newestSequence = slot.submit("newest")

        let item = slot.take()
        XCTAssertEqual(item?.value, "newest")
        XCTAssertEqual(item?.sequence, newestSequence)
        XCTAssertNil(slot.take())
    }

    func testLatestFrameSlotRejectsSupersededInFlightFrame() throws {
        var slot = LatestFrameSlot<String>()

        slot.submit("rendering")
        let rendering = try XCTUnwrap(slot.take())
        slot.submit("replacement")

        XCTAssertFalse(slot.isLatest(rendering.sequence))
        XCTAssertEqual(slot.take()?.value, "replacement")
    }

    func testLatestFrameSlotCancelInvalidatesInFlightFrameAndPendingFrame() throws {
        var slot = LatestFrameSlot<String>()

        slot.submit("rendering")
        let rendering = try XCTUnwrap(slot.take())
        slot.submit("pending")
        slot.cancel()

        XCTAssertFalse(slot.isLatest(rendering.sequence))
        XCTAssertNil(slot.take())
    }

    func testHeartbeatCannotReplacePendingClearDelivery() async throws {
        let processor = SharePreviewFrameProcessor()
        let delivered = expectation(description: "visual delivery wins")
        var received: [String] = []
        processor.onDelivery = { delivery in
            switch delivery {
            case .clear:
                received.append("clear")
            case .heartbeat:
                received.append("heartbeat")
            case .frame:
                received.append("frame")
            }
            delivered.fulfill()
        }

        processor.enqueue(.clear(generation: 1, maskRevision: 1))
        processor.enqueue(.heartbeat(generation: 1, maskRevision: 1))

        await fulfillment(of: [delivered], timeout: 1)
        try await Task.sleep(for: .milliseconds(20))
        XCTAssertEqual(received, ["clear"])
    }

    func testCompletedZeroMatchTextFollowConfigurationDoesNotCoverFrame() {
        XCTAssertFalse(SharePreviewRenderPolicy.isBlocked(
            requiresFullCover: false,
            hasRenderableConfiguration: true
        ))
    }

    func testEmptyPreviewConfigurationAndUnreadyTextFollowStayCovered() {
        XCTAssertTrue(SharePreviewRenderPolicy.isBlocked(
            requiresFullCover: false,
            hasRenderableConfiguration: false
        ))
        XCTAssertTrue(SharePreviewRenderPolicy.isBlocked(
            requiresFullCover: true,
            hasRenderableConfiguration: true
        ))
    }

    func testWindowPinCandidateUsesApplicationNameWhenLegacyAnchorHasNoBundle() {
        let legacyAnchor = WindowAnchor(
            windowID: 41,
            bundleIdentifier: "",
            applicationName: "Source",
            windowTitle: "Document",
            initialFrame: CodableRect(CGRect(x: 0, y: 0, width: 800, height: 600)),
            processID: 1234
        )

        XCTAssertTrue(SharePreviewWindowPinApplicationPolicy.isPlausibleCandidate(
            anchor: legacyAnchor,
            sourceBundleIdentifier: "com.example.source",
            sourceApplicationName: "Source"
        ))
        XCTAssertFalse(SharePreviewWindowPinApplicationPolicy.isPlausibleCandidate(
            anchor: legacyAnchor,
            sourceBundleIdentifier: "com.example.other",
            sourceApplicationName: "Other"
        ))
    }

    func testWindowPinCandidateFailsClosedWithoutComparableApplicationMetadata() {
        let bundleOnlyAnchor = WindowAnchor(
            windowID: 41,
            bundleIdentifier: "com.example.source",
            applicationName: "",
            windowTitle: "Document",
            initialFrame: CodableRect(CGRect(x: 0, y: 0, width: 800, height: 600)),
            processID: 1234
        )

        XCTAssertTrue(SharePreviewWindowPinApplicationPolicy.isPlausibleCandidate(
            anchor: bundleOnlyAnchor,
            sourceBundleIdentifier: "",
            sourceApplicationName: "Source"
        ))
    }

    func testPreviewFrameChangeDetectorIgnoresIdenticalDirtyPixels() {
        let first = TextFollowPixelFingerprint(
            width: 800,
            height: 600,
            primary: 1,
            secondary: 2
        )
        let changed = TextFollowPixelFingerprint(
            width: 800,
            height: 600,
            primary: 3,
            secondary: 4
        )
        var detector = SharePreviewFrameChangeDetector()

        XCTAssertTrue(detector.requiresFingerprint(metadataReportsChange: false))
        XCTAssertEqual(
            detector.assess(fingerprint: first, metadataReportsChange: false),
            .initial
        )
        XCTAssertTrue(detector.requiresFingerprint(metadataReportsChange: true))
        XCTAssertEqual(
            detector.assess(fingerprint: first, metadataReportsChange: true),
            .unchanged
        )
        XCTAssertFalse(detector.requiresFingerprint(metadataReportsChange: false))
        XCTAssertEqual(
            detector.assess(fingerprint: nil, metadataReportsChange: false),
            .unchanged
        )
        XCTAssertEqual(
            detector.assess(fingerprint: changed, metadataReportsChange: true),
            .changed
        )
    }

    func testPreviewFrameChangeDetectorFailsClosedWhenFingerprintIsUnavailable() {
        let fingerprint = TextFollowPixelFingerprint(
            width: 800,
            height: 600,
            primary: 1,
            secondary: 2
        )
        var detector = SharePreviewFrameChangeDetector()

        XCTAssertEqual(
            detector.assess(fingerprint: fingerprint, metadataReportsChange: false),
            .initial
        )
        XCTAssertEqual(
            detector.assess(fingerprint: nil, metadataReportsChange: true),
            .unknown
        )
        XCTAssertEqual(
            detector.assess(fingerprint: fingerprint, metadataReportsChange: true),
            .unknown
        )
    }

    func testPreviewFrameChangeDetectorResetRequiresNewInitialDamage() {
        let fingerprint = TextFollowPixelFingerprint(
            width: 800,
            height: 600,
            primary: 1,
            secondary: 2
        )
        var detector = SharePreviewFrameChangeDetector()
        XCTAssertEqual(
            detector.assess(fingerprint: fingerprint, metadataReportsChange: false),
            .initial
        )
        XCTAssertEqual(
            detector.assess(fingerprint: fingerprint, metadataReportsChange: true),
            .unchanged
        )

        detector.reset()

        XCTAssertTrue(detector.requiresFingerprint(metadataReportsChange: false))
        XCTAssertEqual(
            detector.assess(fingerprint: fingerprint, metadataReportsChange: false),
            .initial
        )
    }

    func testFingerprintAssessmentGateCannotBeReleasedByAnotherGeneration() {
        var gate = SharePreviewFingerprintAssessmentGate()
        gate.begin(generation: 7)

        XCTAssertTrue(gate.requiresFullCover(generation: 7))
        XCTAssertFalse(gate.requiresFullCover(generation: 8))
        XCTAssertFalse(gate.complete(generation: 6))
        XCTAssertTrue(gate.requiresFullCover(generation: 7))

        XCTAssertTrue(gate.complete(generation: 7))
        XCTAssertFalse(gate.requiresFullCover(generation: 7))
    }

    func testFingerprintAssessmentGateResetClosesOnlyActiveStreamLifetime() {
        var gate = SharePreviewFingerprintAssessmentGate()
        gate.begin(generation: 7)
        gate.reset()

        XCTAssertFalse(gate.requiresFullCover(generation: 7))

        gate.begin(generation: 8)
        XCTAssertTrue(gate.requiresFullCover(generation: 8))
        XCTAssertFalse(gate.complete(generation: 7))
        XCTAssertTrue(gate.requiresFullCover(generation: 8))
    }

    func testFingerprintAssessmentKeepsEffectiveCoverUntilUnchangedCommit() {
        var barrier = SharePreviewDynamicContentBarrier(
            relevantTextFollowRuleCount: 1,
            minimumCompletedTextFollowFrameTime: 100,
            maximumCompletedTextFollowFrameTime: 100
        )
        barrier.observeFrame(reportsPixelDamage: true, displayTime: 100)
        var gate = SharePreviewFingerprintAssessmentGate()
        gate.begin(generation: 7)

        XCTAssertTrue(SharePreviewDynamicCoverPolicy.requiresFullCover(
            barrierRequiresFullCover: barrier.snapshot.requiresFullCover,
            fingerprintAssessmentInFlight: gate.requiresFullCover(generation: 7)
        ))

        barrier.observeFrame(reportsPixelDamage: false, displayTime: 200)
        XCTAssertTrue(SharePreviewDynamicCoverPolicy.requiresFullCover(
            barrierRequiresFullCover: barrier.snapshot.requiresFullCover,
            fingerprintAssessmentInFlight: gate.requiresFullCover(generation: 7)
        ))
        XCTAssertTrue(gate.complete(generation: 7))
        XCTAssertFalse(SharePreviewDynamicCoverPolicy.requiresFullCover(
            barrierRequiresFullCover: barrier.snapshot.requiresFullCover,
            fingerprintAssessmentInFlight: gate.requiresFullCover(generation: 7)
        ))
    }

    func testChangedFingerprintCommitsDamageBeforeAssessmentGateReopens() {
        var barrier = SharePreviewDynamicContentBarrier(
            relevantTextFollowRuleCount: 1,
            minimumCompletedTextFollowFrameTime: 100,
            maximumCompletedTextFollowFrameTime: 100
        )
        barrier.observeFrame(reportsPixelDamage: true, displayTime: 100)
        var gate = SharePreviewFingerprintAssessmentGate()
        gate.begin(generation: 7)

        barrier.observeFrame(reportsPixelDamage: true, displayTime: 200)
        XCTAssertTrue(gate.complete(generation: 7))

        XCTAssertTrue(SharePreviewDynamicCoverPolicy.requiresFullCover(
            barrierRequiresFullCover: barrier.snapshot.requiresFullCover,
            fingerprintAssessmentInFlight: gate.requiresFullCover(generation: 7)
        ))
        XCTAssertEqual(barrier.snapshot.latestDamageFrameTime, 200)
    }

    func testDynamicContentBarrierWaitsUntilPreviewAdvancesPastNewerOCR() {
        var barrier = SharePreviewDynamicContentBarrier(
            relevantTextFollowRuleCount: 1,
            minimumCompletedTextFollowFrameTime: 300
        )

        let snapshot = barrier.observeFrame(
            dirtyRects: [CGRect(x: 10, y: 20, width: 30, height: 40)],
            displayTime: 200
        )

        XCTAssertEqual(snapshot.latestDamageFrameTime, 200)
        XCTAssertTrue(snapshot.requiresFullCover)
        XCTAssertTrue(barrier.observeIdleFrame(displayTime: 300))
        XCTAssertFalse(barrier.snapshot.requiresFullCover)
    }

    func testDynamicContentBarrierDoesNotAdvanceDamageForIdenticalDirtyPixels() {
        var barrier = SharePreviewDynamicContentBarrier(
            relevantTextFollowRuleCount: 1,
            minimumCompletedTextFollowFrameTime: 100,
            maximumCompletedTextFollowFrameTime: 100
        )

        XCTAssertTrue(barrier.observeFrame(
            reportsPixelDamage: true,
            displayTime: 200
        ).requiresFullCover)
        XCTAssertTrue(barrier.advanceRecognitionTime(
            relevantTextFollowRuleCount: 1,
            minimumCompletedTextFollowFrameTime: 200,
            maximumCompletedTextFollowFrameTime: 200
        ))

        let unchanged = barrier.observeFrame(
            reportsPixelDamage: false,
            displayTime: 300
        )
        XCTAssertEqual(unchanged.latestDamageFrameTime, 200)
        XCTAssertEqual(unchanged.latestObservedFrameTime, 300)
        XCTAssertFalse(unchanged.requiresFullCover)

        let changed = barrier.observeFrame(
            reportsPixelDamage: true,
            displayTime: 400
        )
        XCTAssertEqual(changed.latestDamageFrameTime, 400)
        XCTAssertTrue(changed.requiresFullCover)
    }

    func testDynamicContentBarrierTreatsMissingOrMalformedDirtyRectsAsDamage() {
        var missing = SharePreviewDynamicContentBarrier(
            relevantTextFollowRuleCount: 1,
            minimumCompletedTextFollowFrameTime: 100
        )
        XCTAssertTrue(missing.observeFrame(
            dirtyRects: nil,
            displayTime: 200
        ).requiresFullCover)

        var malformed = SharePreviewDynamicContentBarrier(
            relevantTextFollowRuleCount: 1,
            minimumCompletedTextFollowFrameTime: 100
        )
        XCTAssertTrue(malformed.observeFrame(
            dirtyRects: [CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)],
            displayTime: 200
        ).requiresFullCover)
    }

    func testDynamicContentBarrierOrdersInitialFrameEvenWithEmptyDirtyRects() {
        var barrier = SharePreviewDynamicContentBarrier(
            relevantTextFollowRuleCount: 1,
            minimumCompletedTextFollowFrameTime: 100
        )

        XCTAssertTrue(barrier.observeFrame(
            dirtyRects: [],
            displayTime: 200
        ).requiresFullCover)

        XCTAssertTrue(barrier.advanceRecognitionTime(
            relevantTextFollowRuleCount: 1,
            minimumCompletedTextFollowFrameTime: 200,
            maximumCompletedTextFollowFrameTime: 200
        ))
        let snapshot = barrier.observeFrame(dirtyRects: [], displayTime: 300)

        XCTAssertEqual(snapshot.latestDamageFrameTime, 200)
        XCTAssertFalse(snapshot.requiresFullCover)
    }

    func testDynamicContentBarrierReleasesWhenEveryRuleCatchesLatestDamage() {
        var barrier = SharePreviewDynamicContentBarrier(
            relevantTextFollowRuleCount: 2,
            minimumCompletedTextFollowFrameTime: 100
        )
        XCTAssertTrue(barrier.observeFrame(
            dirtyRects: [CGRect(x: 0, y: 0, width: 1, height: 1)],
            displayTime: 250
        ).requiresFullCover)

        barrier.updateConfiguration(
            relevantTextFollowRuleCount: 2,
            minimumCompletedTextFollowFrameTime: 249,
            maximumCompletedTextFollowFrameTime: 249
        )
        XCTAssertTrue(barrier.snapshot.requiresFullCover)

        XCTAssertTrue(barrier.advanceRecognitionTime(
            relevantTextFollowRuleCount: 2,
            minimumCompletedTextFollowFrameTime: 250,
            maximumCompletedTextFollowFrameTime: 250
        ))
        XCTAssertFalse(barrier.snapshot.requiresFullCover)
    }

    func testDynamicContentBarrierWaitsForIdleStreamToAdvancePastNewestOCRFrame() {
        var barrier = SharePreviewDynamicContentBarrier(
            relevantTextFollowRuleCount: 2,
            minimumCompletedTextFollowFrameTime: 100,
            maximumCompletedTextFollowFrameTime: 100
        )
        XCTAssertTrue(barrier.observeFrame(
            dirtyRects: [CGRect(x: 0, y: 0, width: 10, height: 10)],
            displayTime: 200
        ).requiresFullCover)

        XCTAssertFalse(barrier.advanceRecognitionTime(
            relevantTextFollowRuleCount: 2,
            minimumCompletedTextFollowFrameTime: 220,
            maximumCompletedTextFollowFrameTime: 260
        ))
        XCTAssertTrue(barrier.snapshot.requiresFullCover)
        XCTAssertTrue(barrier.observeIdleFrame(displayTime: 260))
        XCTAssertFalse(barrier.snapshot.requiresFullCover)
    }

    func testDynamicContentBarrierNeverBlocksWithoutRelevantRules() {
        var barrier = SharePreviewDynamicContentBarrier()

        XCTAssertFalse(barrier.observeFrame(
            dirtyRects: nil,
            displayTime: 500
        ).requiresFullCover)
    }

    func testStaleRerenderCannotReplaceCacheFromNewerMaskRevision() {
        var cache: String? = "cached-revision-8"
        var slot = LatestFrameSlot<String>()
        let pendingSequence = slot.submit("pending-revision-8")

        XCTAssertFalse(SharePreviewRenderRebasePolicy.replaceCacheAndSubmit(
            requestedRevision: 7,
            cachedRevision: 8,
            replacement: "stale-revision-7",
            cache: &cache,
            slot: &slot
        ))

        XCTAssertEqual(cache, "cached-revision-8")
        XCTAssertEqual(slot.latestSequence, pendingSequence)
        XCTAssertEqual(slot.take()?.value, "pending-revision-8")

        XCTAssertTrue(SharePreviewRenderRebasePolicy.replaceCacheAndSubmit(
            requestedRevision: 8,
            cachedRevision: 8,
            replacement: "current-revision-8",
            cache: &cache,
            slot: &slot
        ))
        XCTAssertEqual(cache, "current-revision-8")
        XCTAssertEqual(slot.take()?.value, "current-revision-8")
    }

    func testCachedPreviewSampleMustReachLatestObservedDamageBeforeRebase() {
        XCTAssertFalse(SharePreviewCachedFrameFreshnessPolicy.canRebase(
            cachedDisplayTime: 199,
            latestDamageFrameTime: 200
        ))
        XCTAssertFalse(SharePreviewCachedFrameFreshnessPolicy.canRebase(
            cachedDisplayTime: nil,
            latestDamageFrameTime: 200
        ))
        XCTAssertTrue(SharePreviewCachedFrameFreshnessPolicy.canRebase(
            cachedDisplayTime: 200,
            latestDamageFrameTime: 200
        ))
        XCTAssertTrue(SharePreviewCachedFrameFreshnessPolicy.canRebase(
            cachedDisplayTime: nil,
            latestDamageFrameTime: nil
        ))
    }

    func testUnresolvedSameApplicationWindowPinCoversInsteadOfDisappearing() {
        XCTAssertEqual(
            SharePreviewWindowPinResolutionPolicy.decision(
                for: .uncertain,
                sourceWindowID: 50,
                sourceProcessID: 500
            ),
            .cover
        )
        XCTAssertEqual(
            SharePreviewWindowPinResolutionPolicy.decision(
                for: .unavailable,
                sourceWindowID: 50,
                sourceProcessID: 500
            ),
            .cover
        )

        let exact = TrackedWindowFrame(
            windowID: 50,
            processID: 500,
            appKitFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            isOnScreen: true
        )
        XCTAssertEqual(
            SharePreviewWindowPinResolutionPolicy.decision(
                for: .frame(exact),
                sourceWindowID: 50,
                sourceProcessID: 500
            ),
            .include
        )

        let otherWindow = TrackedWindowFrame(
            windowID: 51,
            processID: 500,
            appKitFrame: CGRect(x: 0, y: 0, width: 800, height: 600),
            isOnScreen: true
        )
        XCTAssertEqual(
            SharePreviewWindowPinResolutionPolicy.decision(
                for: .frame(otherWindow),
                sourceWindowID: 50,
                sourceProcessID: 500
            ),
            .unrelated
        )
    }

    func testRuntimeRecoveryIssueImmediatelyDisablesRenderablePreview() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let blockingFile = directory.appendingPathComponent("not-a-directory")
        let storageURL = blockingFile.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("block writes below this file".utf8).write(to: blockingFile)

        let store = MaskStore(storageURL: storageURL)
        let tracker = WindowTracker()
        let textFollow = TextFollowCoordinator(store: store, tracker: tracker)
        let session = SharePreviewSession(
            store: store,
            tracker: tracker,
            textFollow: textFollow
        )
        XCTAssertFalse(session.savedDataNeedsReview)

        store.add(MaskRegion(
            name: "Triggers persistence failure",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            style: .redact
        ), hasUnlimitedAccess: true)

        XCTAssertNotNil(store.recoveryIssue)
        XCTAssertTrue(session.savedDataNeedsReview)
        XCTAssertTrue(session.frameIsCovered)
        XCTAssertFalse(session.hasRenderablePreview)
    }
}
