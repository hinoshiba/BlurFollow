import XCTest
@testable import BlurFollow

final class MaskAccessPolicyTests: XCTestCase {
    func testFreePlanAllowsFiveMasksAndRejectsTheSixth() {
        for count in 0..<MaskAccessPolicy.freeMaskLimit {
            XCTAssertTrue(MaskAccessPolicy.canCreateMask(
                currentCount: count,
                hasUnlimitedAccess: false
            ))
        }

        XCTAssertFalse(MaskAccessPolicy.canCreateMask(
            currentCount: MaskAccessPolicy.freeMaskLimit,
            hasUnlimitedAccess: false
        ))
        XCTAssertFalse(MaskAccessPolicy.canCreateMask(
            currentCount: MaskAccessPolicy.freeMaskLimit + 3,
            hasUnlimitedAccess: false
        ))
    }

    func testUnlimitedAccessHasNoPlanLimit() {
        XCTAssertTrue(MaskAccessPolicy.canCreateMask(
            currentCount: 10_000,
            hasUnlimitedAccess: true
        ))
    }

    func testRemainingFreeMasksClampsAtZero() {
        XCTAssertEqual(MaskAccessPolicy.remainingFreeMasks(currentCount: 0), 5)
        XCTAssertEqual(MaskAccessPolicy.remainingFreeMasks(currentCount: 4), 1)
        XCTAssertEqual(MaskAccessPolicy.remainingFreeMasks(currentCount: 5), 0)
        XCTAssertEqual(MaskAccessPolicy.remainingFreeMasks(currentCount: 9), 0)
    }

    func testVersionsBeforeMonetizationAreGrandfathered() {
        XCTAssertTrue(MaskAccessPolicy.isGrandfathered(originalAppVersion: "0.1.1"))
        XCTAssertTrue(MaskAccessPolicy.isGrandfathered(originalAppVersion: "0.1.10"))
        XCTAssertFalse(MaskAccessPolicy.isGrandfathered(originalAppVersion: "0.2"))
        XCTAssertFalse(MaskAccessPolicy.isGrandfathered(originalAppVersion: "0.2.0"))
        XCTAssertFalse(MaskAccessPolicy.isGrandfathered(originalAppVersion: "0.10.0"))
    }

    func testMalformedOriginalVersionDoesNotGrantAccess() {
        XCTAssertFalse(MaskAccessPolicy.isGrandfathered(originalAppVersion: ""))
        XCTAssertFalse(MaskAccessPolicy.isGrandfathered(originalAppVersion: "0.1.beta"))
        XCTAssertFalse(MaskAccessPolicy.isGrandfathered(originalAppVersion: "0.1.1.0"))
    }
}
