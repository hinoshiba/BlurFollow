import XCTest
import ScreenCaptureKit
@testable import BlurFollow

@MainActor
final class ContentPickerServiceTests: XCTestCase {
    func testBusyRequestCompletesWithoutReplacingActiveOwner() {
        var presentationCount = 0
        let picker = makePicker {
            presentationCount += 1
        }
        var ownerResult: Result<PickedWindow, ContentPickerError>?

        let owner = picker.pickWindow { ownerResult = $0 }

        XCTAssertNotNil(owner)
        XCTAssertEqual(presentationCount, 1)
        XCTAssertTrue(picker.isPicking)

        var busyResult: Result<PickedWindow, ContentPickerError>?
        let rejected = picker.pickWindow { busyResult = $0 }

        XCTAssertNil(rejected)
        XCTAssertEqual(presentationCount, 1)
        XCTAssertNil(ownerResult)
        guard case .failure(let error)? = busyResult, case .busy = error else {
            return XCTFail("A concurrent picker request must complete with the generic busy error")
        }
        XCTAssertEqual(
            error.localizedDescription,
            String(localized: "Another window selection is already in progress.")
        )
    }

    func testOnlyOwningTokenCanCancelActiveRequest() async {
        let picker = makePicker()
        var ownerResult: Result<PickedWindow, ContentPickerError>?
        let owner = picker.pickWindow { ownerResult = $0 }
        let unrelatedRequest = ContentPickerRequestToken()

        XCTAssertNotNil(owner)
        XCTAssertFalse(picker.cancelRequest(unrelatedRequest))
        XCTAssertNil(ownerResult)
        XCTAssertTrue(picker.isPicking)

        XCTAssertTrue(picker.cancelRequest(owner!))
        guard case .failure(let error)? = ownerResult, case .cancelled = error else {
            return XCTFail("The owning request must receive cancellation")
        }
        // ScreenCaptureKit has no programmatic dismiss API, so the service intentionally keeps the
        // picker slot occupied until Apple's eventual callback isolates that late generation.
        XCTAssertTrue(picker.isPicking)

        picker.contentSharingPicker(SCContentSharingPicker.shared, didCancelFor: nil)
        for _ in 0..<5 where picker.isPicking {
            await Task.yield()
        }
        XCTAssertFalse(picker.isPicking)

        var replacementResult: Result<PickedWindow, ContentPickerError>?
        XCTAssertNotNil(picker.pickWindow { replacementResult = $0 })
        XCTAssertNil(replacementResult)
    }

    private func makePicker(present: @escaping () -> Void = {}) -> ContentPickerService {
        ContentPickerService(
            presentPicker: present,
            preflightScreenCaptureAccess: { true },
            requestScreenCaptureAccess: { true }
        )
    }
}
