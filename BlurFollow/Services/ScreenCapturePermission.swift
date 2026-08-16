import AppKit
import CoreGraphics
import Combine

@MainActor
final class ScreenCapturePermission: ObservableObject {
    @Published private(set) var isAuthorized = CGPreflightScreenCaptureAccess()

    func refresh() {
        isAuthorized = CGPreflightScreenCaptureAccess()
    }

    func requestLegacyAccess() {
        isAuthorized = CGRequestScreenCaptureAccess()
    }

    func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}
