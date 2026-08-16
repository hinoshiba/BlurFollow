import AppKit
import ScreenCaptureKit

struct WindowCandidate: Identifiable, @unchecked Sendable {
    let id: CGWindowID
    let title: String
    let identityTitle: String
    let applicationName: String
    let bundleIdentifier: String
    let processID: pid_t
    let quartzFrame: CGRect
    let window: SCWindow

    var appKitFrame: CGRect {
        ScreenCoordinates.appKitRect(fromQuartz: quartzFrame)
    }

    var anchor: WindowAnchor {
        WindowAnchor(
            windowID: id,
            bundleIdentifier: bundleIdentifier,
            applicationName: applicationName,
            windowTitle: identityTitle,
            initialFrame: CodableRect(quartzFrame),
            processID: processID
        )
    }

    var icon: NSImage? {
        NSRunningApplication(processIdentifier: processID)?.icon
    }
}
