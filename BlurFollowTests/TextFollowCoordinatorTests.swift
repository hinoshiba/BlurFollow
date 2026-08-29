import XCTest
@testable import BlurFollow

final class TextFollowCoordinatorTests: XCTestCase {
    func testTransientWindowUncertaintyDoesNotBecomePersistentOrRestartCapture() {
        XCTAssertTrue(TextFollowWindowRecoveryPolicy.allowsFallbackDuringUncertainty(
            after: nil
        ))
        XCTAssertTrue(TextFollowWindowRecoveryPolicy.allowsFallbackDuringUncertainty(
            after: .visible
        ))
        XCTAssertFalse(TextFollowWindowRecoveryPolicy.shouldRequestFreshFrame(
            whenVisibleAfter: nil
        ))
        XCTAssertFalse(TextFollowWindowRecoveryPolicy.shouldRequestFreshFrame(
            whenVisibleAfter: .visible
        ))
    }

    func testConfirmedUnavailableWindowRequiresFreshFrameWhenItBecomesVisible() {
        XCTAssertFalse(TextFollowWindowRecoveryPolicy.allowsFallbackDuringUncertainty(
            after: .confirmedUnavailable
        ))
        XCTAssertTrue(TextFollowWindowRecoveryPolicy.shouldRequestFreshFrame(
            whenVisibleAfter: .confirmedUnavailable
        ))
    }

    func testDesktopPlacementCanTradeFullWindowScanningCoverForLastMatches() {
        let completed = [UnitRect(x: 0.2, y: 0.3, width: 0.4, height: 0.1)]

        XCTAssertEqual(
            TextFollowDesktopPlacementPolicy.rects(
                state: .scanning,
                completedMatches: completed,
                safetyCoverEnabled: true
            ),
            [.full]
        )
        XCTAssertEqual(
            TextFollowDesktopPlacementPolicy.rects(
                state: .scanning,
                completedMatches: completed,
                safetyCoverEnabled: false
            ),
            completed
        )
        XCTAssertTrue(TextFollowDesktopPlacementPolicy.rects(
            state: .scanning,
            completedMatches: [],
            safetyCoverEnabled: false
        ).isEmpty)
        XCTAssertEqual(
            TextFollowDesktopPlacementPolicy.rects(
                state: .following,
                completedMatches: completed,
                safetyCoverEnabled: true
            ),
            completed
        )
        XCTAssertTrue(TextFollowDesktopPlacementPolicy.rects(
            state: .noMatches,
            completedMatches: [],
            safetyCoverEnabled: false
        ).isEmpty)
        XCTAssertEqual(
            TextFollowDesktopPlacementPolicy.rects(
                state: .noMatches,
                completedMatches: [],
                safetyCoverEnabled: true
            ),
            [.full]
        )

        for unsafeState in [
            TextFollowRuntimeState.connecting,
            .sourceUnavailable,
            .failed
        ] {
            XCTAssertEqual(
                TextFollowDesktopPlacementPolicy.rects(
                    state: unsafeState,
                    completedMatches: completed,
                    safetyCoverEnabled: true
                ),
                [.full]
            )
            XCTAssertEqual(
                TextFollowDesktopPlacementPolicy.rects(
                    state: unsafeState,
                    completedMatches: completed,
                    safetyCoverEnabled: false
                ),
                completed
            )
        }
    }

    func testProvisionalGeometryPreservesMaskForSupersededEmptyResult() {
        let retained = [UnitRect(x: 0.2, y: 0.3, width: 0.4, height: 0.1)]

        XCTAssertEqual(
            TextFollowProvisionalGeometryPolicy.resolve(
                retainedRects: retained,
                provisionalRects: []
            ),
            retained
        )
        XCTAssertTrue(TextFollowProvisionalGeometryPolicy.resolve(
            retainedRects: [],
            provisionalRects: []
        ).isEmpty)
    }

    func testProvisionalGeometryAddsNewPlacementWithoutDroppingCompletedMasks() {
        let retained = [UnitRect(x: 0.2, y: 0.3, width: 0.4, height: 0.1)]
        let provisional = [UnitRect(x: 0.6, y: 0.5, width: 0.2, height: 0.08)]

        XCTAssertEqual(
            TextFollowProvisionalGeometryPolicy.resolve(
                retainedRects: retained,
                provisionalRects: provisional
            ),
            retained + provisional
        )
        XCTAssertEqual(
            TextFollowProvisionalGeometryPolicy.resolve(
                retainedRects: retained,
                provisionalRects: retained + provisional
            ),
            retained + provisional
        )
    }

    func testDesktopPanelPlacementUsesLastTrustedFrameDuringUncertainLookup() throws {
        let lastTrustedFrame = CGRect(x: 120, y: 80, width: 900, height: 700)
        let completed = [UnitRect(x: 0.2, y: 0.3, width: 0.4, height: 0.1)]

        let safe = try XCTUnwrap(TextFollowDesktopPanelPlacement.resolve(
            state: .sourceUnavailable,
            completedMatches: completed,
            safetyCoverEnabled: true,
            windowResolution: .uncertain,
            fallbackWindowFrame: lastTrustedFrame
        ))
        XCTAssertEqual(safe.windowFrame, lastTrustedFrame)
        XCTAssertEqual(safe.normalizedRects, [.full])
        XCTAssertTrue(safe.usesSafetyCover)

        let relaxed = try XCTUnwrap(TextFollowDesktopPanelPlacement.resolve(
            state: .sourceUnavailable,
            completedMatches: completed,
            safetyCoverEnabled: false,
            windowResolution: .uncertain,
            fallbackWindowFrame: lastTrustedFrame
        ))
        XCTAssertEqual(relaxed.windowFrame, lastTrustedFrame)
        XCTAssertEqual(relaxed.normalizedRects, completed)
        XCTAssertFalse(relaxed.usesSafetyCover)

        XCTAssertNil(TextFollowDesktopPanelPlacement.resolve(
            state: .sourceUnavailable,
            completedMatches: completed,
            safetyCoverEnabled: true,
            windowResolution: .uncertain,
            fallbackWindowFrame: nil
        ))

        XCTAssertNil(TextFollowDesktopPanelPlacement.resolve(
            state: .sourceUnavailable,
            completedMatches: completed,
            safetyCoverEnabled: true,
            windowResolution: .unavailable,
            fallbackWindowFrame: lastTrustedFrame
        ))

        XCTAssertNil(TextFollowDesktopPanelPlacement.resolve(
            state: .sourceUnavailable,
            completedMatches: completed,
            safetyCoverEnabled: true,
            windowResolution: .uncertain,
            fallbackWindowFrame: lastTrustedFrame,
            allowsUncertainFallback: false
        ))
    }

    func testRecognitionLanguagePolicyPrioritizesKnownLiteralScriptButStillDetectsEachBlock() {
        XCTAssertEqual(
            TextFollowRecognitionLanguagePolicy.configuration(
                for: [
                    (matchMode: .exact, pattern: "Account"),
                    (matchMode: .prefix, pattern: "Invoice")
                ],
                fallbackPrefersJapanese: true
            ),
            .init(
                recognitionLanguages: ["en-US", "ja-JP"],
                automaticallyDetectsLanguage: true
            )
        )
        XCTAssertEqual(
            TextFollowRecognitionLanguagePolicy.configuration(
                for: [
                    (matchMode: .exact, pattern: "顧客番号"),
                    (matchMode: .prefix, pattern: "請求書")
                ],
                fallbackPrefersJapanese: false
            ),
            .init(
                recognitionLanguages: ["ja-JP", "en-US"],
                automaticallyDetectsLanguage: true
            )
        )
    }

    func testRecognitionLanguagePolicyUsesAutoDetectionForMixedLiteralScripts() {
        XCTAssertEqual(
            TextFollowRecognitionLanguagePolicy.configuration(
                for: [
                    (matchMode: .exact, pattern: "Account"),
                    (matchMode: .prefix, pattern: "顧客番号")
                ],
                fallbackPrefersJapanese: true
            ),
            .init(
                recognitionLanguages: ["ja-JP", "en-US"],
                automaticallyDetectsLanguage: true
            )
        )
        XCTAssertEqual(
            TextFollowRecognitionLanguagePolicy.configuration(
                for: [(matchMode: .exact, pattern: "顧客ID")],
                fallbackPrefersJapanese: false
            ),
            .init(
                recognitionLanguages: ["en-US", "ja-JP"],
                automaticallyDetectsLanguage: true
            )
        )
    }

    func testRecognitionLanguagePolicyUsesAutoDetectionForRegexOrUnknownLiteral() {
        XCTAssertEqual(
            TextFollowRecognitionLanguagePolicy.configuration(
                for: [
                    (matchMode: .exact, pattern: "Invoice"),
                    (matchMode: .regex, pattern: #"INV-\d+"#)
                ],
                fallbackPrefersJapanese: true
            ),
            .init(
                recognitionLanguages: ["ja-JP", "en-US"],
                automaticallyDetectsLanguage: true
            )
        )
        XCTAssertEqual(
            TextFollowRecognitionLanguagePolicy.configuration(
                for: [(matchMode: .exact, pattern: "12345")],
                fallbackPrefersJapanese: false
            ),
            .init(
                recognitionLanguages: ["en-US", "ja-JP"],
                automaticallyDetectsLanguage: true
            )
        )
        XCTAssertEqual(
            TextFollowRecognitionLanguagePolicy.configuration(
                for: [],
                fallbackPrefersJapanese: true
            ),
            .init(
                recognitionLanguages: ["ja-JP", "en-US"],
                automaticallyDetectsLanguage: true
            )
        )
    }

    func testCaptureSizeKeepsNativePixelsUntilTheBounded4KSurface() throws {
        XCTAssertEqual(
            TextFollowCaptureSizePolicy.outputPixelSize(
                sourceSize: CGSize(width: 640, height: 360),
                pointPixelScale: 2
            ),
            .init(width: 1_280, height: 720)
        )

        // 6000 x 4000 native pixels fit inside the 3840 x 2160 ceiling without distortion.
        XCTAssertEqual(
            TextFollowCaptureSizePolicy.outputPixelSize(
                sourceSize: CGSize(width: 3_000, height: 2_000),
                pointPixelScale: 2
            ),
            .init(width: 3_240, height: 2_160)
        )
        XCTAssertEqual(
            TextFollowCaptureSizePolicy.outputPixelSize(
                sourceSize: CGSize(width: 2_560, height: 720),
                pointPixelScale: 2
            ),
            .init(width: 3_840, height: 1_080)
        )
        XCTAssertEqual(
            TextFollowCaptureSizePolicy.outputPixelSize(
                sourceSize: CGSize(width: 1_080, height: 1_920),
                pointPixelScale: 2
            ),
            .init(width: 1_214, height: 2_160)
        )
    }

    func testCaptureQueueKeepsOneSurfaceAvailableBeyondAllRetainedOCRFrames() {
        XCTAssertEqual(TextFollowCaptureSizePolicy.maximumRetainedSurfaceCount, 3)
        XCTAssertEqual(TextFollowCaptureSizePolicy.streamQueueDepth, 4)
        XCTAssertGreaterThan(
            TextFollowCaptureSizePolicy.streamQueueDepth,
            TextFollowCaptureSizePolicy.maximumRetainedSurfaceCount
        )
        XCTAssertLessThanOrEqual(TextFollowCaptureSizePolicy.streamQueueDepth, 8)
    }

    func testCaptureSizeRecoversOriginalPointsFromDownscaledFrameMetadata() {
        XCTAssertEqual(
            TextFollowCaptureSizePolicy.originalSourceSize(
                contentRectInPoints: CGRect(x: 10, y: 5, width: 640, height: 360),
                contentScale: 0.5
            ),
            CGSize(width: 1_280, height: 720)
        )
        XCTAssertNil(TextFollowCaptureSizePolicy.originalSourceSize(
            contentRectInPoints: CGRect(x: 0, y: 0, width: 640, height: 360),
            contentScale: 0
        ))
    }

    func testCaptureResizePolicyOnlyRaisesMateriallyInsufficientResolution() {
        let current = TextFollowCaptureSizePolicy.PixelSize(width: 1_600, height: 900)

        XCTAssertFalse(TextFollowCaptureSizePolicy.requiresResolutionIncrease(
            from: current,
            to: .init(width: 1_740, height: 978)
        ))
        XCTAssertTrue(TextFollowCaptureSizePolicy.requiresResolutionIncrease(
            from: current,
            to: .init(width: 1_760, height: 990)
        ))
        XCTAssertFalse(TextFollowCaptureSizePolicy.requiresResolutionIncrease(
            from: current,
            to: .init(width: 1_280, height: 720)
        ))

        let expected = TextFollowCaptureSizePolicy.PixelSize(width: 3_840, height: 2_160)
        XCTAssertTrue(TextFollowCaptureSizePolicy.matchesOutputSurface(
            width: 3_840,
            height: 2_160,
            expected: expected
        ))
        XCTAssertFalse(TextFollowCaptureSizePolicy.matchesOutputSurface(
            width: 2_560,
            height: 1_440,
            expected: expected
        ))
    }

    func testCaptureSurfaceRejectsUndersizedFramesUntilResizeTargetArrives() {
        let oldSurface = TextFollowCaptureSizePolicy.PixelSize(width: 1_600, height: 900)
        let target = TextFollowCaptureSizePolicy.PixelSize(width: 2_560, height: 1_440)

        XCTAssertFalse(TextFollowCaptureSurfaceAuthorityPolicy.isAuthoritative(
            actualWidth: oldSurface.width,
            actualHeight: oldSurface.height,
            updateTarget: target,
            awaitedTarget: nil
        ))
        XCTAssertFalse(TextFollowCaptureSurfaceAuthorityPolicy.isAuthoritative(
            actualWidth: oldSurface.width,
            actualHeight: oldSurface.height,
            updateTarget: nil,
            awaitedTarget: target
        ))
        XCTAssertTrue(TextFollowCaptureSurfaceAuthorityPolicy.isAuthoritative(
            actualWidth: target.width,
            actualHeight: target.height,
            updateTarget: nil,
            awaitedTarget: target
        ))
        XCTAssertTrue(TextFollowCaptureSurfaceAuthorityPolicy.isAuthoritative(
            actualWidth: oldSurface.width,
            actualHeight: oldSurface.height,
            updateTarget: nil,
            awaitedTarget: nil
        ))
    }

    func testGeometryMapsVisionLowerLeftBoxThroughCaptureContentRect() throws {
        let matcher = try TextPatternMatcher(mode: .exact, pattern: "secret")
        let rects = TextFollowFrameGeometry.matchingNormalizedRects(
            blocks: [TextFollowRecognizedBlock(
                candidates: ["secret"],
                normalizedBoundingBox: CGRect(x: 0.30, y: 0.20, width: 0.10, height: 0.20)
            )],
            matcher: matcher,
            imageSize: CGSize(width: 200, height: 100),
            contentPixelRect: CGRect(x: 50, y: 0, width: 100, height: 100),
            paddingPixels: 0
        )

        let rect = try XCTUnwrap(rects.first)
        XCTAssertEqual(rects.count, 1)
        XCTAssertEqual(rect.x, 0.10, accuracy: 0.000_001)
        XCTAssertEqual(rect.y, 0.20, accuracy: 0.000_001)
        XCTAssertEqual(rect.width, 0.20, accuracy: 0.000_001)
        XCTAssertEqual(rect.height, 0.20, accuracy: 0.000_001)
    }

    func testOneMatcherReturnsEveryDistinctMatchingTextBlock() throws {
        let matcher = try TextPatternMatcher(mode: .prefix, pattern: "Account")
        let blocks = [
            TextFollowRecognizedBlock(
                candidates: ["Account 123"],
                normalizedBoundingBox: CGRect(x: 0.05, y: 0.70, width: 0.30, height: 0.10)
            ),
            TextFollowRecognizedBlock(
                candidates: ["Public"],
                normalizedBoundingBox: CGRect(x: 0.40, y: 0.50, width: 0.20, height: 0.10)
            ),
            TextFollowRecognizedBlock(
                candidates: ["Account 456"],
                normalizedBoundingBox: CGRect(x: 0.55, y: 0.20, width: 0.30, height: 0.10)
            )
        ]

        let rects = TextFollowFrameGeometry.matchingNormalizedRects(
            blocks: blocks,
            matcher: matcher,
            imageSize: CGSize(width: 1_000, height: 800),
            contentPixelRect: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            paddingPixels: 0
        )

        XCTAssertEqual(rects.count, 2)
        XCTAssertEqual(rects[0].x, 0.05, accuracy: 0.000_001)
        XCTAssertEqual(rects[1].x, 0.55, accuracy: 0.000_001)
    }

    func testSeveralRegexHitsAndCandidatesInOneObservationProduceOneRectangle() throws {
        let matcher = try TextPatternMatcher(mode: .regex, pattern: #"token-\d+"#)
        let block = TextFollowRecognizedBlock(
            candidates: ["token-12 and token-34", "token-56"],
            normalizedBoundingBox: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.1)
        )

        let rects = TextFollowFrameGeometry.matchingNormalizedRects(
            blocks: [block],
            matcher: matcher,
            imageSize: CGSize(width: 500, height: 400),
            contentPixelRect: CGRect(x: 0, y: 0, width: 500, height: 400),
            paddingPixels: 0
        )

        XCTAssertEqual(rects.count, 1)
    }

    func testExactMatchUsesTheTenthRecognitionCandidate() throws {
        let matcher = try TextPatternMatcher(mode: .exact, pattern: "secret")
        let block = TextFollowRecognizedBlock(
            candidates: [
                "candidate-1", "candidate-2", "candidate-3", "candidate-4", "candidate-5",
                "candidate-6", "candidate-7", "candidate-8", "candidate-9", "secret"
            ],
            normalizedBoundingBox: CGRect(x: 0.2, y: 0.3, width: 0.4, height: 0.1)
        )

        let rects = TextFollowFrameGeometry.matchingNormalizedRects(
            blocks: [block],
            matcher: matcher,
            imageSize: CGSize(width: 500, height: 400),
            contentPixelRect: CGRect(x: 0, y: 0, width: 500, height: 400),
            paddingPixels: 0
        )

        XCTAssertEqual(rects.count, 1)
    }

    func testGeometryReportsRegexTimeoutInsteadOfPublishingNoMatches() throws {
        let matcher = try TextPatternMatcher(mode: .regex, pattern: #"(a+)+$"#)
        let blocks = [TextFollowRecognizedBlock(
            candidates: [String(repeating: "a", count: 64) + "!"],
            normalizedBoundingBox: CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)
        )]

        let result = TextFollowFrameGeometry.matchingNormalizedRects(
            blocks: blocks,
            matcher: matcher,
            imageSize: CGSize(width: 1_000, height: 800),
            contentPixelRect: CGRect(x: 0, y: 0, width: 1_000, height: 800),
            paddingPixels: 0,
            regexDeadlineUptimeNanoseconds: 0
        )

        XCTAssertNil(result)
    }

    func testDuplicateVisionObservationsWithSameGeometryAreDeduplicated() throws {
        let matcher = try TextPatternMatcher(mode: .exact, pattern: "same")
        let box = CGRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)
        let rects = TextFollowFrameGeometry.matchingNormalizedRects(
            blocks: [
                TextFollowRecognizedBlock(candidates: ["same"], normalizedBoundingBox: box),
                TextFollowRecognizedBlock(candidates: ["same"], normalizedBoundingBox: box)
            ],
            matcher: matcher,
            imageSize: CGSize(width: 500, height: 400),
            contentPixelRect: CGRect(x: 0, y: 0, width: 500, height: 400),
            paddingPixels: 0
        )

        XCTAssertEqual(rects.count, 1)
    }

    func testGeometryClampsPaddingToCapturedContent() throws {
        let matcher = try TextPatternMatcher(mode: .exact, pattern: "edge")
        let rects = TextFollowFrameGeometry.matchingNormalizedRects(
            blocks: [TextFollowRecognizedBlock(
                candidates: ["edge"],
                normalizedBoundingBox: CGRect(x: 0.24, y: 0.02, width: 0.04, height: 0.08)
            )],
            matcher: matcher,
            imageSize: CGSize(width: 400, height: 200),
            contentPixelRect: CGRect(x: 100, y: 0, width: 200, height: 200),
            paddingPixels: 20
        )

        let rect = try XCTUnwrap(rects.first)
        XCTAssertEqual(rect.x, 0, accuracy: 0.000_001)
        XCTAssertEqual(rect.y, 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(rect.width, 0)
        XCTAssertGreaterThan(rect.height, 0)
    }

    func testDirtyFrameCoverageReportsTinyChangeForPixelVerification() throws {
        let content = CGRect(x: 100, y: 50, width: 1_000, height: 800)
        let dirtyRects = [CGRect(x: 620, y: 360, width: 8, height: 28)]

        let coverage = try XCTUnwrap(TextFollowDirtyFramePolicy.coverage(
            of: dirtyRects,
            inside: content
        ))

        XCTAssertEqual(coverage, 0.000_28, accuracy: 0.000_000_1)
        let assessment = TextFollowDirtyFramePolicy.assess(
            dirtyRects: dirtyRects,
            contentPixelRect: content
        )
        XCTAssertTrue(assessment.hasAnyChange)
        XCTAssertFalse(assessment.isUnclassified)
    }

    func testDirtyFrameCoverageReportsPageSizedScroll() throws {
        let content = CGRect(x: 100, y: 50, width: 1_000, height: 800)
        let dirtyRects = [CGRect(x: 100, y: 250, width: 1_000, height: 600)]

        let coverage = try XCTUnwrap(TextFollowDirtyFramePolicy.coverage(
            of: dirtyRects,
            inside: content
        ))

        XCTAssertEqual(coverage, 0.75, accuracy: 0.000_001)
        let assessment = TextFollowDirtyFramePolicy.assess(
            dirtyRects: dirtyRects,
            contentPixelRect: content
        )
        XCTAssertTrue(assessment.hasAnyChange)
        XCTAssertFalse(assessment.isUnclassified)
    }

    func testDirtyFrameCoverageClipsAndDoesNotDoubleCountOverlaps() throws {
        let content = CGRect(x: 100, y: 50, width: 1_000, height: 800)
        let dirtyRects = [
            CGRect(x: 0, y: 0, width: 300, height: 250),
            CGRect(x: 150, y: 100, width: 200, height: 200)
        ]

        let coverage = try XCTUnwrap(TextFollowDirtyFramePolicy.coverage(
            of: dirtyRects,
            inside: content
        ))

        // The clipped union is 57,500 pixels inside an 800,000-pixel content rectangle.
        XCTAssertEqual(coverage, 0.071875, accuracy: 0.000_001)
    }

    func testDirtyFramePolicyTreatsEmptyAsUnchangedAndMissingOrMalformedAsRequiringVerification() {
        let content = CGRect(x: 0, y: 0, width: 1_000, height: 800)

        XCTAssertEqual(
            TextFollowDirtyFramePolicy.assess(
                dirtyRects: nil,
                contentPixelRect: content
            ),
            TextFollowDirtyFramePolicy.Assessment(
                hasAnyChange: true,
                isUnclassified: true
            )
        )
        XCTAssertEqual(
            TextFollowDirtyFramePolicy.assess(
                dirtyRects: [],
                contentPixelRect: content
            ),
            TextFollowDirtyFramePolicy.Assessment(
                hasAnyChange: false,
                isUnclassified: false
            )
        )

        XCTAssertTrue(TextFollowDirtyFramePolicy.assess(
            dirtyRects: [CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)],
            contentPixelRect: content
        ).isUnclassified)
        XCTAssertTrue(TextFollowDirtyFramePolicy.assess(
            dirtyRects: [CGRect(x: 0, y: 0, width: 10, height: 10)],
            contentPixelRect: .zero
        ).isUnclassified)
    }

    func testFrameChangeDetectorProcessesInitialFrameAndSkipsIdenticalDirtyFrames() {
        var detector = TextFollowFrameChangeDetector()
        let staticFrame = makePixelFingerprint(primary: 10, secondary: 20)

        XCTAssertTrue(detector.requiresFingerprint(metadataReportsChange: false))
        let initial = detector.assess(
            fingerprint: staticFrame,
            metadataReportsChange: false
        )
        XCTAssertEqual(initial.kind, .initial)
        XCTAssertTrue(initial.shouldProcess)
        XCTAssertFalse(initial.invalidatesInFlight)

        XCTAssertFalse(detector.requiresFingerprint(metadataReportsChange: false))
        XCTAssertTrue(detector.requiresFingerprint(metadataReportsChange: true))
        for _ in 0..<100 {
            let unchangedDirtyFrame = detector.assess(
                fingerprint: staticFrame,
                metadataReportsChange: true
            )
            XCTAssertEqual(unchangedDirtyFrame.kind, .unchanged)
            XCTAssertFalse(unchangedDirtyFrame.shouldProcess)
            XCTAssertFalse(unchangedDirtyFrame.invalidatesInFlight)
        }
    }

    func testFrameChangeDetectorInvalidatesChangedPixelsAndDimensions() {
        var detector = TextFollowFrameChangeDetector()
        let staticFrame = makePixelFingerprint(primary: 10, secondary: 20)
        let pageScroll = makePixelFingerprint(primary: 12, secondary: 20)
        let resized = TextFollowPixelFingerprint(
            width: 999,
            height: 800,
            primary: 12,
            secondary: 20
        )

        XCTAssertEqual(detector.assess(
            fingerprint: staticFrame,
            metadataReportsChange: false
        ).kind, .initial)

        let changed = detector.assess(
            fingerprint: pageScroll,
            metadataReportsChange: true
        )
        XCTAssertEqual(changed.kind, .changed)
        XCTAssertTrue(changed.shouldProcess)
        XCTAssertTrue(changed.invalidatesInFlight)

        XCTAssertEqual(detector.assess(
            fingerprint: pageScroll,
            metadataReportsChange: true
        ).kind, .unchanged)
        XCTAssertEqual(detector.assess(
            fingerprint: resized,
            metadataReportsChange: true
        ).kind, .changed)
    }

    func testFrameChangeDetectorTreatsUnavailableFingerprintConservatively() {
        var detector = TextFollowFrameChangeDetector()
        let readableFrame = makePixelFingerprint(primary: 10, secondary: 20)

        let initial = detector.assess(
            fingerprint: nil,
            metadataReportsChange: false
        )
        XCTAssertEqual(initial.kind, .initial)
        XCTAssertTrue(initial.shouldProcess)
        XCTAssertFalse(initial.invalidatesInFlight)

        XCTAssertEqual(detector.assess(
            fingerprint: nil,
            metadataReportsChange: false
        ).kind, .unchanged)

        let unknownDirtyFrame = detector.assess(
            fingerprint: nil,
            metadataReportsChange: true
        )
        XCTAssertEqual(unknownDirtyFrame.kind, .unknown)
        XCTAssertTrue(unknownDirtyFrame.shouldProcess)
        XCTAssertTrue(unknownDirtyFrame.invalidatesInFlight)

        XCTAssertEqual(detector.assess(
            fingerprint: readableFrame,
            metadataReportsChange: true
        ).kind, .unknown)
        XCTAssertEqual(detector.assess(
            fingerprint: nil,
            metadataReportsChange: true
        ).kind, .unknown)
    }

    func testFingerprintSchedulingHashesEveryReportedChange() {
        var detector = TextFollowFrameChangeDetector()
        let baseline = makePixelFingerprint(primary: 10, secondary: 20)

        XCTAssertTrue(detector.requiresFingerprint(metadataReportsChange: false))
        XCTAssertEqual(detector.assess(
            fingerprint: baseline,
            metadataReportsChange: false
        ).kind, .initial)

        for _ in 0..<100 {
            XCTAssertFalse(detector.requiresFingerprint(metadataReportsChange: false))
        }
        XCTAssertEqual(detector.assess(
            fingerprint: nil,
            metadataReportsChange: false
        ).kind, .unchanged)
        XCTAssertTrue(detector.requiresFingerprint(metadataReportsChange: true))
        XCTAssertEqual(detector.assess(
            fingerprint: baseline,
            metadataReportsChange: true
        ).kind, .unchanged)
    }

    func testFingerprintBaselineIsResetForEveryGeneration() {
        var detector = TextFollowGenerationFrameChangeDetector()
        let oldFrame = makePixelFingerprint(primary: 10, secondary: 20)
        let newFrame = makePixelFingerprint(primary: 30, secondary: 40)

        XCTAssertTrue(detector.requiresFingerprint(
            metadataReportsChange: false,
            generation: 1
        ))
        XCTAssertEqual(detector.assess(
            fingerprint: oldFrame,
            metadataReportsChange: false,
            generation: 1
        ).kind, .initial)
        XCTAssertEqual(detector.assess(
            fingerprint: oldFrame,
            metadataReportsChange: true,
            generation: 1
        ).kind, .unchanged)

        XCTAssertTrue(detector.requiresFingerprint(
            metadataReportsChange: false,
            generation: 2
        ))
        let newGeneration = detector.assess(
            fingerprint: newFrame,
            metadataReportsChange: false,
            generation: 2
        )
        XCTAssertEqual(newGeneration.kind, .initial)
        XCTAssertTrue(newGeneration.shouldProcess)
        XCTAssertFalse(newGeneration.invalidatesInFlight)

        // A discarded old-generation hash cannot roll generation 2's baseline back.
        XCTAssertEqual(detector.assess(
            fingerprint: oldFrame,
            metadataReportsChange: true,
            generation: 1
        ).kind, .unchanged)
        detector.invalidateBaseline(generation: 1)
        XCTAssertFalse(detector.requiresFingerprint(
            metadataReportsChange: false,
            generation: 2
        ))
        XCTAssertEqual(detector.assess(
            fingerprint: newFrame,
            metadataReportsChange: true,
            generation: 2
        ).kind, .unchanged)
    }

    func testExplicitBaselineInvalidationForcesInitialProcessing() {
        var detector = TextFollowGenerationFrameChangeDetector()
        let frameA = makePixelFingerprint(primary: 10, secondary: 20)

        XCTAssertEqual(detector.assess(
            fingerprint: frameA,
            metadataReportsChange: false,
            generation: 1
        ).kind, .initial)
        XCTAssertEqual(detector.assess(
            fingerprint: frameA,
            metadataReportsChange: true,
            generation: 1
        ).kind, .unchanged)

        detector.invalidateBaseline(generation: 1)
        XCTAssertTrue(detector.requiresFingerprint(
            metadataReportsChange: false,
            generation: 1
        ))
        let reset = detector.assess(
            fingerprint: frameA,
            metadataReportsChange: false,
            generation: 1
        )
        XCTAssertEqual(reset.kind, .initial)
        XCTAssertTrue(reset.shouldProcess)
        XCTAssertFalse(reset.invalidatesInFlight)
    }

    func testPeriodicFingerprintAuditRecoversAChangeWithEmptyDirtyMetadata() {
        var detector = TextFollowGenerationFrameChangeDetector()
        let baseline = makePixelFingerprint(primary: 10, secondary: 20)
        let silentlyChanged = makePixelFingerprint(primary: 30, secondary: 40)
        let interval = TextFollowGenerationFrameChangeDetector
            .periodicAuditIntervalNanoseconds

        XCTAssertTrue(detector.requiresFingerprint(
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 100
        ))
        XCTAssertEqual(detector.assess(
            fingerprint: baseline,
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 100
        ).kind, .initial)

        XCTAssertFalse(detector.requiresFingerprint(
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 100 + interval - 1
        ))
        XCTAssertTrue(detector.requiresFingerprint(
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 100 + interval
        ))
        let recovered = detector.assess(
            fingerprint: silentlyChanged,
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 100 + interval
        )
        XCTAssertEqual(recovered.kind, .changed)
        XCTAssertTrue(recovered.shouldProcess)
        XCTAssertTrue(recovered.invalidatesInFlight)
    }

    func testSettlingAuditProcessesEmptyDirtyFinalScrollFrameBeforeIdle() {
        var detector = TextFollowGenerationFrameChangeDetector()
        let baseline = makePixelFingerprint(primary: 10, secondary: 20)
        let intermediate = makePixelFingerprint(primary: 30, secondary: 40)
        let settled = makePixelFingerprint(primary: 50, secondary: 60)

        XCTAssertEqual(detector.assess(
            fingerprint: baseline,
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 100
        ).kind, .initial)
        XCTAssertEqual(detector.assess(
            fingerprint: intermediate,
            metadataReportsChange: true,
            generation: 1,
            nowUptimeNanoseconds: 200
        ).kind, .changed)

        // The last scroll frame arrives well before the one-second periodic audit and incorrectly
        // reports no dirty rects. It must still invalidate the intermediate OCR result.
        XCTAssertTrue(detector.requiresFingerprint(
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 201
        ))
        let finalFrame = detector.assess(
            fingerprint: settled,
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 201
        )
        XCTAssertEqual(finalFrame.kind, .changed)
        XCTAssertTrue(finalFrame.invalidatesInFlight)

        // One equal empty-dirty frame proves the exact pixels have settled and returns to the
        // low-frequency audit path.
        XCTAssertTrue(detector.requiresFingerprint(
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 202
        ))
        XCTAssertEqual(detector.assess(
            fingerprint: settled,
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 202
        ).kind, .unchanged)
        XCTAssertFalse(detector.requiresFingerprint(
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 203
        ))
    }

    func testPeriodicFingerprintAuditDoesNotRescanUnchangedPixels() {
        var detector = TextFollowGenerationFrameChangeDetector()
        let baseline = makePixelFingerprint(primary: 10, secondary: 20)
        let interval = TextFollowGenerationFrameChangeDetector
            .periodicAuditIntervalNanoseconds

        XCTAssertEqual(detector.assess(
            fingerprint: baseline,
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 1
        ).kind, .initial)
        XCTAssertTrue(detector.requiresFingerprint(
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 1 + interval
        ))
        XCTAssertEqual(detector.assess(
            fingerprint: baseline,
            metadataReportsChange: false,
            generation: 1,
            nowUptimeNanoseconds: 1 + interval
        ).kind, .unchanged)
    }

    func testDirtyFramePolicyBoundsPathologicalRectangleCount() {
        let content = CGRect(x: 0, y: 0, width: 1_000, height: 800)
        let tooManyRects = (0...TextFollowDirtyFramePolicy.maximumDirtyRectCount).map { index in
            CGRect(x: index, y: index, width: 1, height: 1)
        }

        XCTAssertNil(TextFollowDirtyFramePolicy.coverage(
            of: tooManyRects,
            inside: content
        ))
        XCTAssertTrue(TextFollowDirtyFramePolicy.assess(
            dirtyRects: tooManyRects,
            contentPixelRect: content
        ).isUnclassified)
    }

    func testDirtyFramePolicyUsesUnionAcrossDisjointChanges() {
        let content = CGRect(x: 0, y: 0, width: 1_000, height: 1_000)
        let dirtyRects = [
            CGRect(x: 0, y: 0, width: 100, height: 250),
            CGRect(x: 900, y: 750, width: 100, height: 250)
        ]

        let assessment = TextFollowDirtyFramePolicy.assess(
            dirtyRects: dirtyRects,
            contentPixelRect: content
        )
        XCTAssertTrue(assessment.hasAnyChange)
        XCTAssertFalse(assessment.isUnclassified)
    }

    func testFrameSubmissionRejectsFailureStaleGenerationAndReplacedStream() {
        let activeStream = NSObject()
        let replacementStream = NSObject()
        let activeID = ObjectIdentifier(activeStream)
        let replacementID = ObjectIdentifier(replacementStream)

        XCTAssertTrue(TextFollowFrameSubmissionPolicy.accepts(
            currentGeneration: 4,
            inputGeneration: 4,
            activeStreamIdentifier: activeID,
            expectedStreamIdentifier: activeID,
            failed: false,
            hasSpecifications: true
        ))
        XCTAssertFalse(TextFollowFrameSubmissionPolicy.accepts(
            currentGeneration: 4,
            inputGeneration: 4,
            activeStreamIdentifier: activeID,
            expectedStreamIdentifier: activeID,
            failed: true,
            hasSpecifications: true
        ))
        XCTAssertFalse(TextFollowFrameSubmissionPolicy.accepts(
            currentGeneration: 5,
            inputGeneration: 4,
            activeStreamIdentifier: activeID,
            expectedStreamIdentifier: activeID,
            failed: false,
            hasSpecifications: true
        ))
        XCTAssertFalse(TextFollowFrameSubmissionPolicy.accepts(
            currentGeneration: 4,
            inputGeneration: 4,
            activeStreamIdentifier: replacementID,
            expectedStreamIdentifier: activeID,
            failed: false,
            hasSpecifications: true
        ))
    }

    func testLatestFrameMailboxKeepsOnlyNewestPendingFrame() throws {
        var mailbox = TextFollowLatestFrameMailbox<String>()
        let firstSubmission = mailbox.submit("old")
        let newestSubmission = mailbox.submit("newest")

        XCTAssertTrue(firstSubmission.shouldSchedule)
        XCTAssertFalse(newestSubmission.shouldSchedule)
        let item = try XCTUnwrap(mailbox.takeScheduledTurn())
        XCTAssertEqual(item.value, "newest")
        XCTAssertEqual(item.sequence, newestSubmission.sequence)
        XCTAssertFalse(mailbox.finishScheduledTurn())
    }

    func testOrdinarySubmissionDoesNotInvalidateInFlightResultInSameEpoch() throws {
        var mailbox = TextFollowLatestFrameMailbox<String>()
        mailbox.submit("processing")
        let processing = try XCTUnwrap(mailbox.takeScheduledTurn())

        let replacementSubmission = mailbox.submit("replacement")

        XCTAssertFalse(replacementSubmission.shouldSchedule)
        XCTAssertTrue(mailbox.canPublish(processing))
        XCTAssertTrue(mailbox.finishScheduledTurn())
        let replacement = try XCTUnwrap(mailbox.takeScheduledTurn())
        XCTAssertTrue(mailbox.canPublish(replacement))
        XCTAssertFalse(mailbox.finishScheduledTurn())
    }

    func testInvalidatingSubmissionRejectsInFlightResultAndPublishesReplacement() throws {
        var mailbox = TextFollowLatestFrameMailbox<String>()
        mailbox.submit("before-scroll")
        let beforeScroll = try XCTUnwrap(mailbox.takeScheduledTurn())

        let scrolledSubmission = mailbox.submitInvalidatingInFlight("after-scroll")

        XCTAssertFalse(scrolledSubmission.shouldSchedule)
        XCTAssertFalse(mailbox.canPublish(beforeScroll))
        XCTAssertTrue(mailbox.finishScheduledTurn())
        let afterScroll = try XCTUnwrap(mailbox.takeScheduledTurn())
        XCTAssertEqual(afterScroll.value, "after-scroll")
        XCTAssertEqual(afterScroll.sequence, scrolledSubmission.sequence)
        XCTAssertTrue(mailbox.canPublish(afterScroll))
        XCTAssertFalse(mailbox.finishScheduledTurn())
    }

    func testInvalidatingSubmissionReplacesAlreadyPendingFrame() throws {
        var mailbox = TextFollowLatestFrameMailbox<String>()
        mailbox.submit("processing")
        let processing = try XCTUnwrap(mailbox.takeScheduledTurn())
        mailbox.submit("small-animation")

        let scrolledSubmission = mailbox.submitInvalidatingInFlight("after-scroll")

        XCTAssertFalse(mailbox.canPublish(processing))
        XCTAssertTrue(mailbox.finishScheduledTurn())
        let afterScroll = try XCTUnwrap(mailbox.takeScheduledTurn())
        XCTAssertEqual(afterScroll.value, "after-scroll")
        XCTAssertEqual(afterScroll.sequence, scrolledSubmission.sequence)
        XCTAssertFalse(mailbox.finishScheduledTurn())
    }

    func testEveryMaterialFrameRejectsOlderResultsAndKeepsLatestPendingFrame() throws {
        var mailbox = TextFollowLatestFrameMailbox<String>()
        mailbox.submit("before-scroll")
        let beforeScroll = try XCTUnwrap(mailbox.takeScheduledTurn())

        mailbox.submitInvalidatingInFlight("scroll-step-1")
        mailbox.submitInvalidatingInFlight("scroll-step-2")
        let settledSubmission = mailbox.submitInvalidatingInFlight("settled")

        XCTAssertFalse(mailbox.canPublish(beforeScroll))
        XCTAssertTrue(mailbox.finishScheduledTurn())
        let settled = try XCTUnwrap(mailbox.takeScheduledTurn())
        XCTAssertEqual(settled.value, "settled")
        XCTAssertEqual(settled.sequence, settledSubmission.sequence)
        XCTAssertTrue(mailbox.canPublish(settled))
        XCTAssertFalse(mailbox.finishScheduledTurn())
    }

    func testCancelInvalidatesInFlightResultAndClearsPendingFrame() throws {
        var mailbox = TextFollowLatestFrameMailbox<String>()
        mailbox.submit("processing")
        let processing = try XCTUnwrap(mailbox.takeScheduledTurn())
        mailbox.submit("pending")

        mailbox.cancel()

        XCTAssertFalse(mailbox.canPublish(processing))
        XCTAssertEqual(mailbox.latestInvalidatingSequence, mailbox.latestSequence)
        XCTAssertGreaterThan(mailbox.latestInvalidatingSequence, processing.sequence)
        XCTAssertNil(mailbox.takeScheduledTurn())
        XCTAssertFalse(mailbox.finishScheduledTurn())
    }

    func testReconfiguredFrameWaitsForStaleInFlightTurnThenRunsInNewEpoch() throws {
        var mailbox = TextFollowLatestFrameMailbox<String>()
        mailbox.submit("old-generation")
        let staleItem = try XCTUnwrap(mailbox.takeScheduledTurn())

        mailbox.cancel()
        let freshSubmission = mailbox.submit("new-generation")

        XCTAssertFalse(freshSubmission.shouldSchedule)
        XCTAssertFalse(mailbox.canPublish(staleItem))
        XCTAssertTrue(mailbox.finishScheduledTurn())
        let freshItem = try XCTUnwrap(mailbox.takeScheduledTurn())
        XCTAssertTrue(mailbox.canPublish(freshItem))
        XCTAssertEqual(freshItem.value, "new-generation")
        XCTAssertFalse(mailbox.finishScheduledTurn())
    }

    func testRecognitionTurnsRequeueAtTailForFairnessBetweenSessions() throws {
        var first = TextFollowLatestFrameMailbox<String>()
        var second = TextFollowLatestFrameMailbox<String>()
        var dispatchOrder: [String] = []

        if first.submit("first-1").shouldSchedule { dispatchOrder.append("first") }
        if second.submit("second-1").shouldSchedule { dispatchOrder.append("second") }

        XCTAssertEqual(dispatchOrder.removeFirst(), "first")
        let firstItem = try XCTUnwrap(first.takeScheduledTurn())
        XCTAssertEqual(firstItem.value, "first-1")
        XCTAssertFalse(first.submit("first-2").shouldSchedule)
        if first.finishScheduledTurn() { dispatchOrder.append("first") }

        // The next frame for the busy first session goes behind the already waiting second one.
        XCTAssertEqual(dispatchOrder.removeFirst(), "second")
        let secondItem = try XCTUnwrap(second.takeScheduledTurn())
        XCTAssertEqual(secondItem.value, "second-1")
        XCTAssertFalse(second.finishScheduledTurn())

        XCTAssertEqual(dispatchOrder.removeFirst(), "first")
        let nextFirstItem = try XCTUnwrap(first.takeScheduledTurn())
        XCTAssertEqual(nextFirstItem.value, "first-2")
        XCTAssertFalse(first.finishScheduledTurn())
        XCTAssertTrue(dispatchOrder.isEmpty)
    }

    func testEventCursorRejectsOlderGenerationAndOlderFrameResults() {
        var cursor = TextFollowEventCursor()

        XCTAssertTrue(cursor.accepts(generation: 4, sequence: 2))
        XCTAssertFalse(cursor.accepts(generation: 3, sequence: 100))
        XCTAssertFalse(cursor.accepts(generation: 4, sequence: 1))
        XCTAssertTrue(cursor.accepts(generation: 4, sequence: 3))
        XCTAssertTrue(cursor.accepts(generation: 5, sequence: 0))
    }

    func testEventCursorAllowsResultAfterSameFrameScanningButNeverRegressesToScanning() {
        var ordered = TextFollowEventCursor()
        XCTAssertTrue(ordered.accepts(generation: 2, sequence: 7, phase: .scanning))
        XCTAssertTrue(ordered.accepts(generation: 2, sequence: 7, phase: .result))

        var reordered = TextFollowEventCursor()
        XCTAssertTrue(reordered.accepts(generation: 2, sequence: 7, phase: .result))
        XCTAssertFalse(reordered.accepts(generation: 2, sequence: 7, phase: .scanning))
    }

    func testCompletionCursorAcceptsEachNewerCompletionExactlyOnce() {
        var cursor = TextFollowCompletionCursor()

        XCTAssertTrue(cursor.accepts(generation: 4, sequence: 7))
        XCTAssertFalse(cursor.accepts(generation: 4, sequence: 7))
        XCTAssertFalse(cursor.accepts(generation: 4, sequence: 6))
        XCTAssertFalse(cursor.accepts(generation: 3, sequence: 100))
        XCTAssertTrue(cursor.accepts(generation: 4, sequence: 8))
        XCTAssertTrue(cursor.accepts(generation: 5, sequence: 0))
    }

    func testProvisionalCompletionOrderingIsIndependentFromNewerScanningEvent() {
        var events = TextFollowEventCursor()
        var completions = TextFollowCompletionCursor()

        XCTAssertTrue(events.accepts(
            generation: 9,
            sequence: 12,
            phase: .scanning
        ))
        // OCR for frame 10 completed after damage from frame 12. It cannot be authoritative, but
        // it is still the newest completed geometry available to relaxed desktop mode.
        XCTAssertTrue(completions.accepts(generation: 9, sequence: 10))
        XCTAssertFalse(completions.accepts(generation: 9, sequence: 9))
        XCTAssertTrue(completions.accepts(generation: 9, sequence: 11))

        XCTAssertEqual(events.sequence, 12)
        XCTAssertEqual(events.phase, .scanning)
        XCTAssertEqual(completions.sequence, 11)
    }

    func testBoundedRetryCursorUsesDeterministicBackoffAndStopsAtLimit() throws {
        let policy = TextFollowBoundedRetryPolicy(delaysNanoseconds: [10, 20, 40])
        var cursor = TextFollowBoundedRetryCursor()

        guard case .scheduled(let first) = cursor.schedule(generation: 7, policy: policy) else {
            return XCTFail("Expected first retry to be scheduled")
        }
        XCTAssertEqual(first.attempt, 1)
        XCTAssertEqual(first.delayNanoseconds, 10)
        XCTAssertEqual(cursor.schedule(generation: 7, policy: policy), .alreadyPending)
        XCTAssertTrue(cursor.consume(first))
        XCTAssertFalse(cursor.consume(first))

        guard case .scheduled(let second) = cursor.schedule(generation: 7, policy: policy) else {
            return XCTFail("Expected second retry to be scheduled")
        }
        XCTAssertEqual(second.attempt, 2)
        XCTAssertEqual(second.delayNanoseconds, 20)
        XCTAssertTrue(cursor.consume(second))
        guard case .scheduled(let third) = cursor.schedule(generation: 7, policy: policy) else {
            return XCTFail("Expected third retry to be scheduled")
        }
        XCTAssertEqual(third.attempt, 3)
        XCTAssertEqual(third.delayNanoseconds, 40)
        XCTAssertTrue(cursor.consume(third))
        XCTAssertEqual(cursor.schedule(generation: 7, policy: policy), .exhausted)
    }

    func testBoundedRetryResetInvalidatesPendingTicketAndRejectsOlderGeneration() throws {
        let policy = TextFollowBoundedRetryPolicy(delaysNanoseconds: [10, 20])
        var cursor = TextFollowBoundedRetryCursor()
        guard case .scheduled(let stale) = cursor.schedule(generation: 8, policy: policy) else {
            return XCTFail("Expected retry to be scheduled")
        }

        cursor.reset(generation: 8)
        XCTAssertFalse(cursor.consume(stale))
        guard case .scheduled(let restarted) = cursor.schedule(generation: 8, policy: policy) else {
            return XCTFail("Expected retry after reset")
        }
        XCTAssertEqual(restarted.attempt, 1)
        XCTAssertNotEqual(restarted.revision, stale.revision)
        XCTAssertEqual(cursor.schedule(generation: 7, policy: policy), .stale)

        cursor.reset(generation: 9)
        XCTAssertFalse(cursor.consume(restarted))
        guard case .scheduled(let nextGeneration) = cursor.schedule(
            generation: 9,
            policy: policy
        ) else {
            return XCTFail("Expected retry for next generation")
        }
        XCTAssertEqual(nextGeneration.attempt, 1)
    }

    func testNewerFailedFrameReplacesPendingRetryAndRetiresOldTicket() {
        let policy = TextFollowBoundedRetryPolicy(delaysNanoseconds: [10, 20])
        let firstFrame = TextFollowRetryFrameCursor(sequence: 3, epoch: 1)
        let newerFrame = TextFollowRetryFrameCursor(sequence: 4, epoch: 2)
        var cursor = TextFollowBoundedRetryCursor()

        guard case .scheduled(let first) = cursor.schedule(
            generation: 8,
            frameCursor: firstFrame,
            policy: policy
        ) else {
            return XCTFail("Expected first frame retry")
        }
        guard case .scheduled(let replacement) = cursor.schedule(
            generation: 8,
            frameCursor: newerFrame,
            policy: policy
        ) else {
            return XCTFail("Expected newer frame to replace pending retry")
        }

        XCTAssertEqual(replacement.attempt, first.attempt)
        XCTAssertNotEqual(replacement.revision, first.revision)
        XCTAssertFalse(cursor.consume(first))
        XCTAssertTrue(cursor.consume(replacement))
    }

    func testRetryFrameCursorIsRejectedAfterInvalidatingSubmission() throws {
        var mailbox = TextFollowLatestFrameMailbox<String>()
        mailbox.submit("failed-frame")
        let failed = try XCTUnwrap(mailbox.takeScheduledTurn())
        XCTAssertTrue(mailbox.isCurrent(failed.retryFrameCursor))

        mailbox.submitInvalidatingInFlight("newer-frame")

        XCTAssertFalse(mailbox.isCurrent(failed.retryFrameCursor))
    }

    func testRecognitionWatchdogKeysTimeoutToExactRequestGenerationAndEpoch() {
        var cursor = TextFollowRecognitionWatchdogCursor()
        let first = cursor.begin(generation: 4, epoch: 9)
        let unrelated = TextFollowRecognitionWatchdogKey(
            requestID: first.requestID + 1,
            generation: first.generation,
            epoch: first.epoch
        )

        XCTAssertFalse(cursor.markTimedOut(unrelated))
        XCTAssertTrue(cursor.markTimedOut(first))
        XCTAssertFalse(cursor.markTimedOut(first))
        XCTAssertEqual(cursor.finish(first), true)
        XCTAssertNil(cursor.finish(first))

        let replacement = cursor.begin(generation: 4, epoch: 9)
        XCTAssertNotEqual(replacement.requestID, first.requestID)
        XCTAssertFalse(cursor.markTimedOut(first))
        XCTAssertEqual(cursor.finish(replacement), false)
    }

    func testRecognitionWorkerPoolUsesReserveOnlyAfterActiveWorkerTimesOut() throws {
        var cursor = TextFollowRecognitionWorkerPoolCursor(maximumOutstandingWorkers: 2)
        let first = try XCTUnwrap(cursor.beginIfPossible())

        XCTAssertEqual(cursor.activeWorkerCount, 1)
        XCTAssertEqual(cursor.orphanedWorkerCount, 0)
        XCTAssertNil(cursor.beginIfPossible())

        XCTAssertTrue(cursor.markTimedOut(first))
        let replacement = try XCTUnwrap(cursor.beginIfPossible())
        XCTAssertNotEqual(replacement, first)
        XCTAssertEqual(cursor.activeWorkerCount, 1)
        XCTAssertEqual(cursor.orphanedWorkerCount, 1)
        XCTAssertEqual(cursor.outstandingWorkerCount, 2)
        XCTAssertNil(cursor.beginIfPossible())
    }

    func testRecognitionWorkerPoolBoundsOrphansAndLateCompletionReleasesOnlyItsLease() throws {
        var cursor = TextFollowRecognitionWorkerPoolCursor(maximumOutstandingWorkers: 2)
        let first = try XCTUnwrap(cursor.beginIfPossible())
        XCTAssertTrue(cursor.markTimedOut(first))
        let second = try XCTUnwrap(cursor.beginIfPossible())
        XCTAssertTrue(cursor.markTimedOut(second))

        // Two cancellation-ignoring Vision calls consume the hard physical-worker bound.
        XCTAssertEqual(cursor.orphanedWorkerCount, 2)
        XCTAssertTrue(cursor.isExhaustedByOrphans)
        XCTAssertNil(cursor.beginIfPossible())

        // A late completion can release its own lease once, but cannot retire the other orphan.
        XCTAssertTrue(cursor.finish(first))
        XCTAssertFalse(cursor.finish(first))
        XCTAssertEqual(cursor.orphanedWorkerCount, 1)
        XCTAssertFalse(cursor.isExhaustedByOrphans)
        let recovery = try XCTUnwrap(cursor.beginIfPossible())
        XCTAssertEqual(cursor.activeWorkerCount, 1)
        XCTAssertEqual(cursor.orphanedWorkerCount, 1)
        XCTAssertTrue(cursor.finish(recovery))
        XCTAssertEqual(cursor.orphanedWorkerCount, 1)
    }

    func testContinuousInvalidationFailsClosedAndRejectsStaleCompletionReset() {
        var cursor = TextFollowContinuousInvalidationCursor()
        let deadline = TextFollowContinuousInvalidationCursor.failClosedAfterNanoseconds

        XCTAssertEqual(cursor.recordInvalidation(
            generation: 8,
            nowUptimeNanoseconds: 100
        ), .scanning)
        XCTAssertEqual(cursor.recordInvalidation(
            generation: 8,
            nowUptimeNanoseconds: 100 + deadline - 1
        ), .scanning)
        XCTAssertEqual(cursor.recordInvalidation(
            generation: 8,
            nowUptimeNanoseconds: 100 + deadline
        ), .enterFailClosed)
        XCTAssertTrue(cursor.isFailClosed)
        XCTAssertEqual(cursor.recordInvalidation(
            generation: 8,
            nowUptimeNanoseconds: 100 + deadline + 1
        ), .remainFailClosed)

        cursor.recordAuthoritativeCompletion(generation: 7)
        XCTAssertTrue(cursor.isFailClosed)
        cursor.recordAuthoritativeCompletion(generation: 8)
        XCTAssertFalse(cursor.isFailClosed)
        XCTAssertEqual(cursor.recordInvalidation(
            generation: 8,
            nowUptimeNanoseconds: 900
        ), .scanning)
    }

    func testContinuousInvalidationStartsFreshEpisodeForNewGeneration() {
        var cursor = TextFollowContinuousInvalidationCursor()
        let deadline = TextFollowContinuousInvalidationCursor.failClosedAfterNanoseconds

        XCTAssertEqual(cursor.recordInvalidation(
            generation: 3,
            nowUptimeNanoseconds: 10
        ), .scanning)
        XCTAssertEqual(cursor.recordInvalidation(
            generation: 3,
            nowUptimeNanoseconds: 10 + deadline
        ), .enterFailClosed)
        XCTAssertEqual(cursor.recordInvalidation(
            generation: 4,
            nowUptimeNanoseconds: 20 + deadline
        ), .scanning)
        XCTAssertFalse(cursor.isFailClosed)
    }

    func testRecognitionCompletionIsRejectedAfterTerminalStreamFailure() {
        XCTAssertTrue(TextFollowRecognitionCompletionPolicy.isCurrent(
            currentGeneration: 4,
            inputGeneration: 4,
            sessionFailed: false
        ))
        XCTAssertFalse(TextFollowRecognitionCompletionPolicy.isCurrent(
            currentGeneration: 4,
            inputGeneration: 4,
            sessionFailed: true
        ))
        XCTAssertFalse(TextFollowRecognitionCompletionPolicy.isCurrent(
            currentGeneration: 5,
            inputGeneration: 4,
            sessionFailed: false
        ))
    }

    func testFirstUsableFrameWatchdogRejectsRetiredStreamAttempt() {
        var cursor = TextFollowStreamStartupWatchdogCursor()
        let retired = cursor.begin(generation: 3)
        let current = cursor.begin(generation: 3)

        XCTAssertFalse(cursor.expire(retired))
        XCTAssertFalse(cursor.complete(generation: 2))
        XCTAssertTrue(cursor.expire(current))
        XCTAssertFalse(cursor.expire(current))

        let completed = cursor.begin(generation: 4)
        XCTAssertTrue(cursor.complete(generation: 4))
        XCTAssertFalse(cursor.expire(completed))
    }

    func testStreamHeartbeatSlidesOnCompleteOrIdleActivityAndExpiresOnce() {
        var cursor = TextFollowStreamHeartbeatCursor()
        let key = cursor.begin(generation: 8, nowUptimeNanoseconds: 100)

        XCTAssertFalse(cursor.observe(generation: 7, nowUptimeNanoseconds: 130))
        XCTAssertTrue(cursor.observe(generation: 8, nowUptimeNanoseconds: 150))
        XCTAssertEqual(
            cursor.evaluate(
                key,
                nowUptimeNanoseconds: 180,
                timeoutNanoseconds: 100
            ),
            .rearm(afterNanoseconds: 70)
        )
        XCTAssertEqual(
            cursor.evaluate(
                key,
                nowUptimeNanoseconds: 250,
                timeoutNanoseconds: 100
            ),
            .expired
        )
        XCTAssertEqual(
            cursor.evaluate(
                key,
                nowUptimeNanoseconds: 400,
                timeoutNanoseconds: 100
            ),
            .stale
        )
    }

    func testStreamCallbackDispositionRefreshesLivenessOnlyForUsableAuthoritativeFrames() {
        XCTAssertEqual(
            TextFollowStreamCallbackDispositionPolicy.resolve(.malformed),
            .beginInterruptionGrace
        )
        XCTAssertEqual(
            TextFollowStreamCallbackDispositionPolicy.resolve(.completeOrStarted(
                hasUsableFrame: false,
                awaitsConfiguredSurface: false
            )),
            .beginInterruptionGrace
        )
        XCTAssertEqual(
            TextFollowStreamCallbackDispositionPolicy.resolve(.completeOrStarted(
                hasUsableFrame: true,
                awaitsConfiguredSurface: true
            )),
            .deferToSurfaceWatchdog
        )
        XCTAssertEqual(
            TextFollowStreamCallbackDispositionPolicy.resolve(.completeOrStarted(
                hasUsableFrame: true,
                awaitsConfiguredSurface: false
            )),
            .acceptUsableFrame
        )
        XCTAssertEqual(
            TextFollowStreamCallbackDispositionPolicy.resolve(.idle),
            .observeIdle
        )
        XCTAssertEqual(
            TextFollowStreamCallbackDispositionPolicy.resolve(.blankOrSuspended),
            .beginInterruptionGrace
        )
        XCTAssertEqual(
            TextFollowStreamCallbackDispositionPolicy.resolve(.stoppedOrUnknown),
            .failImmediately
        )
    }

    func testStreamHeartbeatRejectsRetiredStreamAttemptAndClockRegression() {
        var cursor = TextFollowStreamHeartbeatCursor()
        let retired = cursor.begin(generation: 3, nowUptimeNanoseconds: 1_000)
        let current = cursor.begin(generation: 3, nowUptimeNanoseconds: 1_100)

        XCTAssertEqual(
            cursor.evaluate(
                retired,
                nowUptimeNanoseconds: 2_000,
                timeoutNanoseconds: 100
            ),
            .stale
        )
        XCTAssertEqual(
            cursor.evaluate(
                current,
                nowUptimeNanoseconds: 1_050,
                timeoutNanoseconds: 100
            ),
            .rearm(afterNanoseconds: 100)
        )
        cursor.cancel()
        XCTAssertFalse(cursor.observe(generation: 3, nowUptimeNanoseconds: 2_100))
    }

    func testStreamHeartbeatResizeGenerationRetiresOldTimerBeforeStartingNewMonitoring() {
        var cursor = TextFollowStreamHeartbeatCursor()
        let preResize = cursor.begin(generation: 8, nowUptimeNanoseconds: 100)

        // The capture session performs this cancellation while advancing its resize generation.
        cursor.cancel()
        let reconfiguredSurface = cursor.begin(generation: 9, nowUptimeNanoseconds: 200)

        XCTAssertEqual(
            cursor.evaluate(
                preResize,
                nowUptimeNanoseconds: 1_000,
                timeoutNanoseconds: 100
            ),
            .stale
        )
        XCTAssertEqual(cursor.activeKey, reconfiguredSurface)
        XCTAssertTrue(cursor.observe(generation: 9, nowUptimeNanoseconds: 250))
        XCTAssertEqual(
            cursor.evaluate(
                reconfiguredSurface,
                nowUptimeNanoseconds: 350,
                timeoutNanoseconds: 100
            ),
            .expired
        )
    }

    func testTransientInterruptionGraceCanRecoverOrExpireExactAttempt() {
        var cursor = TextFollowStreamStartupWatchdogCursor()
        let recovered = cursor.begin(generation: 5)
        cursor.cancel()
        XCTAssertFalse(cursor.expire(recovered))

        let sustained = cursor.begin(generation: 5)
        XCTAssertTrue(cursor.expire(sustained))
        XCTAssertFalse(cursor.expire(sustained))
    }

    func testTransientInterruptionGraceRetiresShorterHeartbeatAndRecoveryStartsFreshOne() {
        var heartbeat = TextFollowStreamHeartbeatCursor()
        var interruption = TextFollowStreamStartupWatchdogCursor()
        let oldHeartbeat = heartbeat.begin(generation: 6, nowUptimeNanoseconds: 100)

        // Model the stateLock-protected interruption claim: its grace now owns the deadline.
        heartbeat.cancel()
        let sustainedInterruption = interruption.begin(generation: 6)
        XCTAssertEqual(
            heartbeat.evaluate(
                oldHeartbeat,
                nowUptimeNanoseconds: 195,
                timeoutNanoseconds: 90
            ),
            .stale
        )
        XCTAssertTrue(interruption.expire(sustainedInterruption))

        let secondOldHeartbeat = heartbeat.begin(
            generation: 6,
            nowUptimeNanoseconds: 300
        )
        heartbeat.cancel()
        let recoveredInterruption = interruption.begin(generation: 6)

        // A usable authoritative frame wins the grace and establishes a fresh heartbeat attempt.
        interruption.cancel()
        let recoveredHeartbeat = heartbeat.begin(
            generation: 6,
            nowUptimeNanoseconds: 350
        )
        XCTAssertFalse(interruption.expire(recoveredInterruption))
        XCTAssertEqual(
            heartbeat.evaluate(
                secondOldHeartbeat,
                nowUptimeNanoseconds: 1_000,
                timeoutNanoseconds: 90
            ),
            .stale
        )
        XCTAssertEqual(heartbeat.activeKey, recoveredHeartbeat)
    }

    func testConfigurationWatchdogSeparatesRetriesForSamePixelTarget() {
        let target = TextFollowCaptureSizePolicy.PixelSize(width: 2_560, height: 1_440)
        var cursor = TextFollowCaptureConfigurationWatchdogCursor()
        let failedAttempt = cursor.begin(generation: 9, targetPixelSize: target)
        XCTAssertTrue(cursor.complete(failedAttempt))

        let retryAttempt = cursor.begin(generation: 9, targetPixelSize: target)
        XCTAssertNotEqual(retryAttempt.attemptID, failedAttempt.attemptID)
        XCTAssertFalse(cursor.expire(failedAttempt))
        XCTAssertTrue(cursor.complete(retryAttempt))
        XCTAssertFalse(cursor.expire(retryAttempt))
    }

    func testConfigurationUpdateRetriesAreBoundedWithBackoff() throws {
        var cursor = TextFollowBoundedRetryCursor()
        let policy = TextFollowBoundedRetryPolicy.configurationUpdate

        for expectedAttempt in 1...policy.delaysNanoseconds.count {
            guard case .scheduled(let ticket) = cursor.schedule(
                generation: 12,
                policy: policy
            ) else {
                return XCTFail("Expected configuration retry \(expectedAttempt)")
            }
            XCTAssertEqual(ticket.attempt, expectedAttempt)
            XCTAssertTrue(cursor.consume(ticket))
        }
        XCTAssertEqual(
            cursor.schedule(generation: 12, policy: policy),
            .exhausted
        )
    }

    func testSharePreviewResolverCompositesEveryOccurrenceWithRuleAppearance() throws {
        let source = try XCTUnwrap(makeIdentity())
        let rule = makeRule(
            identity: source,
            strength: 0.41,
            granularity: 0.67,
            tint: .mint,
            borderEnabled: false,
            cornerRadius: 17
        )
        let rects = [
            UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
            UnitRect(x: 0.6, y: 0.7, width: 0.2, height: 0.08)
        ]

        let snapshot = TextFollowSharePreviewResolver.resolve(
            source: source,
            masksEnabled: true,
            rules: [rule],
            runtimes: [rule.id: TextFollowSharePreviewRuntime(
                identity: source,
                state: .following,
                normalizedRects: rects,
                completedFrameTime: 500
            )]
        )

        XCTAssertFalse(snapshot.requiresFullCover)
        XCTAssertEqual(snapshot.relevantRuleCount, 1)
        XCTAssertEqual(snapshot.minimumCompletedFrameTime, 500)
        XCTAssertEqual(snapshot.maximumCompletedFrameTime, 500)
        XCTAssertEqual(snapshot.regions.map(\.normalizedRect), rects)
        XCTAssertTrue(snapshot.regions.allSatisfy { $0.style == .mosaic })
        XCTAssertTrue(snapshot.regions.allSatisfy { $0.strength == 0.41 })
        XCTAssertTrue(snapshot.regions.allSatisfy { $0.granularity == 0.67 })
        XCTAssertTrue(snapshot.regions.allSatisfy { $0.tint == .mint })
        XCTAssertTrue(snapshot.regions.allSatisfy { !$0.borderEnabled })
        XCTAssertTrue(snapshot.regions.allSatisfy { $0.cornerRadius == 17 })
    }

    func testSharePreviewResolverRequiresExactProcessAndApplicationIdentity() throws {
        let source = try XCTUnwrap(makeIdentity())
        let wrongProcess = try XCTUnwrap(makeIdentity(processID: 78))
        let wrongBundle = try XCTUnwrap(makeIdentity(bundleIdentifier: "com.example.other"))
        let rule = makeRule(identity: source)
        let rect = UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)

        for mismatchedIdentity in [wrongProcess, wrongBundle] {
            let snapshot = TextFollowSharePreviewResolver.resolve(
                source: source,
                masksEnabled: true,
                rules: [rule],
                runtimes: [rule.id: TextFollowSharePreviewRuntime(
                    identity: mismatchedIdentity,
                    state: .following,
                    normalizedRects: [rect]
                )]
            )

            XCTAssertTrue(snapshot.requiresFullCover)
            XCTAssertTrue(snapshot.regions.isEmpty)
        }
    }

    func testSharePreviewResolverMatchesLegacyNameAnchorToBundledSource() throws {
        let source = try XCTUnwrap(makeIdentity())
        var rule = makeRule(identity: source)
        rule.windowAnchor.bundleIdentifier = ""
        rule.windowAnchor.applicationName = source.applicationName
        let rect = UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)

        let snapshot = TextFollowSharePreviewResolver.resolve(
            source: source,
            masksEnabled: true,
            rules: [rule],
            runtimes: [rule.id: TextFollowSharePreviewRuntime(
                identity: source,
                state: .following,
                normalizedRects: [rect],
                completedFrameTime: 900
            )]
        )

        XCTAssertFalse(snapshot.requiresFullCover)
        XCTAssertEqual(snapshot.relevantRuleCount, 1)
        XCTAssertEqual(snapshot.regions.map(\.normalizedRect), [rect])
    }

    func testSharePreviewResolverMatchesLegacyNameRuntimeToBundledSource() throws {
        let source = try XCTUnwrap(makeIdentity())
        let legacyRuntimeIdentity = try XCTUnwrap(makeIdentity(
            bundleIdentifier: "",
            applicationName: source.applicationName
        ))
        let rule = makeRule(identity: source)
        let rect = UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)

        let snapshot = TextFollowSharePreviewResolver.resolve(
            source: source,
            masksEnabled: true,
            rules: [rule],
            runtimes: [rule.id: TextFollowSharePreviewRuntime(
                identity: legacyRuntimeIdentity,
                state: .following,
                normalizedRects: [rect],
                completedFrameTime: 901
            )]
        )

        XCTAssertFalse(snapshot.requiresFullCover)
        XCTAssertEqual(snapshot.relevantRuleCount, 1)
        XCTAssertEqual(snapshot.regions.map(\.normalizedRect), [rect])
        XCTAssertEqual(snapshot.minimumCompletedFrameTime, 901)
    }

    func testSharePreviewResolverFailsClosedUntilMatchingRuleFinishesScan() throws {
        let source = try XCTUnwrap(makeIdentity())
        let rule = makeRule(identity: source)

        for state in [
            TextFollowRuntimeState.reconnectRequired,
            .connecting,
            .scanning,
            .sourceUnavailable,
            .failed
        ] {
            let snapshot = TextFollowSharePreviewResolver.resolve(
                source: source,
                masksEnabled: true,
                rules: [rule],
                runtimes: [rule.id: TextFollowSharePreviewRuntime(
                    identity: source,
                    state: state,
                    normalizedRects: []
                )]
            )
            XCTAssertTrue(snapshot.requiresFullCover, "state: \(state)")
        }

        let completedEmptyScan = TextFollowSharePreviewResolver.resolve(
            source: source,
            masksEnabled: true,
            rules: [rule],
            runtimes: [rule.id: TextFollowSharePreviewRuntime(
                identity: source,
                state: .noMatches,
                normalizedRects: [],
                completedFrameTime: 700
            )]
        )
        XCTAssertFalse(completedEmptyScan.requiresFullCover)
        XCTAssertTrue(completedEmptyScan.regions.isEmpty)
        XCTAssertEqual(completedEmptyScan.minimumCompletedFrameTime, 700)
        XCTAssertEqual(completedEmptyScan.maximumCompletedFrameTime, 700)

        let strictCompletedEmptyScan = TextFollowSharePreviewResolver.resolve(
            source: source,
            masksEnabled: true,
            safetyCoverEnabled: true,
            rules: [rule],
            runtimes: [rule.id: TextFollowSharePreviewRuntime(
                identity: source,
                state: .noMatches,
                normalizedRects: [],
                completedFrameTime: 700
            )]
        )
        XCTAssertTrue(strictCompletedEmptyScan.requiresFullCover)
        XCTAssertTrue(strictCompletedEmptyScan.regions.isEmpty)
        XCTAssertNil(strictCompletedEmptyScan.minimumCompletedFrameTime)
        XCTAssertNil(strictCompletedEmptyScan.maximumCompletedFrameTime)

        let missingFrameTime = TextFollowSharePreviewResolver.resolve(
            source: source,
            masksEnabled: true,
            rules: [rule],
            runtimes: [rule.id: TextFollowSharePreviewRuntime(
                identity: source,
                state: .noMatches,
                normalizedRects: []
            )]
        )
        XCTAssertTrue(missingFrameTime.requiresFullCover)
        XCTAssertNil(missingFrameTime.minimumCompletedFrameTime)
        XCTAssertNil(missingFrameTime.maximumCompletedFrameTime)
    }

    func testSharePreviewResolverDoesNotCompositeStaleRectsWhileRescanning() throws {
        let source = try XCTUnwrap(makeIdentity())
        let rule = makeRule(identity: source)
        let staleRect = UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)

        let snapshot = TextFollowSharePreviewResolver.resolve(
            source: source,
            masksEnabled: true,
            rules: [rule],
            runtimes: [rule.id: TextFollowSharePreviewRuntime(
                identity: source,
                state: .scanning,
                normalizedRects: [staleRect]
            )]
        )

        XCTAssertTrue(snapshot.requiresFullCover)
        XCTAssertTrue(snapshot.regions.isEmpty)
    }

    func testSharePreviewResolverIgnoresRuleForDifferentApplication() throws {
        let source = try XCTUnwrap(makeIdentity())
        let otherWindow = try XCTUnwrap(makeIdentity(
            windowID: 222,
            bundleIdentifier: "com.example.other"
        ))
        let rule = makeRule(identity: otherWindow)

        let snapshot = TextFollowSharePreviewResolver.resolve(
            source: source,
            masksEnabled: true,
            rules: [rule],
            runtimes: [:]
        )

        XCTAssertFalse(snapshot.requiresFullCover)
        XCTAssertEqual(snapshot.relevantRuleCount, 0)
        XCTAssertTrue(snapshot.regions.isEmpty)
    }

    func testSharePreviewResolverFailsClosedForPlausibleStaleSavedRule() throws {
        let source = try XCTUnwrap(makeIdentity())
        let staleIdentity = try XCTUnwrap(makeIdentity(windowID: 999, processID: 888))
        let staleRule = makeRule(identity: staleIdentity)

        let snapshot = TextFollowSharePreviewResolver.resolve(
            source: source,
            masksEnabled: true,
            rules: [staleRule],
            runtimes: [:]
        )

        XCTAssertTrue(snapshot.requiresFullCover)
        XCTAssertEqual(snapshot.relevantRuleCount, 1)
        XCTAssertTrue(snapshot.regions.isEmpty)
    }

    func testSharePreviewResolverFailsClosedWhenStaleWindowTitleChanged() throws {
        let source = try XCTUnwrap(makeIdentity())
        let otherIdentity = try XCTUnwrap(makeIdentity(windowID: 999, processID: 888))
        var otherRule = makeRule(identity: otherIdentity)
        otherRule.windowAnchor.windowTitle = "Other Window"

        let snapshot = TextFollowSharePreviewResolver.resolve(
            source: source,
            masksEnabled: true,
            rules: [otherRule],
            runtimes: [:]
        )

        XCTAssertTrue(snapshot.requiresFullCover)
        XCTAssertEqual(snapshot.relevantRuleCount, 1)
        XCTAssertTrue(snapshot.regions.isEmpty)
    }

    func testSharePreviewResolverIgnoresPickerConnectedOtherWindowFromSameApp() throws {
        let source = try XCTUnwrap(makeIdentity())
        let otherIdentity = try XCTUnwrap(makeIdentity(windowID: 999, processID: 888))
        let otherRule = makeRule(identity: otherIdentity)

        let snapshot = TextFollowSharePreviewResolver.resolve(
            source: source,
            masksEnabled: true,
            rules: [otherRule],
            runtimes: [otherRule.id: TextFollowSharePreviewRuntime(
                identity: otherIdentity,
                state: .following,
                normalizedRects: [UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.1)]
            )]
        )

        XCTAssertFalse(snapshot.requiresFullCover)
        XCTAssertEqual(snapshot.relevantRuleCount, 0)
        XCTAssertTrue(snapshot.regions.isEmpty)
    }

    private func makePixelFingerprint(
        primary: UInt64,
        secondary: UInt64
    ) -> TextFollowPixelFingerprint {
        TextFollowPixelFingerprint(
            width: 1_000,
            height: 800,
            primary: primary,
            secondary: secondary
        )
    }

    private func makeIdentity(
        windowID: CGWindowID = 111,
        processID: pid_t = 77,
        bundleIdentifier: String = "com.example.source",
        applicationName: String = "Source"
    ) -> TextFollowWindowIdentity? {
        TextFollowWindowIdentity(
            windowID: windowID,
            processID: processID,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName
        )
    }

    private func makeRule(
        identity: TextFollowWindowIdentity,
        strength: Double = 0.78,
        granularity: Double = 0.78,
        tint: MaskTint = .cool,
        borderEnabled: Bool = true,
        cornerRadius: Double = 8
    ) -> TextFollowRule {
        let bundleIdentifier: String
        let applicationName: String
        switch identity.applicationIdentity {
        case .bundleIdentifier(let value):
            bundleIdentifier = value
            applicationName = "Source"
        case .applicationName(let value):
            bundleIdentifier = ""
            applicationName = value
        }
        return TextFollowRule(
            name: "Sensitive values",
            matchMode: .exact,
            pattern: "secret",
            windowAnchor: WindowAnchor(
                windowID: identity.windowID,
                bundleIdentifier: bundleIdentifier,
                applicationName: applicationName,
                windowTitle: "Source Window",
                initialFrame: CodableRect(CGRect(x: 0, y: 0, width: 800, height: 600)),
                processID: identity.processID
            ),
            strength: strength,
            granularity: granularity,
            tint: tint,
            borderEnabled: borderEnabled,
            cornerRadius: cornerRadius
        )
    }
}
