import XCTest
@testable import BlurFollow

@MainActor
final class ReviewPromptPolicyTests: XCTestCase {
    func testRequiresRepeatedPreviewChecksAndSevenDaysExperience() {
        let now = Date(timeIntervalSince1970: 2_000_000)
        let experiencedSince = now.addingTimeInterval(-ReviewPromptPolicy.minimumExperience)

        XCTAssertFalse(ReviewPromptPolicy.shouldRequestReview(
            successfulPreviewCheckCount: 1,
            firstUseDate: experiencedSince,
            lastRequestedVersion: nil,
            lastRequestedDate: nil,
            currentVersion: "0.2.0",
            now: now
        ))
        XCTAssertFalse(ReviewPromptPolicy.shouldRequestReview(
            successfulPreviewCheckCount: 2,
            firstUseDate: now.addingTimeInterval(-60),
            lastRequestedVersion: nil,
            lastRequestedDate: nil,
            currentVersion: "0.2.0",
            now: now
        ))
        XCTAssertTrue(ReviewPromptPolicy.shouldRequestReview(
            successfulPreviewCheckCount: 2,
            firstUseDate: experiencedSince,
            lastRequestedVersion: nil,
            lastRequestedDate: nil,
            currentVersion: "0.2.0",
            now: now
        ))
    }

    func testRequestsAtMostOncePerVersionAndWaitsBetweenVersions() {
        let now = Date(timeIntervalSince1970: 20_000_000)
        let firstUse = now.addingTimeInterval(-ReviewPromptPolicy.minimumExperience)

        XCTAssertFalse(ReviewPromptPolicy.shouldRequestReview(
            successfulPreviewCheckCount: 10,
            firstUseDate: firstUse,
            lastRequestedVersion: "0.2.0",
            lastRequestedDate: now.addingTimeInterval(-ReviewPromptPolicy.minimumRequestInterval),
            currentVersion: "0.2.0",
            now: now
        ))
        XCTAssertFalse(ReviewPromptPolicy.shouldRequestReview(
            successfulPreviewCheckCount: 10,
            firstUseDate: firstUse,
            lastRequestedVersion: "0.2.0",
            lastRequestedDate: now.addingTimeInterval(-60),
            currentVersion: "0.3.0",
            now: now
        ))
        XCTAssertTrue(ReviewPromptPolicy.shouldRequestReview(
            successfulPreviewCheckCount: 10,
            firstUseDate: firstUse,
            lastRequestedVersion: "0.2.0",
            lastRequestedDate: now.addingTimeInterval(-ReviewPromptPolicy.minimumRequestInterval),
            currentVersion: "0.3.0",
            now: now
        ))
    }

    func testEmptyVersionNeverRequestsReview() {
        let now = Date()
        XCTAssertFalse(ReviewPromptPolicy.shouldRequestReview(
            successfulPreviewCheckCount: 20,
            firstUseDate: now.addingTimeInterval(-ReviewPromptPolicy.minimumExperience),
            lastRequestedVersion: nil,
            lastRequestedDate: nil,
            currentVersion: "",
            now: now
        ))
    }

    func testCoordinatorQueuesAfterSecondEligibleCheckAndClearsAfterAttempt() {
        let suiteName = "ReviewPromptPolicyTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let now = Date(timeIntervalSince1970: 30_000_000)
        defaults.set(
            now.addingTimeInterval(-ReviewPromptPolicy.minimumExperience),
            forKey: "review.firstUseDate"
        )
        let coordinator = ReviewPromptCoordinator(
            defaults: defaults,
            versionProvider: { "0.2.0" }
        )

        coordinator.recordSuccessfulPreviewCheck(now: now)
        XCTAssertFalse(coordinator.hasPendingRequest)

        coordinator.recordSuccessfulPreviewCheck(now: now)
        XCTAssertTrue(coordinator.hasPendingRequest)

        coordinator.markRequestAttempted(now: now)
        XCTAssertFalse(coordinator.hasPendingRequest)

        coordinator.recordSuccessfulPreviewCheck(
            now: now.addingTimeInterval(ReviewPromptPolicy.minimumRequestInterval)
        )
        XCTAssertFalse(coordinator.hasPendingRequest, "The same marketing version must not queue again.")
    }
}
