import AppKit
import Combine
import ScreenCaptureKit

struct PickedWindow: @unchecked Sendable {
    let candidate: WindowCandidate
    let filter: SCContentFilter
}

struct ContentPickerRequestToken: Hashable, Sendable {
    fileprivate let id: UUID

    init() {
        id = UUID()
    }
}

/// Remembers the BlurFollow window that initiated a system-picker flow so callers can return
/// focus only after their follow-up work (such as selecting a region) has finished.
@MainActor
struct AppWindowReturnTarget {
    private let activateApplication: () -> Void
    private let orderWindowFront: () -> Void

    init() {
        self.init(window: NSApp.keyWindow)
    }

    init(window: NSWindow?) {
        activateApplication = {
            // Returning here is the direct continuation of the user's Window Pin action. Use the
            // forceful API supported by every deployment target so the app does not remain behind
            // the window selected in ScreenCaptureKit's picker.
            NSApp.activate(ignoringOtherApps: true)
        }
        orderWindowFront = { [weak window] in
            window?.makeKeyAndOrderFront(nil)
        }
    }

    init(
        activateApplication: @escaping () -> Void,
        orderWindowFront: @escaping () -> Void
    ) {
        self.activateApplication = activateApplication
        self.orderWindowFront = orderWindowFront
    }

    func restore() {
        activateApplication()
        orderWindowFront()
    }
}

enum ContentPickerError: LocalizedError {
    case cancelled
    case busy
    case noWindow
    case ambiguousWindow
    case legacyPermissionDenied
    case legacyPermissionGrantedRestartRequired
    case pickerPermissionDenied
    case system(Error)

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return String(localized: "Window selection was cancelled.")
        case .busy:
            return String(localized: "Another window selection is already in progress.")
        case .noWindow:
            return String(localized: "The selected window could not be identified.")
        case .ambiguousWindow:
            return String(localized: "More than one window matched the selection. Bring the target window forward and try again.")
        case .legacyPermissionDenied:
            return String(localized: "Screen Recording access was not allowed. Enable it in System Settings, then reopen BlurFollow.")
        case .legacyPermissionGrantedRestartRequired:
            return String(localized: "Screen Recording access was granted. Reopen BlurFollow to continue.")
        case .pickerPermissionDenied:
            return String(localized: "Screen capture access was not allowed. You can enable it in System Settings, then try again.")
        case .system:
            // Do not surface arbitrary system text in a window that may itself be shared. Future
            // OS errors could include a window title, path, or application metadata.
            return String(localized: "The system window picker could not complete the request.")
        }
    }
}

/// Owns Apple's system content picker. The picker grants access to the exact content the user chose
/// and avoids building a look-alike privacy dialog inside the app.
final class ContentPickerService: NSObject, ObservableObject, SCContentSharingPickerObserver {
    @Published private(set) var isPicking = false
    @Published private(set) var lastError: String?

    private var completion: ((Result<PickedWindow, ContentPickerError>) -> Void)?
    private var requestToken: ContentPickerRequestToken?
    private var resolutionTask: Task<Void, Never>?
    private var discardActiveRequest = false
    private let presentPicker: () -> Void
    private let preflightScreenCaptureAccess: () -> Bool
    private let requestScreenCaptureAccess: () -> Bool
    private let requiresLegacyScreenCaptureAccess: () -> Bool
    private let onLegacyAccessRequestCompleted: @MainActor (Bool) -> Void
    private let onPickerAuthorization: @MainActor () -> Void
    private let onAccessDenied: @MainActor () -> Void

    init(
        presentPicker: @escaping () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
            SCContentSharingPicker.shared.present(using: .window)
        },
        preflightScreenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestScreenCaptureAccess: @escaping () -> Bool = { CGRequestScreenCaptureAccess() },
        requiresLegacyScreenCaptureAccess: @escaping () -> Bool = {
            if #available(macOS 15.2, *) { return false }
            return true
        },
        onLegacyAccessRequestCompleted: @escaping @MainActor (Bool) -> Void = { _ in },
        onPickerAuthorization: @escaping @MainActor () -> Void = {},
        onAccessDenied: @escaping @MainActor () -> Void = {}
    ) {
        self.presentPicker = presentPicker
        self.preflightScreenCaptureAccess = preflightScreenCaptureAccess
        self.requestScreenCaptureAccess = requestScreenCaptureAccess
        self.requiresLegacyScreenCaptureAccess = requiresLegacyScreenCaptureAccess
        self.onLegacyAccessRequestCompleted = onLegacyAccessRequestCompleted
        self.onPickerAuthorization = onPickerAuthorization
        self.onAccessDenied = onAccessDenied
        super.init()
        let picker = SCContentSharingPicker.shared
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = .singleWindow
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier].compactMap { $0 }
        configuration.allowsChangingSelectedContent = false
        picker.defaultConfiguration = configuration
        picker.maximumStreamCount = 1
        picker.add(self)
        picker.isActive = true
    }

    deinit {
        resolutionTask?.cancel()
        SCContentSharingPicker.shared.remove(self)
    }

    @MainActor
    @discardableResult
    func pickWindow(
        requestToken: ContentPickerRequestToken = ContentPickerRequestToken(),
        completion: @escaping (Result<PickedWindow, ContentPickerError>) -> Void
    ) -> ContentPickerRequestToken? {
        guard !isPicking else {
            let error = ContentPickerError.busy
            lastError = error.localizedDescription
            completion(.failure(error))
            return nil
        }
        if requiresLegacyScreenCaptureAccess(), !preflightScreenCaptureAccess() {
            // Legacy authorization is only reliable after the app restarts. Never continue into
            // broad window enumeration in the same process and mistake an incomplete grant for success.
            let isGranted = requestScreenCaptureAccess()
            onLegacyAccessRequestCompleted(isGranted)
            let error = isGranted
                ? ContentPickerError.legacyPermissionGrantedRestartRequired
                : ContentPickerError.legacyPermissionDenied
            lastError = error.localizedDescription
            completion(.failure(error))
            return nil
        }
        self.requestToken = requestToken
        discardActiveRequest = false
        self.completion = completion
        isPicking = true
        lastError = nil
        presentPicker()
        return requestToken
    }

    @MainActor
    @discardableResult
    func cancelRequest(_ requestToken: ContentPickerRequestToken) -> Bool {
        guard isPicking, self.requestToken == requestToken else { return false }
        // ScreenCaptureKit has no public programmatic dismiss API. Invalidate the consumer but keep
        // this picker generation occupied until its eventual cancel/update callback, so that a late
        // selection can never be mistaken for a newer request.
        let wasResolvingSelection = resolutionTask != nil
        resolutionTask?.cancel()
        discardActiveRequest = true
        let callback = completion
        completion = nil
        callback?(.failure(.cancelled))

        // Once didUpdate has already fired, the picker callback was consumed and resolution is the
        // last phase. Cancelling that task must release the picker slot immediately; there will be
        // no later callback to finish a discarded request.
        if wasResolvingSelection {
            finishDiscardedRequest()
        }
        return true
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didCancelFor stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.discardActiveRequest { self.finishDiscardedRequest() }
            else { self.cancelActiveRequest() }
        }
    }

    func contentSharingPicker(
        _ picker: SCContentSharingPicker,
        didUpdateWith filter: SCContentFilter,
        for stream: SCStream?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            // The shared picker can report a Control Center selection that BlurFollow did not
            // initiate. Such a callback must not clear this app's denial recovery state.
            guard self.requestToken != nil, self.isPicking else { return }
            if self.discardActiveRequest { self.finishDiscardedRequest() }
            else {
                self.onPickerAuthorization()
                self.startResolution(for: filter)
            }
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self, let requestToken = self.requestToken else { return }
            if self.discardActiveRequest {
                self.finishDiscardedRequest()
                return
            }
            if ScreenCapturePermission.isUserDeclinedError(error) {
                self.onAccessDenied()
                self.finish(.failure(.pickerPermissionDenied), requestToken: requestToken)
            } else {
                self.finish(.failure(.system(error)), requestToken: requestToken)
            }
        }
    }

    @MainActor
    private func startResolution(for filter: SCContentFilter) {
        guard let requestToken, isPicking else { return }
        resolutionTask?.cancel()
        resolutionTask = Task { [weak self] in
            let result: Result<PickedWindow, ContentPickerError>
            do {
                let candidate = try await Self.resolveWindow(for: filter)
                try Task.checkCancellation()
                result = .success(PickedWindow(candidate: candidate, filter: filter))
            } catch is CancellationError {
                return
            } catch let error as ContentPickerError {
                result = .failure(error)
            } catch {
                result = .failure(.system(error))
            }
            guard !Task.isCancelled else { return }
            self?.finish(result, requestToken: requestToken)
        }
    }

    @MainActor
    private func cancelActiveRequest() {
        guard let requestToken else { return }
        resolutionTask?.cancel()
        finish(.failure(.cancelled), requestToken: requestToken)
    }

    @MainActor
    private func finishDiscardedRequest() {
        guard discardActiveRequest else { return }
        requestToken = nil
        discardActiveRequest = false
        resolutionTask?.cancel()
        resolutionTask = nil
        completion = nil
        isPicking = false
        lastError = nil
    }

    @MainActor
    private func finish(
        _ result: Result<PickedWindow, ContentPickerError>,
        requestToken: ContentPickerRequestToken
    ) {
        guard self.requestToken == requestToken else { return }
        self.requestToken = nil
        discardActiveRequest = false
        resolutionTask = nil
        isPicking = false
        if case .failure(let error) = result, case .cancelled = error {
            // Cancellation is expected and should not leave a warning banner behind.
            lastError = nil
        } else if case .failure(let error) = result {
            lastError = error.localizedDescription
        } else {
            lastError = nil
        }
        let callback = completion
        completion = nil
        callback?(result)
    }

    private static func resolveWindow(for filter: SCContentFilter) async throws -> WindowCandidate {
        if #available(macOS 15.2, *) {
            // On modern macOS, includedWindows is the picker-authorized identity boundary. Never
            // fall back to broad enumeration if that exact result is missing or malformed.
            guard filter.includedWindows.count == 1, let window = filter.includedWindows.first else {
                if filter.includedWindows.count > 1 { throw ContentPickerError.ambiguousWindow }
                throw ContentPickerError.noWindow
            }
            return candidate(from: window)
        }

        // macOS 14–15.1 does not expose includedWindows on SCContentFilter. Never guess from the
        // nearest window: two same-sized browser windows can overlap, and a wrong identity would
        // attach a privacy mask to the wrong content. Accept one exact geometry match only.
        let content = try await SCShareableContent.excludingDesktopWindows(
            true,
            onScreenWindowsOnly: true
        )
        let windows = content.windows.filter { window in
            window.windowLayer == 0 && window.owningApplication?.bundleIdentifier != Bundle.main.bundleIdentifier
        }
        let filterRect = filter.contentRect
        guard filterRect.width > 1, filterRect.height > 1 else {
            throw ContentPickerError.noWindow
        }
        let exactMatches = windows.filter { window in
            let rect = window.frame
            let sizeDelta = abs(rect.width - filterRect.width) + abs(rect.height - filterRect.height)
            let originDelta = abs(rect.minX - filterRect.minX) + abs(rect.minY - filterRect.minY)
            return sizeDelta <= 4 && originDelta <= 4
        }
        guard exactMatches.count == 1, let window = exactMatches.first else {
            if exactMatches.count > 1 { throw ContentPickerError.ambiguousWindow }
            throw ContentPickerError.noWindow
        }
        return candidate(from: window)
    }

    private static func candidate(from window: SCWindow) -> WindowCandidate {
        let application = window.owningApplication
        let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return WindowCandidate(
            id: window.windowID,
            title: title.isEmpty ? String(localized: "Untitled Window") : title,
            identityTitle: title,
            applicationName: application?.applicationName ?? String(localized: "Unknown App"),
            bundleIdentifier: application?.bundleIdentifier ?? "",
            processID: application?.processID ?? 0,
            quartzFrame: window.frame,
            window: window
        )
    }
}
