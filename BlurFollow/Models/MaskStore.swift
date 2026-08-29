import AppKit
import Foundation
import Combine

@MainActor
final class MaskStore: ObservableObject {
    @Published private(set) var regions: [MaskRegion] {
        didSet { persistCollectionChangeIfNeeded() }
    }
    @Published private(set) var textRules: [TextFollowRule] {
        didSet { persistCollectionChangeIfNeeded() }
    }
    @Published var masksEnabled: Bool {
        didSet { persistIfNeeded() }
    }
    @Published var coverLastPositionEnabled: Bool {
        didSet { persistIfNeeded() }
    }
    @Published var textFollowSafetyCoverEnabled: Bool {
        didSet { persistIfNeeded() }
    }
    @Published var hasCompletedOnboarding: Bool {
        didSet { persistIfNeeded() }
    }
    @Published private(set) var trackingStates: [UUID: TrackingState] = [:]
    @Published private(set) var recoveryIssue: String?

    private let storageURL: URL
    private let backupURL: URL
    private var canPersist = false
    private var preserveExistingBackup = false
    private var eraseBackupOnNextPersist = false
    private var isApplyingLiveCollectionUpdate = false
    private var isPerformingBatchMutation = false
    private var hasPendingPersistence = false
    private var pendingPersistenceTask: Task<Void, Never>?
    private var terminationCancellable: AnyCancellable?

    private struct Snapshot: Codable {
        var regions: [MaskRegion]
        var textRules: [TextFollowRule]
        var masksEnabled: Bool
        var coverLastPositionEnabled: Bool
        var textFollowSafetyCoverEnabled: Bool
        var hasCompletedOnboarding: Bool

        private enum CodingKeys: String, CodingKey {
            case regions
            case textRules
            case masksEnabled
            case coverLastPositionEnabled
            case textFollowSafetyCoverEnabled
            case hasCompletedOnboarding
        }

        init(
            regions: [MaskRegion],
            textRules: [TextFollowRule],
            masksEnabled: Bool,
            coverLastPositionEnabled: Bool,
            textFollowSafetyCoverEnabled: Bool,
            hasCompletedOnboarding: Bool
        ) {
            self.regions = regions
            self.textRules = textRules
            self.masksEnabled = masksEnabled
            self.coverLastPositionEnabled = coverLastPositionEnabled
            self.textFollowSafetyCoverEnabled = textFollowSafetyCoverEnabled
            self.hasCompletedOnboarding = hasCompletedOnboarding
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            regions = try container.decode([MaskRegion].self, forKey: .regions)
            // Snapshots written before text following existed have no textRules key.
            textRules = try container.decodeIfPresent([TextFollowRule].self, forKey: .textRules) ?? []
            masksEnabled = try container.decode(Bool.self, forKey: .masksEnabled)
            coverLastPositionEnabled = try container.decode(Bool.self, forKey: .coverLastPositionEnabled)
            // Safety-first behavior is the migration default for snapshots created before this
            // preference existed.
            textFollowSafetyCoverEnabled = try container.decodeIfPresent(
                Bool.self,
                forKey: .textFollowSafetyCoverEnabled
            ) ?? true
            hasCompletedOnboarding = try container.decode(Bool.self, forKey: .hasCompletedOnboarding)
        }
    }

    private enum SnapshotError: LocalizedError {
        case invalidMask

        var errorDescription: String? {
            String(localized: "Saved mask data could not be validated.")
        }
    }

    init(storageURL: URL? = nil) {
        let resolvedURL = storageURL ?? Self.defaultStorageURL
        self.storageURL = resolvedURL
        self.backupURL = resolvedURL.appendingPathExtension("backup")

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: resolvedURL.path) {
            do {
                let snapshot = try Self.loadSnapshot(from: resolvedURL)
                regions = snapshot.regions
                textRules = snapshot.textRules
                masksEnabled = snapshot.masksEnabled
                coverLastPositionEnabled = snapshot.coverLastPositionEnabled
                textFollowSafetyCoverEnabled = snapshot.textFollowSafetyCoverEnabled
                hasCompletedOnboarding = snapshot.hasCompletedOnboarding
                recoveryIssue = nil
            } catch {
                do {
                    let backup = try Self.loadSnapshot(from: backupURL)
                    regions = backup.regions
                    textRules = backup.textRules
                    masksEnabled = backup.masksEnabled
                    coverLastPositionEnabled = backup.coverLastPositionEnabled
                    textFollowSafetyCoverEnabled = backup.textFollowSafetyCoverEnabled
                    hasCompletedOnboarding = backup.hasCompletedOnboarding
                    recoveryIssue = String(localized: "Saved masks were damaged. BlurFollow restored the last validated backup; review every mask before sharing.")
                    preserveExistingBackup = true
                } catch {
                    // Corruption must never look like a successful first launch with zero masks.
                    regions = []
                    textRules = []
                    masksEnabled = false
                    coverLastPositionEnabled = true
                    textFollowSafetyCoverEnabled = true
                    hasCompletedOnboarding = true
                    recoveryIssue = String(localized: "Saved masks could not be recovered. Masks are paused; recreate and check them before sharing.")
                    preserveExistingBackup = true
                }
            }
        } else {
            regions = []
            textRules = []
            masksEnabled = true
            coverLastPositionEnabled = true
            textFollowSafetyCoverEnabled = true
            hasCompletedOnboarding = ProcessInfo.processInfo.environment["BLURFOLLOW_UI_TEST"] == "1"
            recoveryIssue = nil
        }
        canPersist = true

        terminationCancellable = NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.flushPersistence() }
    }

    @discardableResult
    func add(_ region: MaskRegion, hasUnlimitedAccess: Bool) -> MaskRegion? {
        guard MaskAccessPolicy.canCreate(
            kind: region.mode.planKind,
            usage: planUsage,
            hasUnlimitedAccess: hasUnlimitedAccess
        ) else { return nil }
        regions.append(region)
        return region
    }

    var planUsage: MaskPlanUsage {
        MaskPlanUsage(
            displayMaskCount: regions.lazy.filter { $0.mode == .display }.count,
            windowMaskCount: regions.lazy.filter { $0.mode == .window }.count,
            textFollowRuleCount: textRules.count
        )
    }

    @discardableResult
    func addTextRule(
        _ rule: TextFollowRule,
        hasUnlimitedAccess: Bool
    ) -> TextFollowRule? {
        guard (try? Self.validate(rule)) != nil,
              MaskAccessPolicy.canCreate(
                  kind: .textFollowRule,
                  usage: planUsage,
                  hasUnlimitedAccess: hasUnlimitedAccess
              ) else { return nil }
        textRules.append(rule)
        return rule
    }

    func update(_ region: MaskRegion) {
        guard let index = regions.firstIndex(where: { $0.id == region.id }) else { return }
        regions[index] = region
    }

    func updateTextRule(_ rule: TextFollowRule) {
        guard (try? Self.validate(rule)) != nil,
              let index = textRules.firstIndex(where: { $0.id == rule.id }) else { return }
        textRules[index] = rule
    }

    func updateTextRuleLive(_ rule: TextFollowRule) {
        guard (try? Self.validate(rule)) != nil,
              let index = textRules.firstIndex(where: { $0.id == rule.id }),
              textRules[index] != rule else { return }
        isApplyingLiveCollectionUpdate = true
        textRules[index] = rule
        isApplyingLiveCollectionUpdate = false
        schedulePersistence()
    }

    /// Publishes a high-frequency visual edit immediately while coalescing only its disk write.
    /// Use this for continuous controls such as Strength and granularity; discrete mutations keep
    /// using `update`.
    func updateLive(_ region: MaskRegion) {
        guard let index = regions.firstIndex(where: { $0.id == region.id }),
              regions[index] != region else { return }
        isApplyingLiveCollectionUpdate = true
        regions[index] = region
        isApplyingLiveCollectionUpdate = false
        schedulePersistence()
    }

    /// Writes the newest live value now. Immediate mutations also call this path implicitly, so a
    /// toggle or delete can never persist an older snapshot while a Strength edit is pending.
    func flushPersistence() {
        guard hasPendingPersistence else { return }
        persistIfNeeded()
    }

    func setEnabled(_ isEnabled: Bool, for id: UUID) {
        guard var region = regions.first(where: { $0.id == id }),
              region.isEnabled != isEnabled else { return }
        region.isEnabled = isEnabled
        update(region)
    }

    func setTextRuleEnabled(_ isEnabled: Bool, for id: UUID) {
        guard var rule = textRules.first(where: { $0.id == id }),
              rule.isEnabled != isEnabled else { return }
        rule.isEnabled = isEnabled
        updateTextRule(rule)
    }

    func remove(id: UUID) {
        regions.removeAll { $0.id == id }
        trackingStates[id] = nil
    }

    func removeTextRule(id: UUID) {
        textRules.removeAll { $0.id == id }
        trackingStates[id] = nil
    }

    func removeAll() {
        eraseBackupOnNextPersist = true
        recoveryIssue = nil
        isPerformingBatchMutation = true
        regions.removeAll()
        textRules.removeAll()
        isPerformingBatchMutation = false
        trackingStates.removeAll()
        persistIfNeeded()
    }

    func setTrackingState(_ state: TrackingState, for id: UUID) {
        guard trackingStates[id] != state else { return }
        trackingStates[id] = state
    }

    func acknowledgeRecoveryIssue() {
        recoveryIssue = nil
        persistIfNeeded()
    }

    private func persistCollectionChangeIfNeeded() {
        guard !isApplyingLiveCollectionUpdate, !isPerformingBatchMutation else { return }
        persistIfNeeded()
    }

    private func schedulePersistence() {
        hasPendingPersistence = true
        pendingPersistenceTask?.cancel()
        pendingPersistenceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.flushPersistence()
        }
    }

    func exportData() throws -> Data {
        let snapshot = Snapshot(
            regions: regions,
            textRules: textRules,
            masksEnabled: masksEnabled,
            coverLastPositionEnabled: coverLastPositionEnabled,
            textFollowSafetyCoverEnabled: textFollowSafetyCoverEnabled,
            hasCompletedOnboarding: hasCompletedOnboarding
        )
        try Self.validate(snapshot)
        return try JSONEncoder.blurFollow.encode(snapshot)
    }

    private func persistIfNeeded() {
        pendingPersistenceTask?.cancel()
        pendingPersistenceTask = nil
        hasPendingPersistence = false
        guard canPersist else { return }
        do {
            let fileManager = FileManager.default
            try fileManager.createDirectory(
                at: storageURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            // Only promote a known-valid current snapshot to backup. A corrupt primary file must
            // never overwrite the last recovery point.
            if !eraseBackupOnNextPersist,
               !preserveExistingBackup,
               fileManager.fileExists(atPath: storageURL.path),
               (try? Self.loadSnapshot(from: storageURL)) != nil {
                let currentData = try Data(contentsOf: storageURL)
                try currentData.write(to: backupURL, options: .atomic)
            }

            try exportData().write(to: storageURL, options: .atomic)
            if eraseBackupOnNextPersist, fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            eraseBackupOnNextPersist = false
            preserveExistingBackup = false
        } catch {
            recoveryIssue = String.localizedStringWithFormat(
                String(localized: "BlurFollow could not save mask settings: %@"),
                error.localizedDescription
            )
        }
    }

    private static func loadSnapshot(from url: URL) throws -> Snapshot {
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder.blurFollow.decode(Snapshot.self, from: data)
        try validate(snapshot)
        return snapshot
    }

    private static func validate(_ snapshot: Snapshot) throws {
        let identifiers = snapshot.regions.map(\.id) + snapshot.textRules.map(\.id)
        guard Set(identifiers).count == identifiers.count else {
            throw SnapshotError.invalidMask
        }

        for region in snapshot.regions {
            let unit = region.normalizedRect
            let values = [
                unit.x, unit.y, unit.width, unit.height,
                region.strength, region.granularity, region.cornerRadius
            ]
            guard values.allSatisfy(\.isFinite),
                  unit.x >= 0, unit.y >= 0,
                  unit.width >= 0.002, unit.height >= 0.002,
                  unit.x + unit.width <= 1.000_001,
                  unit.y + unit.height <= 1.000_001,
                  (0...1).contains(region.strength),
                  (0...1).contains(region.granularity),
                  (0...40).contains(region.cornerRadius),
                  region.createdAt.timeIntervalSinceReferenceDate.isFinite else {
                throw SnapshotError.invalidMask
            }

            if region.mode == .window {
                guard let anchor = region.windowAnchor else { throw SnapshotError.invalidMask }
                try validate(anchor)
            }
        }

        for rule in snapshot.textRules {
            try validate(rule)
        }
    }

    private static func validate(_ rule: TextFollowRule) throws {
        let values = [
            rule.strength,
            rule.granularity,
            rule.cornerRadius,
            rule.padding
        ]
        guard values.allSatisfy(\.isFinite),
              (0...1).contains(rule.strength),
              (0...1).contains(rule.granularity),
              (0...40).contains(rule.cornerRadius),
              (0...TextFollowRule.maximumPadding).contains(rule.padding),
              rule.createdAt.timeIntervalSinceReferenceDate.isFinite,
              (try? TextPatternMatcher(rule: rule)) != nil else {
            throw SnapshotError.invalidMask
        }
        try validate(rule.windowAnchor)
    }

    private static func validate(_ anchor: WindowAnchor) throws {
        let frame = anchor.initialFrame
        let rect = frame.cgRect
        let frameValues = [
            rect.minX, rect.minY, rect.maxX, rect.maxY,
            rect.width, rect.height
        ]
        guard anchor.windowID != 0,
              !anchor.bundleIdentifier.isEmpty || !anchor.applicationName.isEmpty,
              frameValues.allSatisfy(\.isFinite),
              frame.width >= 80,
              frame.height >= 60,
              frame.width <= 100_000,
              frame.height <= 100_000,
              abs(frame.x) <= 1_000_000,
              abs(frame.y) <= 1_000_000 else {
            throw SnapshotError.invalidMask
        }
    }

    private static var defaultStorageURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("BlurFollow", isDirectory: true)
            .appendingPathComponent("Masks.json")
    }
}

private extension JSONEncoder {
    static var blurFollow: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var blurFollow: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
