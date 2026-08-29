import XCTest
@testable import BlurFollow

final class MaskAccessPolicyTests: XCTestCase {
    func testFreeLimitsAreIndependentForEachCreationKind() {
        XCTAssertEqual(MaskAccessPolicy.freeDisplayMaskLimit, 10)
        XCTAssertEqual(MaskAccessPolicy.freeWindowMaskLimit, 5)
        XCTAssertEqual(MaskAccessPolicy.freeTextFollowRuleLimit, 2)

        for kind in MaskPlanKind.allCases {
            let limit = MaskAccessPolicy.freeLimit(for: kind)
            XCTAssertTrue(MaskAccessPolicy.canCreate(
                kind: kind,
                usage: usage(kind: kind, count: limit - 1),
                hasUnlimitedAccess: false
            ))
            XCTAssertFalse(MaskAccessPolicy.canCreate(
                kind: kind,
                usage: usage(kind: kind, count: limit),
                hasUnlimitedAccess: false
            ))
            XCTAssertFalse(MaskAccessPolicy.canCreate(
                kind: kind,
                usage: usage(kind: kind, count: limit + 3),
                hasUnlimitedAccess: false
            ))
        }
    }

    func testFullCategoryDoesNotConsumeAnotherCategoriesFreeSlots() {
        let displayFull = MaskPlanUsage(
            displayMaskCount: MaskAccessPolicy.freeDisplayMaskLimit,
            windowMaskCount: 0,
            textFollowRuleCount: 0
        )
        XCTAssertFalse(MaskAccessPolicy.canCreate(
            kind: .displayMask,
            usage: displayFull,
            hasUnlimitedAccess: false
        ))
        XCTAssertTrue(MaskAccessPolicy.canCreate(
            kind: .windowMask,
            usage: displayFull,
            hasUnlimitedAccess: false
        ))
        XCTAssertTrue(MaskAccessPolicy.canCreate(
            kind: .textFollowRule,
            usage: displayFull,
            hasUnlimitedAccess: false
        ))
    }

    func testUnlimitedAccessHasNoPlanLimit() {
        let usage = MaskPlanUsage(
            displayMaskCount: 10_000,
            windowMaskCount: 10_000,
            textFollowRuleCount: 10_000
        )
        for kind in MaskPlanKind.allCases {
            XCTAssertTrue(MaskAccessPolicy.canCreate(
                kind: kind,
                usage: usage,
                hasUnlimitedAccess: true
            ))
        }
    }

    func testRemainingFreeSlotsClampsAtZeroForEveryKind() {
        for kind in MaskPlanKind.allCases {
            let limit = MaskAccessPolicy.freeLimit(for: kind)
            XCTAssertEqual(
                MaskAccessPolicy.remainingFreeSlots(for: kind, usage: usage(kind: kind, count: 0)),
                limit
            )
            XCTAssertEqual(
                MaskAccessPolicy.remainingFreeSlots(for: kind, usage: usage(kind: kind, count: limit - 1)),
                1
            )
            XCTAssertEqual(
                MaskAccessPolicy.remainingFreeSlots(for: kind, usage: usage(kind: kind, count: limit)),
                0
            )
            XCTAssertEqual(
                MaskAccessPolicy.remainingFreeSlots(for: kind, usage: usage(kind: kind, count: limit + 9)),
                0
            )
        }
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

    private func usage(kind: MaskPlanKind, count: Int) -> MaskPlanUsage {
        switch kind {
        case .displayMask:
            return MaskPlanUsage(displayMaskCount: count)
        case .windowMask:
            return MaskPlanUsage(windowMaskCount: count)
        case .textFollowRule:
            return MaskPlanUsage(textFollowRuleCount: count)
        }
    }
}

final class TextPatternMatcherTests: XCTestCase {
    func testExactMatchRequiresTheWholeUnmodifiedBlock() throws {
        let matcher = try TextPatternMatcher(mode: .exact, pattern: "Account 123")

        XCTAssertTrue(matcher.matches("Account 123"))
        XCTAssertFalse(matcher.matches("Account 1234"))
        XCTAssertFalse(matcher.matches(" Account 123"))
        XCTAssertFalse(matcher.matches("account 123"))
    }

    func testPrefixMatchRequiresTheUnmodifiedBeginning() throws {
        let matcher = try TextPatternMatcher(mode: .prefix, pattern: "Customer:")

        XCTAssertTrue(matcher.matches("Customer: Example Ltd."))
        XCTAssertTrue(matcher.matches("Customer:"))
        XCTAssertFalse(matcher.matches("Current Customer: Example Ltd."))
    }

    func testContainsMatchSearchesTheUnmodifiedBlockCaseSensitively() throws {
        let matcher = try TextPatternMatcher(mode: .contains, pattern: "test")

        XCTAssertTrue(matcher.matches("test"))
        XCTAssertTrue(matcher.matches("Speed test"))
        XCTAssertTrue(matcher.matches("contest results"))
        XCTAssertFalse(matcher.matches("Speed Test"))
        XCTAssertFalse(matcher.matches("tes t"))
    }

    func testRegularExpressionSearchesAUnicodeTextBlock() throws {
        let matcher = try TextPatternMatcher(mode: .regex, pattern: #"請求番号：INV-\d{4}"#)

        XCTAssertTrue(matcher.matches("お支払い / 請求番号：INV-2048 / 完了"))
        XCTAssertFalse(matcher.matches("請求番号：INV-ABC"))
    }

    func testPathologicalRegularExpressionStopsAtDeadline() throws {
        let matcher = try TextPatternMatcher(mode: .regex, pattern: #"(a+)+$"#)
        let text = String(repeating: "a", count: 64) + "!"
        let start = DispatchTime.now().uptimeNanoseconds
        let result = matcher.matchResult(
            text,
            deadlineUptimeNanoseconds: TextPatternMatcher.deadline(afterNanoseconds: 5_000_000)
        )
        let elapsed = DispatchTime.now().uptimeNanoseconds - start

        // A future ICU may optimize this expression into a fast no-match. Either outcome is safe;
        // the critical invariant is that it cannot monopolize the recognition queue.
        XCTAssertNotEqual(result, .matched)
        XCTAssertLessThan(elapsed, 500_000_000)
        XCTAssertEqual(
            matcher.matchResult(text, deadlineUptimeNanoseconds: 0),
            .timedOut
        )
    }

    func testOneRuleReturnsEveryMatchingBlockIncludingDuplicateText() throws {
        struct Block: Equatable {
            let id: Int
            let text: String
        }
        let blocks = [
            Block(id: 1, text: "Secret: alpha"),
            Block(id: 2, text: "Public"),
            Block(id: 3, text: "Secret: alpha"),
            Block(id: 4, text: "Secret: beta")
        ]
        let matcher = try TextPatternMatcher(mode: .prefix, pattern: "Secret:")

        XCTAssertEqual(
            matcher.matchingIndices(in: blocks.map(\.text)),
            [0, 2, 3]
        )
        XCTAssertEqual(
            matcher.matchingElements(in: blocks, text: \.text).map(\.id),
            [1, 3, 4]
        )

        // The plan counts this saved matcher once, not its three current matches.
        let oneSavedRule = MaskPlanUsage(textFollowRuleCount: 1)
        XCTAssertTrue(MaskAccessPolicy.canCreate(
            kind: .textFollowRule,
            usage: oneSavedRule,
            hasUnlimitedAccess: false
        ))
        XCTAssertFalse(MaskAccessPolicy.canCreate(
            kind: .textFollowRule,
            usage: MaskPlanUsage(textFollowRuleCount: 2),
            hasUnlimitedAccess: false
        ))
    }

    func testRejectsEmptyOversizedAndInvalidRegexPatterns() {
        XCTAssertThrowsError(try TextPatternMatcher(mode: .exact, pattern: "")) { error in
            XCTAssertEqual(error as? TextPatternMatcher.ValidationError, .emptyPattern)
        }

        let oversized = String(repeating: "a", count: TextFollowRule.maximumPatternLength + 1)
        XCTAssertThrowsError(try TextPatternMatcher(mode: .prefix, pattern: oversized)) { error in
            XCTAssertEqual(
                error as? TextPatternMatcher.ValidationError,
                .patternTooLong(maximum: TextFollowRule.maximumPatternLength)
            )
        }

        XCTAssertThrowsError(try TextPatternMatcher(mode: .regex, pattern: "[unterminated")) { error in
            XCTAssertEqual(error as? TextPatternMatcher.ValidationError, .invalidRegularExpression)
        }
    }
}
