import XCTest
@testable import BlurFollow

@MainActor
final class SharePreviewSessionTests: XCTestCase {
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

    func testRuntimeRecoveryIssueImmediatelyDisablesRenderablePreview() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let blockingFile = directory.appendingPathComponent("not-a-directory")
        let storageURL = blockingFile.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("block writes below this file".utf8).write(to: blockingFile)

        let store = MaskStore(storageURL: storageURL)
        let session = SharePreviewSession(store: store, tracker: WindowTracker())
        XCTAssertFalse(session.savedDataNeedsReview)

        store.add(MaskRegion(
            name: "Triggers persistence failure",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            style: .redact
        ))

        XCTAssertNotNil(store.recoveryIssue)
        XCTAssertTrue(session.savedDataNeedsReview)
        XCTAssertTrue(session.frameIsCovered)
        XCTAssertFalse(session.hasRenderablePreview)
    }
}
