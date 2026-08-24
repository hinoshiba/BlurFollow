import AppKit
import Combine
import CoreGraphics
import ScreenCaptureKit

@MainActor
final class ScreenCapturePermission: ObservableObject {
    @Published private(set) var isAuthorized: Bool
    // Core Graphics has no not-requested/denied status. Set this only from an explicit failure in
    // the current app session so a fresh launch never bypasses the system request or picker.
    @Published private(set) var shouldOfferSystemSettings: Bool

    private let preflightScreenCaptureAccess: () -> Bool

    init(
        preflightScreenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() }
    ) {
        self.preflightScreenCaptureAccess = preflightScreenCaptureAccess
        isAuthorized = preflightScreenCaptureAccess()
        shouldOfferSystemSettings = false
    }

    func refresh() {
        let isAuthorized = preflightScreenCaptureAccess()
        self.isAuthorized = isAuthorized
        if isAuthorized {
            shouldOfferSystemSettings = false
        }
    }

    func recordLegacyRequestResult(_ isGranted: Bool) {
        // A newly granted legacy permission still requires reopening the app. Keep the live
        // authorization status tied to preflight so the UI never claims the current process is ready.
        isAuthorized = preflightScreenCaptureAccess()
        shouldOfferSystemSettings = !isGranted && !isAuthorized
    }

    func recordPickerAuthorization() {
        shouldOfferSystemSettings = false
    }

    func recordDenial() {
        let isAuthorized = preflightScreenCaptureAccess()
        self.isAuthorized = isAuthorized
        shouldOfferSystemSettings = !isAuthorized
    }

    func openSystemSettings() {
        guard shouldOfferSystemSettings else { return }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }

    nonisolated static func isUserDeclinedError(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == SCStreamErrorDomain
            && error.code == SCStreamError.Code.userDeclined.rawValue
    }
}
