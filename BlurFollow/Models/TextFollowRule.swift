import Foundation

enum TextMatchMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case exact
    case prefix
    case contains
    case regex

    var id: String { rawValue }
}

/// A saved text-following definition. One rule consumes one plan slot even when it matches many
/// text blocks in the current window; every matching block is rendered by the runtime pipeline.
struct TextFollowRule: Codable, Identifiable, Hashable, Sendable {
    /// UTF-8 byte limit, so combining marks cannot bypass the persisted-input bound.
    static let maximumPatternLength = 512
    static let maximumPadding = 100.0

    var id: UUID
    var name: String
    var matchMode: TextMatchMode
    var pattern: String
    var windowAnchor: WindowAnchor
    var strength: Double
    var granularity: Double
    var tint: MaskTint
    var borderEnabled: Bool
    var cornerRadius: Double
    var padding: Double
    var isEnabled: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        matchMode: TextMatchMode,
        pattern: String,
        windowAnchor: WindowAnchor,
        strength: Double = 0.78,
        granularity: Double = 0.78,
        tint: MaskTint = .cool,
        borderEnabled: Bool = true,
        cornerRadius: Double = 8,
        padding: Double = 6,
        isEnabled: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.matchMode = matchMode
        self.pattern = pattern
        self.windowAnchor = windowAnchor
        self.strength = min(max(strength, 0), 1)
        self.granularity = min(max(granularity, 0), 1)
        self.tint = tint
        self.borderEnabled = borderEnabled
        self.cornerRadius = min(max(cornerRadius, 0), 40)
        self.padding = min(max(padding, 0), Self.maximumPadding)
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    func makeMatcher() throws -> TextPatternMatcher {
        try TextPatternMatcher(mode: matchMode, pattern: pattern)
    }
}

/// A Foundation-only matcher suitable for unit tests and for both UI preview and OCR pipelines.
/// Matching is case-sensitive and does not trim OCR text. Contains and regex modes search the
/// whole block; regex callers can use anchors when they need a full-block match.
struct TextPatternMatcher {
    enum MatchResult: Equatable {
        case matched
        case notMatched
        case timedOut
    }

    enum ValidationError: Error, Equatable {
        case emptyPattern
        case patternTooLong(maximum: Int)
        case invalidRegularExpression
    }

    /// Bounds a standalone regex check. The OCR pipeline applies a separate shared deadline to
    /// the complete frame so several blocks or rules cannot multiply this allowance.
    static let defaultExecutionLimitNanoseconds: UInt64 = 10_000_000

    let mode: TextMatchMode
    let pattern: String
    private let regularExpression: NSRegularExpression?

    init(mode: TextMatchMode, pattern: String) throws {
        guard !pattern.isEmpty else { throw ValidationError.emptyPattern }
        guard pattern.utf8.count <= TextFollowRule.maximumPatternLength else {
            throw ValidationError.patternTooLong(maximum: TextFollowRule.maximumPatternLength)
        }

        let regularExpression: NSRegularExpression?
        if mode == .regex {
            do {
                regularExpression = try NSRegularExpression(pattern: pattern)
            } catch {
                throw ValidationError.invalidRegularExpression
            }
        } else {
            regularExpression = nil
        }

        self.mode = mode
        self.pattern = pattern
        self.regularExpression = regularExpression
    }

    init(rule: TextFollowRule) throws {
        try self.init(mode: rule.matchMode, pattern: rule.pattern)
    }

    func matches(_ textBlock: String) -> Bool {
        matchResult(
            textBlock,
            deadlineUptimeNanoseconds: Self.deadline(
                afterNanoseconds: Self.defaultExecutionLimitNanoseconds
            )
        ) == .matched
    }

    /// Evaluates one block against an absolute deadline. ICU reports progress during expensive
    /// backtracking, which lets a pathological user-supplied expression be stopped without
    /// blocking every selected window's shared recognition queue indefinitely.
    func matchResult(
        _ textBlock: String,
        deadlineUptimeNanoseconds: UInt64
    ) -> MatchResult {
        switch mode {
        case .exact:
            return textBlock == pattern ? .matched : .notMatched
        case .prefix:
            return textBlock.hasPrefix(pattern) ? .matched : .notMatched
        case .contains:
            return textBlock.contains(pattern) ? .matched : .notMatched
        case .regex:
            guard let regularExpression else { return .notMatched }
            guard DispatchTime.now().uptimeNanoseconds < deadlineUptimeNanoseconds else {
                return .timedOut
            }
            let range = NSRange(textBlock.startIndex..<textBlock.endIndex, in: textBlock)
            var result = MatchResult.notMatched
            regularExpression.enumerateMatches(
                in: textBlock,
                options: [.reportProgress],
                range: range
            ) { match, _, stop in
                guard DispatchTime.now().uptimeNanoseconds < deadlineUptimeNanoseconds else {
                    result = .timedOut
                    stop.pointee = true
                    return
                }
                if match != nil {
                    result = .matched
                    stop.pointee = true
                }
            }
            return result
        }
    }

    static func deadline(afterNanoseconds interval: UInt64) -> UInt64 {
        let now = DispatchTime.now().uptimeNanoseconds
        let (deadline, overflowed) = now.addingReportingOverflow(interval)
        return overflowed ? UInt64.max : deadline
    }

    /// Returns every matching offset, including duplicate blocks matched by the same saved rule.
    func matchingIndices(in textBlocks: [String]) -> [Int] {
        textBlocks.indices.filter { matches(textBlocks[$0]) }
    }

    /// Preserves all matching elements and their input order. This lets an OCR caller retain each
    /// block's geometry while still applying one saved rule to every occurrence.
    func matchingElements<Element>(
        in elements: [Element],
        text: (Element) -> String
    ) -> [Element] {
        elements.filter { matches(text($0)) }
    }
}
