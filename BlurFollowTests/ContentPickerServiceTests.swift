import XCTest
import ScreenCaptureKit
@testable import BlurFollow

@MainActor
final class ContentPickerServiceTests: XCTestCase {
    func testSystemSettingsRecoveryAppearsOnlyAfterDenialInCurrentSession() {
        let permission = ScreenCapturePermission(
            preflightScreenCaptureAccess: { false }
        )

        XCTAssertFalse(permission.isAuthorized)
        XCTAssertFalse(permission.shouldOfferSystemSettings)

        permission.recordDenial()

        XCTAssertTrue(permission.shouldOfferSystemSettings)
        let freshSession = ScreenCapturePermission(preflightScreenCaptureAccess: { false })
        XCTAssertFalse(freshSession.shouldOfferSystemSettings)
    }

    func testPickerAuthorizationClearsSystemSettingsRecovery() {
        let permission = ScreenCapturePermission(
            preflightScreenCaptureAccess: { false }
        )
        permission.recordDenial()

        permission.recordPickerAuthorization()

        XCTAssertFalse(permission.shouldOfferSystemSettings)
    }

    func testLegacyDenialStopsBeforePickerAndOffersSystemSettings() {
        let permission = ScreenCapturePermission(
            preflightScreenCaptureAccess: { false }
        )
        var presentationCount = 0
        var result: Result<PickedWindow, ContentPickerError>?
        let picker = ContentPickerService(
            presentPicker: { presentationCount += 1 },
            preflightScreenCaptureAccess: { false },
            requestScreenCaptureAccess: { false },
            requiresLegacyScreenCaptureAccess: { true },
            onLegacyAccessRequestCompleted: { permission.recordLegacyRequestResult($0) }
        )

        let request = picker.pickWindow { result = $0 }

        XCTAssertNil(request)
        XCTAssertEqual(presentationCount, 0)
        XCTAssertTrue(permission.shouldOfferSystemSettings)
        guard case .failure(let error)? = result, case .legacyPermissionDenied = error else {
            return XCTFail("A declined legacy request must return the denial-specific error")
        }
    }

    func testLegacyGrantRequiresRestartWithoutOfferingSystemSettings() {
        let permission = ScreenCapturePermission(
            preflightScreenCaptureAccess: { false }
        )
        var result: Result<PickedWindow, ContentPickerError>?
        let picker = ContentPickerService(
            presentPicker: { XCTFail("The picker must wait for the required reopen") },
            preflightScreenCaptureAccess: { false },
            requestScreenCaptureAccess: { true },
            requiresLegacyScreenCaptureAccess: { true },
            onLegacyAccessRequestCompleted: { permission.recordLegacyRequestResult($0) }
        )

        let request = picker.pickWindow { result = $0 }

        XCTAssertNil(request)
        XCTAssertFalse(permission.isAuthorized)
        XCTAssertFalse(permission.shouldOfferSystemSettings)
        guard case .failure(let error)? = result,
              case .legacyPermissionGrantedRestartRequired = error else {
            return XCTFail("A newly granted legacy request must ask only for an app reopen")
        }
    }

    func testPickerUserDeclinedErrorEnablesRecovery() async {
        var accessWasDenied = false
        var result: Result<PickedWindow, ContentPickerError>?
        let picker = ContentPickerService(
            presentPicker: {},
            requiresLegacyScreenCaptureAccess: { false },
            onAccessDenied: { accessWasDenied = true }
        )
        XCTAssertNotNil(picker.pickWindow { result = $0 })
        let error = NSError(
            domain: SCStreamErrorDomain,
            code: SCStreamError.Code.userDeclined.rawValue
        )

        picker.contentSharingPickerStartDidFailWithError(error)
        for _ in 0..<5 where result == nil {
            await Task.yield()
        }

        XCTAssertTrue(accessWasDenied)
        guard case .failure(let pickerError)? = result,
              case .pickerPermissionDenied = pickerError else {
            return XCTFail("A system-picker denial must return the denial-specific error")
        }
    }

    func testPickerCancellationDoesNotEnableRecovery() async {
        var accessWasDenied = false
        var result: Result<PickedWindow, ContentPickerError>?
        let picker = ContentPickerService(
            presentPicker: {},
            requiresLegacyScreenCaptureAccess: { false },
            onAccessDenied: { accessWasDenied = true }
        )
        XCTAssertNotNil(picker.pickWindow { result = $0 })

        picker.contentSharingPicker(SCContentSharingPicker.shared, didCancelFor: nil)
        for _ in 0..<5 where result == nil {
            await Task.yield()
        }

        XCTAssertFalse(accessWasDenied)
        guard case .failure(let pickerError)? = result, case .cancelled = pickerError else {
            return XCTFail("Cancelling the system picker must remain a non-denial outcome")
        }
    }

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
