import AppKit
import Foundation
import Combine

@MainActor
final class MaskStore: ObservableObject {
    @Published var regions: [MaskRegion] {
        didSet { persistRegionChangeIfNeeded() }
    }
    @Published var masksEnabled: Bool {
        didSet { persistIfNeeded() }
    }
    @Published var coverLastPositionEnabled: Bool {
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
    private var isApplyingLiveRegionUpdate = false
    private var hasPendingPersistence = false
    private var pendingPersistenceTask: Task<Void, Never>?
    private var terminationCancellable: AnyCancellable?

    private struct Snapshot: Codable {
        var regions: [MaskRegion]
        var masksEnabled: Bool
        var coverLastPositionEnabled: Bool
        var hasCompletedOnboarding: Bool
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
                masksEnabled = snapshot.masksEnabled
                coverLastPositionEnabled = snapshot.coverLastPositionEnabled
                hasCompletedOnboarding = snapshot.hasCompletedOnboarding
                recoveryIssue = nil
            } catch {
                do {
                    let backup = try Self.loadSnapshot(from: backupURL)
                    regions = backup.regions
                    masksEnabled = backup.masksEnabled
                    coverLastPositionEnabled = backup.coverLastPositionEnabled
                    hasCompletedOnboarding = backup.hasCompletedOnboarding
                    recoveryIssue = String(localized: "Saved masks were damaged. BlurFollow restored the last validated backup; review every mask before sharing.")
                    preserveExistingBackup = true
                } catch {
                    // Corruption must never look like a successful first launch with zero masks.
                    regions = []
                    masksEnabled = false
                    coverLastPositionEnabled = true
                    hasCompletedOnboarding = true
                    recoveryIssue = String(localized: "Saved masks could not be recovered. Masks are paused; recreate and check them before sharing.")
                    preserveExistingBackup = true
                }
            }
        } else {
            regions = []
            masksEnabled = true
            coverLastPositionEnabled = true
            hasCompletedOnboarding = ProcessInfo.processInfo.environment["BLURFOLLOW_UI_TEST"] == "1"
            recoveryIssue = nil
        }
        canPersist = true

        terminationCancellable = NotificationCenter.default
            .publisher(for: NSApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.flushPersistence() }
    }

    @discardableResult
    func add(_ region: MaskRegion) -> MaskRegion {
        regions.append(region)
        return region
    }

    func update(_ region: MaskRegion) {
        guard let index = regions.firstIndex(where: { $0.id == region.id }) else { return }
        regions[index] = region
    }

    /// Publishes a high-frequency visual edit immediately while coalescing only its disk write.
    /// Use this for continuous controls such as Strength; discrete mutations keep using `update`.
    func updateLive(_ region: MaskRegion) {
        guard let index = regions.firstIndex(where: { $0.id == region.id }),
              regions[index] != region else { return }
        isApplyingLiveRegionUpdate = true
        regions[index] = region
        isApplyingLiveRegionUpdate = false
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

    func remove(id: UUID) {
        regions.removeAll { $0.id == id }
        trackingStates[id] = nil
    }

    func removeAll() {
        eraseBackupOnNextPersist = true
        recoveryIssue = nil
        regions.removeAll()
        trackingStates.removeAll()
    }

    func setTrackingState(_ state: TrackingState, for id: UUID) {
        guard trackingStates[id] != state else { return }
        trackingStates[id] = state
    }

    func acknowledgeRecoveryIssue() {
        recoveryIssue = nil
        persistIfNeeded()
    }

    private func persistRegionChangeIfNeeded() {
        guard !isApplyingLiveRegionUpdate else { return }
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
            masksEnabled: masksEnabled,
            coverLastPositionEnabled: coverLastPositionEnabled,
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
        guard Set(snapshot.regions.map(\.id)).count == snapshot.regions.count else {
            throw SnapshotError.invalidMask
        }

        for region in snapshot.regions {
            let unit = region.normalizedRect
            let values = [unit.x, unit.y, unit.width, unit.height, region.strength, region.cornerRadius]
            guard values.allSatisfy(\.isFinite),
                  unit.x >= 0, unit.y >= 0,
                  unit.width >= 0.002, unit.height >= 0.002,
                  unit.x + unit.width <= 1.000_001,
                  unit.y + unit.height <= 1.000_001,
                  (0...1).contains(region.strength),
                  (0...40).contains(region.cornerRadius),
                  region.createdAt.timeIntervalSinceReferenceDate.isFinite else {
                throw SnapshotError.invalidMask
            }

            if region.mode == .window {
                guard let anchor = region.windowAnchor else { throw SnapshotError.invalidMask }
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
