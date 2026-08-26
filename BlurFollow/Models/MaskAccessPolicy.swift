import Foundation

/// The plan boundary is intentionally independent from StoreKit so every mask-creation path can
/// enforce the same rule and the boundary can be tested without an App Store account.
enum MaskAccessPolicy {
    static let freeMaskLimit = 5
    static let monetizationVersion = "0.2.0"

    static func canCreateMask(currentCount: Int, hasUnlimitedAccess: Bool) -> Bool {
        hasUnlimitedAccess || currentCount < freeMaskLimit
    }

    static func remainingFreeMasks(currentCount: Int) -> Int {
        max(0, freeMaskLimit - currentCount)
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
