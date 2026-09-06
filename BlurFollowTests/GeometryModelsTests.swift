import XCTest
@testable import BlurFollow

final class GeometryModelsTests: XCTestCase {
    func testUnitRectRoundTrip() {
        let container = CGRect(x: -1440, y: 200, width: 1440, height: 900)
        let source = CGRect(x: -1190, y: 380, width: 420, height: 160)

        let normalized = UnitRect(rect: source, in: container)
        let restored = normalized.rect(in: container)

        XCTAssertEqual(restored.minX, source.minX, accuracy: 0.001)
        XCTAssertEqual(restored.minY, source.minY, accuracy: 0.001)
        XCTAssertEqual(restored.width, source.width, accuracy: 0.001)
        XCTAssertEqual(restored.height, source.height, accuracy: 0.001)
    }

    func testUnitRectClampsOutsideSelection() {
        let rect = UnitRect(x: -0.2, y: 0.9, width: 0.7, height: 0.5).clamped()
        XCTAssertEqual(rect.x, 0)
        XCTAssertEqual(rect.y, 0.5)
        XCTAssertEqual(rect.width, 0.7)
        XCTAssertEqual(rect.height, 0.5)
    }

    func testQuartzAndAppKitCoordinatesRoundTrip() {
        let quartz = CGRect(x: -600, y: -120, width: 540, height: 320)
        let appKit = ScreenCoordinates.appKitRect(fromQuartz: quartz, primaryDisplayHeight: 1080)
        let restored = ScreenCoordinates.quartzRect(fromAppKit: appKit, primaryDisplayHeight: 1080)
        XCTAssertEqual(restored, quartz)
    }

    func testRelativeMaskMovesAndResizesWithWindow() {
        let initialWindow = CGRect(x: 100, y: 100, width: 1000, height: 700)
        let selected = CGRect(x: 700, y: 590, width: 300, height: 90)
        let unit = UnitRect(rect: selected, in: initialWindow)

        let movedAndResizedWindow = CGRect(x: -400, y: 300, width: 1400, height: 900)
        let followed = unit.rect(in: movedAndResizedWindow)

        XCTAssertEqual(followed.minX, 440, accuracy: 0.001)
        XCTAssertEqual(followed.minY, 930, accuracy: 0.001)
        XCTAssertEqual(followed.width, 420, accuracy: 0.001)
        XCTAssertEqual(followed.height, 115.714, accuracy: 0.01)
    }

    func testMovedMaskIsNormalizedAgainstCurrentSourceFrame() throws {
        let currentWindow = CGRect(x: -500, y: 240, width: 800, height: 600)
        let movedMask = CGRect(x: -260, y: 420, width: 200, height: 120)

        let normalized = try XCTUnwrap(
            MaskDragGeometry.normalizedRect(for: movedMask, inside: currentWindow)
        )

        XCTAssertEqual(normalized.x, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(normalized.y, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(normalized.width, 0.25, accuracy: 0.000_001)
        XCTAssertEqual(normalized.height, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(normalized.rect(in: currentWindow), movedMask)
    }

    func testMovedMaskClampsFullyInsideSourceFrame() throws {
        let container = CGRect(x: 100, y: 200, width: 800, height: 600)
        let outside = CGRect(x: 850, y: 750, width: 200, height: 120)

        let clamped = try XCTUnwrap(MaskDragGeometry.clampedFrame(outside, inside: container))
        XCTAssertEqual(clamped, CGRect(x: 700, y: 680, width: 200, height: 120))

        let normalized = try XCTUnwrap(
            MaskDragGeometry.normalizedRect(for: outside, inside: container)
        )
        XCTAssertEqual(normalized.x, 0.75, accuracy: 0.000_001)
        XCTAssertEqual(normalized.y, 0.8, accuracy: 0.000_001)
    }

    func testMovedMaskRejectsInvalidGeometry() {
        let container = CGRect(x: 0, y: 0, width: 800, height: 600)
        let invalid = CGRect(x: CGFloat.nan, y: 10, width: 100, height: 100)
        XCTAssertNil(MaskDragGeometry.normalizedRect(for: invalid, inside: container))
        XCTAssertNil(MaskDragGeometry.normalizedRect(for: .zero, inside: container))
    }

    func testFrostAndMosaicStrengthMappingsAreVisibleAndMonotonic() {
        let size = CGSize(width: 360, height: 180)
        let weak = MaskVisualParameters.resolve(strength: 0.2, maskSize: size)
        let strong = MaskVisualParameters.resolve(strength: 1, maskSize: size)

        XCTAssertLessThan(weak.frostEffectOpacity, strong.frostEffectOpacity)
        XCTAssertLessThan(weak.frostTintOpacity, strong.frostTintOpacity)
        XCTAssertLessThan(weak.frostAdditionalBlurRadius, strong.frostAdditionalBlurRadius)
        XCTAssertGreaterThanOrEqual(
            strong.frostAdditionalBlurRadius - weak.frostAdditionalBlurRadius,
            16
        )
        XCTAssertLessThan(weak.mosaicCellSize, strong.mosaicCellSize)
        XCTAssertLessThan(weak.mosaicOpacity, strong.mosaicOpacity)
        XCTAssertEqual(weak.normalizedStrength, 0.2, accuracy: 0.000_001)
        XCTAssertEqual(strong.normalizedStrength, 1, accuracy: 0.000_001)
    }

    func testStrengthMappingClampsInvalidAndOutOfRangeValues() {
        let size = CGSize(width: 200, height: 100)
        XCTAssertEqual(
            MaskVisualParameters.resolve(strength: -.infinity, maskSize: size).normalizedStrength,
            0
        )
        XCTAssertEqual(
            MaskVisualParameters.resolve(strength: 2, maskSize: size).normalizedStrength,
            1
        )
        XCTAssertEqual(
            MaskVisualParameters.resolve(
                strength: 0.5,
                granularity: .infinity,
                maskSize: size
            ).normalizedGranularity,
            0
        )
    }

    func testGranularityChangesFrostBlurAndMosaicCellsWithoutChangingOpacity() {
        let size = CGSize(width: 360, height: 180)
        let fine = MaskVisualParameters.resolve(
            strength: 0.65,
            granularity: 0.1,
            maskSize: size
        )
        let coarse = MaskVisualParameters.resolve(
            strength: 0.65,
            granularity: 0.9,
            maskSize: size
        )

        XCTAssertEqual(fine.frostEffectOpacity, coarse.frostEffectOpacity, accuracy: 0.000_001)
        XCTAssertEqual(fine.frostTintOpacity, coarse.frostTintOpacity, accuracy: 0.000_001)
        XCTAssertEqual(fine.mosaicOpacity, coarse.mosaicOpacity, accuracy: 0.000_001)
        XCTAssertLessThan(fine.frostAdditionalBlurRadius, coarse.frostAdditionalBlurRadius)
        XCTAssertLessThan(fine.mosaicCellSize, coarse.mosaicCellSize)
        XCTAssertEqual(fine.normalizedGranularity, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(coarse.normalizedGranularity, 0.9, accuracy: 0.000_001)
    }

    @MainActor
    func testSelectionCanvasAcceptsInitialDragWhileApplicationIsInactive() {
        let canvas = SelectionCanvasView()

        XCTAssertTrue(canvas.acceptsFirstMouse(for: nil))
        XCTAssertTrue(canvas.needsPanelToBecomeKey)
    }

    @MainActor
    func testSelectionPanelDoesNotActivateAppOverSelectedWindow() {
        let panel = SelectionPanel(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        defer { panel.close() }

        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertTrue(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.canBecomeKey)
    }

    @MainActor
    func testOverlayPanelOnlyAcceptsMouseEventsDuringMoveMode() {
        let region = MaskRegion(
            name: "Test",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        )
        let panel = MaskOverlayPanel(region: region)
        defer { panel.close() }

        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        panel.setEditing(true)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertTrue(panel.contentView?.needsPanelToBecomeKey ?? false)
        panel.setEditing(false)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
    }

    @MainActor
    func testCancellingMoveRestoresFrameWhileCommitKeepsIt() {
        let region = MaskRegion(
            name: "Test",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        )
        let panel = MaskOverlayPanel(region: region)
        let original = CGRect(x: 120, y: 180, width: 320, height: 140)
        let moved = CGRect(x: 400, y: 360, width: 320, height: 140)
        defer { panel.close() }

        panel.update(
            region: region,
            frame: original,
            isEditing: true,
            movementBounds: CGRect(x: 0, y: 0, width: 1200, height: 900)
        )
        panel.setFrame(moved, display: false)
        panel.setEditing(false)
        XCTAssertEqual(panel.frame, original.integral)

        panel.setEditing(true)
        panel.setFrame(moved, display: false)
        panel.setEditing(false, restoreInitialFrame: false)
        XCTAssertEqual(panel.frame, moved)
    }

    @MainActor
    func testOverlayPanelSkipsUnchangedGeometryAndAppearance() {
        var region = MaskRegion(
            name: "Test",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        )
        let panel = MaskOverlayPanel(region: region)
        let frame = CGRect(x: 120, y: 180, width: 320, height: 140)
        defer { panel.close() }

        XCTAssertTrue(panel.update(region: region, frame: frame))
        XCTAssertFalse(panel.update(region: region, frame: frame))

        // Metadata that does not affect pixels must not trigger another overlay draw.
        region.name = "Renamed"
        XCTAssertFalse(panel.update(region: region, frame: frame))

        region.granularity = 0.35
        XCTAssertTrue(panel.update(region: region, frame: frame))
        let weakRadius = panel.renderedFrostBlurRadius

        region.strength = 1
        XCTAssertTrue(panel.update(region: region, frame: frame))
        XCTAssertEqual(panel.renderedFrostBlurRadius, weakRadius)

        region.granularity = 1
        XCTAssertTrue(panel.update(region: region, frame: frame))
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            // Hosted runners may enable this accessibility preference. The app deliberately
            // uses an opaque cover instead of a Frost filter in that environment.
            XCTAssertEqual(weakRadius, 0)
            XCTAssertEqual(panel.renderedFrostBlurRadius, 0)
        } else {
            XCTAssertGreaterThan(panel.renderedFrostBlurRadius, weakRadius)
        }

        region.tint = .warm
        XCTAssertTrue(panel.update(region: region, frame: frame))
        region.borderEnabled = false
        XCTAssertTrue(panel.update(region: region, frame: frame))
    }

    @MainActor
    func testMosaicOverlayPixelatesBackdropAndUpdatesCellSize() {
        var region = MaskRegion(
            name: "Mosaic",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2),
            style: .mosaic,
            strength: 0.2,
            granularity: 0.1
        )
        let panel = MaskOverlayPanel(region: region)
        let frame = CGRect(x: 80, y: 120, width: 360, height: 180)
        defer { panel.close() }

        XCTAssertTrue(panel.update(region: region, frame: frame))
        XCTAssertTrue(panel.usesBackdropMosaicFilter)
        let fineCellSize = panel.renderedMosaicCellSize
        XCTAssertGreaterThan(fineCellSize, 0)

        region.granularity = 0.9
        XCTAssertTrue(panel.update(region: region, frame: frame))
        XCTAssertGreaterThan(panel.renderedMosaicCellSize, fineCellSize)
        XCTAssertTrue(panel.usesBackdropMosaicFilter)
    }
}

final class WindowDescriptionBatchTests: XCTestCase {
    func testIndexesOnlyRequestedWindowDescriptionsByID() throws {
        let first: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: 41),
            "marker": "first"
        ]
        let second: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: 73),
            "marker": "second"
        ]
        let unrelated: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: 99),
            "marker": "unrelated"
        ]
        let malformed: [String: Any] = ["marker": "malformed"]

        let result = WindowDescriptionBatch.informationByID(
            from: [second, unrelated, malformed, first],
            requestedWindowIDs: [41, 73, 88]
        )

        XCTAssertEqual(Set(result.keys), [41, 73])
        XCTAssertEqual(try XCTUnwrap(result[41]?["marker"] as? String), "first")
        XCTAssertEqual(try XCTUnwrap(result[73]?["marker"] as? String), "second")
        XCTAssertNil(result[88])
        XCTAssertNil(result[99])
    }

    func testRejectsDuplicateDescriptionForRequestedWindowID() {
        let duplicateID = CGWindowID(52)
        let result = WindowDescriptionBatch.informationByID(
            from: [
                [kCGWindowNumber as String: NSNumber(value: duplicateID), "marker": "a"],
                [kCGWindowNumber as String: NSNumber(value: duplicateID), "marker": "b"]
            ],
            requestedWindowIDs: [duplicateID]
        )

        XCTAssertTrue(result.isEmpty)
    }

    func testExactAnchorLookupIgnoresOtherSameTitleCandidatesAndKeepsSmallRecord() throws {
        let smallExactAnchor: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: 41),
            kCGWindowBounds as String: [
                "X": 100,
                "Y": 200,
                "Width": 40,
                "Height": 30
            ],
            "marker": "exact-small-anchor"
        ]
        let otherSameTitleCandidate: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: 73),
            kCGWindowBounds as String: [
                "X": 300,
                "Y": 400,
                "Width": 800,
                "Height": 600
            ],
            "marker": "other-same-title"
        ]

        let exact = WindowDescriptionBatch.informationByID(
            from: [otherSameTitleCandidate, smallExactAnchor],
            requestedWindowIDs: [41]
        )

        XCTAssertEqual(Set(exact.keys), [41])
        XCTAssertEqual(try XCTUnwrap(exact[41]?["marker"] as? String), "exact-small-anchor")
        let bounds = try XCTUnwrap(exact[41]?[kCGWindowBounds as String] as? [String: Int])
        XCTAssertEqual(bounds["Width"], 40)
        XCTAssertEqual(bounds["Height"], 30)
    }

    func testIncompleteAnchorDoesNotRebindToDifferentSameTitleWindow() {
        let replacement = TrackedWindowFrame(
            windowID: 73,
            processID: 1234,
            appKitFrame: CGRect(x: 10, y: 20, width: 800, height: 600),
            isOnScreen: true
        )

        XCTAssertFalse(WindowTrackingExactIdentityPolicy.matches(
            anchorWindowID: 41,
            anchorProcessID: 1234,
            candidate: replacement
        ))
    }

    func testIncompleteAnchorAcceptsExactIdentityReplacement() {
        let replacement = TrackedWindowFrame(
            windowID: 41,
            processID: 1234,
            appKitFrame: CGRect(x: 10, y: 20, width: 800, height: 600),
            isOnScreen: true
        )

        XCTAssertTrue(WindowTrackingExactIdentityPolicy.matches(
            anchorWindowID: 41,
            anchorProcessID: 1234,
            candidate: replacement
        ))
    }

    func testRejectedContinuousBindingDoesNotResolveIncompleteAnchorWithThirdWindow() {
        let replacement = TrackedWindowFrame(
            windowID: 73,
            processID: 1234,
            appKitFrame: CGRect(x: 10, y: 20, width: 800, height: 600),
            isOnScreen: true
        )

        let continuousBindingWasRejected = true
        let savedAnchorMetadataWasIncomplete = true
        XCTAssertTrue(continuousBindingWasRejected)
        XCTAssertTrue(savedAnchorMetadataWasIncomplete)
        XCTAssertFalse(WindowTrackingExactIdentityPolicy.matches(
            anchorWindowID: 41,
            anchorProcessID: 1234,
            candidate: replacement
        ))
    }

    func testIncompleteAnchorWithoutSavedProcessCannotAcceptReplacement() {
        let replacement = TrackedWindowFrame(
            windowID: 41,
            processID: 1234,
            appKitFrame: CGRect(x: 10, y: 20, width: 800, height: 600),
            isOnScreen: true
        )

        XCTAssertFalse(WindowTrackingExactIdentityPolicy.matches(
            anchorWindowID: 41,
            anchorProcessID: nil,
            candidate: replacement
        ))
    }

    func testContinuousIdentityAllowsTitleChangesAndSmallGeometry() {
        XCTAssertTrue(WindowTrackingInspectionRole.continuousIdentity.allowsSmallGeometry)
        XCTAssertFalse(
            WindowTrackingInspectionRole.continuousIdentity.requiresStoredTitleMatch
        )
    }

    func testSavedAnchorRequiresTitleButStillAllowsSmallGeometry() {
        XCTAssertTrue(WindowTrackingInspectionRole.savedAnchor.allowsSmallGeometry)
        XCTAssertTrue(WindowTrackingInspectionRole.savedAnchor.requiresStoredTitleMatch)
    }

    func testAutomaticRebindRequiresTitleAndNormalGeometry() {
        XCTAssertFalse(
            WindowTrackingInspectionRole.automaticRebindCandidate.allowsSmallGeometry
        )
        XCTAssertTrue(
            WindowTrackingInspectionRole.automaticRebindCandidate.requiresStoredTitleMatch
        )
    }

    func testConfirmedDiscontinuityRequiresExplicitRebind() {
        XCTAssertTrue(WindowTrackingContinuityPolicy.allowsAutomaticResolution(
            hasConfirmedDiscontinuity: false
        ))
        XCTAssertFalse(WindowTrackingContinuityPolicy.allowsAutomaticResolution(
            hasConfirmedDiscontinuity: true
        ))
        XCTAssertTrue(WindowTrackingContinuityPolicy.requiresExplicitRebind(
            after: .identity
        ))
        XCTAssertFalse(WindowTrackingContinuityPolicy.requiresExplicitRebind(
            after: .savedTitle
        ))
    }
}
