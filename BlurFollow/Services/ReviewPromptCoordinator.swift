import Foundation

enum ReviewPromptPolicy {
    static let requiredSuccessfulPreviewChecks = 2
    static let minimumExperience: TimeInterval = 7 * 24 * 60 * 60
    static let minimumRequestInterval: TimeInterval = 120 * 24 * 60 * 60

    static func shouldRequestReview(
        successfulPreviewCheckCount: Int,
        firstUseDate: Date?,
        lastRequestedVersion: String?,
        lastRequestedDate: Date?,
        currentVersion: String,
        now: Date
    ) -> Bool {
        guard successfulPreviewCheckCount >= requiredSuccessfulPreviewChecks,
              let firstUseDate,
              now.timeIntervalSince(firstUseDate) >= minimumExperience,
              !currentVersion.isEmpty,
              lastRequestedVersion != currentVersion else { return false }

        if let lastRequestedDate,
           now.timeIntervalSince(lastRequestedDate) < minimumRequestInterval {
            return false
        }
        return true
    }
}

@MainActor
final class ReviewPromptCoordinator: ObservableObject {
    private enum Keys {
        static let firstUseDate = "review.firstUseDate"
        static let successfulPreviewCheckCount = "review.successfulPreviewCheckCount"
        static let lastRequestedVersion = "review.lastRequestedVersion"
        static let lastRequestedDate = "review.lastRequestedDate"
    }

    private let defaults: UserDefaults
    private let versionProvider: () -> String
    @Published private(set) var hasPendingRequest = false

    init(
        defaults: UserDefaults = .standard,
        versionProvider: @escaping () -> String = {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        }
    ) {
        self.defaults = defaults
        self.versionProvider = versionProvider
        if defaults.object(forKey: Keys.firstUseDate) == nil {
            defaults.set(Date(), forKey: Keys.firstUseDate)
        }
    }

    /// Records a real, completed in-app task. It never inspects payment status or asks whether the
    /// person is happy, so every sufficiently experienced user follows the same neutral policy.
    func recordSuccessfulPreviewCheck(now: Date = Date()) {
        let count = defaults.integer(forKey: Keys.successfulPreviewCheckCount) + 1
        defaults.set(count, forKey: Keys.successfulPreviewCheckCount)

        guard !hasPendingRequest,
              ReviewPromptPolicy.shouldRequestReview(
                  successfulPreviewCheckCount: count,
                  firstUseDate: defaults.object(forKey: Keys.firstUseDate) as? Date,
                  lastRequestedVersion: defaults.string(forKey: Keys.lastRequestedVersion),
                  lastRequestedDate: defaults.object(forKey: Keys.lastRequestedDate) as? Date,
                  currentVersion: versionProvider(),
                  now: now
              ) else { return }
        // Share Preview records the completed task, but the main window owns presentation. This
        // avoids placing a rating prompt over a window the person may be about to share.
        hasPendingRequest = true
    }

    func markRequestAttempted(now: Date = Date()) {
        defaults.set(versionProvider(), forKey: Keys.lastRequestedVersion)
        defaults.set(now, forKey: Keys.lastRequestedDate)
        hasPendingRequest = false
    }
}
