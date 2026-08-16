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

enum ContentPickerError: LocalizedError {
    case cancelled
    case busy
    case noWindow
    case ambiguousWindow
    case legacyPermissionRequired
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
        case .legacyPermissionRequired:
            return String(localized: "macOS 14 through 15.1 requires Screen Recording access to identify the selected window. Allow it in System Settings, then reopen BlurFollow.")
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

    init(
        presentPicker: @escaping () -> Void = {
            NSApp.activate(ignoringOtherApps: true)
            SCContentSharingPicker.shared.present(using: .window)
        },
        preflightScreenCaptureAccess: @escaping () -> Bool = { CGPreflightScreenCaptureAccess() },
        requestScreenCaptureAccess: @escaping () -> Bool = { CGRequestScreenCaptureAccess() }
    ) {
        self.presentPicker = presentPicker
        self.preflightScreenCaptureAccess = preflightScreenCaptureAccess
        self.requestScreenCaptureAccess = requestScreenCaptureAccess
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
        if #available(macOS 15.2, *) {
            // includedWindows provides exact picker identity with per-selection authorization.
        } else if !preflightScreenCaptureAccess() {
            // Legacy authorization is only reliable after the app restarts. Never continue into
            // broad window enumeration in the same process and mistake an incomplete grant for success.
            _ = requestScreenCaptureAccess()
            let error = ContentPickerError.legacyPermissionRequired
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
            if self.discardActiveRequest { self.finishDiscardedRequest() }
            else { self.startResolution(for: filter) }
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            guard let self, let requestToken = self.requestToken else { return }
            if self.discardActiveRequest {
                self.finishDiscardedRequest()
                return
            }
            self.finish(.failure(.system(error)), requestToken: requestToken)
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
