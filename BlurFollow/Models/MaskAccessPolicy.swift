import Foundation

enum MaskPlanKind: String, CaseIterable, Sendable {
    case displayMask
    case windowMask
    case textFollowRule
}

struct MaskPlanUsage: Equatable, Sendable {
    let displayMaskCount: Int
    let windowMaskCount: Int
    /// Counts saved matching rules, not the number of text blocks currently matched by a rule.
    let textFollowRuleCount: Int

    init(
        displayMaskCount: Int = 0,
        windowMaskCount: Int = 0,
        textFollowRuleCount: Int = 0
    ) {
        self.displayMaskCount = max(0, displayMaskCount)
        self.windowMaskCount = max(0, windowMaskCount)
        self.textFollowRuleCount = max(0, textFollowRuleCount)
    }

    subscript(kind: MaskPlanKind) -> Int {
        switch kind {
        case .displayMask: return displayMaskCount
        case .windowMask: return windowMaskCount
        case .textFollowRule: return textFollowRuleCount
        }
    }
}

/// The plan boundary is intentionally independent from StoreKit so every creation path can
/// enforce the same rule and the boundary can be tested without an App Store account.
enum MaskAccessPolicy {
    static let freeDisplayMaskLimit = 10
    static let freeWindowMaskLimit = 5
    static let freeTextFollowRuleLimit = 2
    static let monetizationVersion = "0.2.0"

    static func freeLimit(for kind: MaskPlanKind) -> Int {
        switch kind {
        case .displayMask: return freeDisplayMaskLimit
        case .windowMask: return freeWindowMaskLimit
        case .textFollowRule: return freeTextFollowRuleLimit
        }
    }

    static func canCreate(
        kind: MaskPlanKind,
        usage: MaskPlanUsage,
        hasUnlimitedAccess: Bool
    ) -> Bool {
        hasUnlimitedAccess || usage[kind] < freeLimit(for: kind)
    }

    static func remainingFreeSlots(for kind: MaskPlanKind, usage: MaskPlanUsage) -> Int {
        max(0, freeLimit(for: kind) - usage[kind])
    }

    /// macOS AppTransaction versions use CFBundleShortVersionString. Comparing numeric components
    /// avoids treating values such as 0.1.10 as older than 0.1.2.
    static func isGrandfathered(originalAppVersion: String) -> Bool {
        guard let original = versionComponents(originalAppVersion),
              let boundary = versionComponents(monetizationVersion) else { return false }
        return original.lexicographicallyPrecedes(boundary)
    }

    private static func versionComponents(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }

        var components: [Int] = []
        for part in parts {
            guard !part.isEmpty,
                  part.allSatisfy(\.isNumber),
                  let component = Int(part) else { return nil }
            components.append(component)
        }
        while components.count < 3 { components.append(0) }
        return components
    }
}
