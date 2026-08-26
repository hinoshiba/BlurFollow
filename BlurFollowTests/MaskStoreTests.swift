import XCTest
@testable import BlurFollow

@MainActor
final class MaskStoreTests: XCTestCase {
    func testFreePlanRejectsSixthMaskButKeepsExistingMasks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        for index in 0..<MaskAccessPolicy.freeMaskLimit {
            XCTAssertNotNil(store.add(MaskRegion(
                name: "Free mask \(index)",
                mode: .display,
                normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                isEnabled: index.isMultiple(of: 2)
            ), hasUnlimitedAccess: false))
        }

        XCTAssertNil(store.add(MaskRegion(
            name: "Sixth mask",
            mode: .display,
            normalizedRect: UnitRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)
        ), hasUnlimitedAccess: false))
        XCTAssertEqual(store.regions.count, MaskAccessPolicy.freeMaskLimit)
        XCTAssertEqual(MaskStore(storageURL: url).regions.count, MaskAccessPolicy.freeMaskLimit)
    }

    func testDeletingAMaskReopensAFreeSlot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        var firstID: UUID?
        for index in 0..<MaskAccessPolicy.freeMaskLimit {
            let added = try XCTUnwrap(store.add(MaskRegion(
                name: "Mask \(index)",
                mode: .display,
                normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
            ), hasUnlimitedAccess: false))
            firstID = firstID ?? added.id
        }

        store.remove(id: try XCTUnwrap(firstID))
        XCTAssertNotNil(store.add(MaskRegion(
            name: "Replacement",
            mode: .display,
            normalizedRect: UnitRect(x: 0.3, y: 0.3, width: 0.2, height: 0.2)
        ), hasUnlimitedAccess: false))
        XCTAssertEqual(store.regions.count, MaskAccessPolicy.freeMaskLimit)
    }

    func testUnlimitedAccessCanAddBeyondFreeLimitAndReloadAllMasks() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        for index in 0..<(MaskAccessPolicy.freeMaskLimit + 3) {
            XCTAssertNotNil(store.add(MaskRegion(
                name: "Unlimited mask \(index)",
                mode: .display,
                normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
            ), hasUnlimitedAccess: true))
        }

        XCTAssertEqual(store.regions.count, 8)
        let restored = MaskStore(storageURL: url)
        XCTAssertEqual(restored.regions.count, 8)
        XCTAssertFalse(MaskAccessPolicy.canCreateMask(
            currentCount: restored.regions.count,
            hasUnlimitedAccess: false
        ))
        XCTAssertEqual(restored.regions.count, 8, "Existing masks must never be removed by the plan boundary.")
    }

    func testLiveUpdatePersistsOnlyNewestValueWhenFlushed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        var region = try XCTUnwrap(store.add(MaskRegion(
            name: "Live strength",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        ), hasUnlimitedAccess: true))
        let originalStrength = region.strength

        region.strength = 0.3
        store.updateLive(region)
        region.strength = 0.9
        store.updateLive(region)

        // Live changes are visible immediately, but the pre-edit snapshot remains on disk until
        // the coalesced write is flushed.
        XCTAssertEqual(store.regions.first?.strength, 0.9)
        XCTAssertEqual(MaskStore(storageURL: url).regions.first?.strength, originalStrength)

        store.flushPersistence()
        XCTAssertEqual(MaskStore(storageURL: url).regions.first?.strength, 0.9)
    }

    func testImmediateMutationFlushesPendingLiveValueInSameSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        var region = try XCTUnwrap(store.add(MaskRegion(
            name: "Live then toggle",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        ), hasUnlimitedAccess: true))
        region.strength = 0.42
        store.updateLive(region)

        // A discrete setting remains an immediate write and includes the pending live edit.
        store.masksEnabled = false

        let restored = MaskStore(storageURL: url)
        XCTAssertEqual(restored.regions.first?.strength, 0.42)
        XCTAssertFalse(restored.masksEnabled)
    }

    func testPersistsAndReloadsMasks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = MaskStore(storageURL: url)
        original.coverLastPositionEnabled = false
        original.add(MaskRegion(
            name: "Customer email",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
            displayIdentifier: "display-1",
            style: .redact
        ), hasUnlimitedAccess: true)

        let restored = MaskStore(storageURL: url)
        XCTAssertEqual(restored.regions.count, 1)
        XCTAssertEqual(restored.regions.first?.name, "Customer email")
        XCTAssertEqual(restored.regions.first?.style, .redact)
        XCTAssertFalse(restored.coverLastPositionEnabled)
    }

    func testPersistsAndReloadsAppearanceControls() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = MaskStore(storageURL: url)
        original.add(MaskRegion(
            name: "Custom appearance",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
            strength: 0.42,
            granularity: 0.27,
            tint: .warm,
            borderEnabled: false
        ), hasUnlimitedAccess: true)

        let restored = try XCTUnwrap(MaskStore(storageURL: url).regions.first)
        XCTAssertEqual(restored.strength, 0.42, accuracy: 0.000_001)
        XCTAssertEqual(restored.granularity, 0.27, accuracy: 0.000_001)
        XCTAssertEqual(restored.tint, .warm)
        XCTAssertFalse(restored.borderEnabled)
    }

    func testLegacySnapshotUsesStrengthAndExistingAppearanceAsDefaults() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        store.add(MaskRegion(
            name: "Legacy appearance",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1),
            strength: 0.37,
            granularity: 0.91,
            tint: .warm,
            borderEnabled: false
        ), hasUnlimitedAccess: true)

        var root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: store.exportData()) as? [String: Any]
        )
        var regions = try XCTUnwrap(root["regions"] as? [[String: Any]])
        regions[0].removeValue(forKey: "granularity")
        regions[0].removeValue(forKey: "tint")
        regions[0].removeValue(forKey: "borderEnabled")
        root["regions"] = regions
        try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
            .write(to: url, options: .atomic)

        let restoredStore = MaskStore(storageURL: url)
        let restored = try XCTUnwrap(restoredStore.regions.first)
        XCTAssertNil(restoredStore.recoveryIssue)
        XCTAssertEqual(restored.granularity, 0.37, accuracy: 0.000_001)
        XCTAssertEqual(restored.tint, .cool)
        XCTAssertTrue(restored.borderEnabled)
    }

    func testRejectsOutOfRangeGranularity() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        var region = try XCTUnwrap(store.add(MaskRegion(
            name: "Invalid granularity",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.1)
        ), hasUnlimitedAccess: true))
        region.granularity = 1.01
        store.update(region)

        XCTAssertThrowsError(try store.exportData())
        XCTAssertNotNil(store.recoveryIssue)
    }

    func testExportContainsNoCapturedPixels() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        store.add(MaskRegion(
            name: "API key",
            mode: .display,
            normalizedRect: UnitRect(x: 0, y: 0, width: 0.2, height: 0.1),
            style: .redact
        ), hasUnlimitedAccess: true)

        let exported = try store.exportData()
        let text = String(decoding: exported, as: UTF8.self)
        XCTAssertTrue(text.contains("API key"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("pixelBuffer"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("imageData"))
    }

    func testSetEnabledChangesOnlyRequestedMaskAndPersists() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let displayMask = MaskRegion(
            name: "Display details",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        )
        let windowMask = MaskRegion(
            name: "Window details",
            mode: .window,
            normalizedRect: UnitRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2),
            windowAnchor: WindowAnchor(
                windowID: 42,
                bundleIdentifier: "com.example.window",
                applicationName: "Example",
                windowTitle: "Example Window",
                initialFrame: CodableRect(CGRect(x: 100, y: 100, width: 800, height: 600)),
                processID: 42
            ),
            isEnabled: false
        )
        let store = MaskStore(storageURL: url)
        store.add(displayMask, hasUnlimitedAccess: true)
        store.add(windowMask, hasUnlimitedAccess: true)

        store.setEnabled(false, for: displayMask.id)
        XCTAssertFalse(store.regions.first(where: { $0.id == displayMask.id })?.isEnabled ?? true)
        XCTAssertFalse(store.regions.first(where: { $0.id == windowMask.id })?.isEnabled ?? true)
        XCTAssertTrue(store.masksEnabled)

        store.setEnabled(true, for: windowMask.id)
        XCTAssertFalse(store.regions.first(where: { $0.id == displayMask.id })?.isEnabled ?? true)
        XCTAssertTrue(store.regions.first(where: { $0.id == windowMask.id })?.isEnabled ?? false)
        XCTAssertTrue(store.masksEnabled)

        let restored = MaskStore(storageURL: url)
        XCTAssertFalse(restored.regions.first(where: { $0.id == displayMask.id })?.isEnabled ?? true)
        XCTAssertTrue(restored.regions.first(where: { $0.id == windowMask.id })?.isEnabled ?? false)
        XCTAssertTrue(restored.masksEnabled)
    }

    func testSetEnabledFlushesPendingLiveEditInSameSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        var region = try XCTUnwrap(store.add(MaskRegion(
            name: "Toolbar mask",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        ), hasUnlimitedAccess: true))
        region.strength = 0.37
        store.updateLive(region)

        store.setEnabled(false, for: region.id)

        let restored = MaskStore(storageURL: url)
        XCTAssertEqual(restored.regions.first?.strength, 0.37)
        XCTAssertFalse(restored.regions.first?.isEnabled ?? true)
    }

    func testCorruptPrimaryRestoresValidatedBackupAndBlocksReadiness() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = MaskStore(storageURL: url)
        original.add(MaskRegion(
            name: "Recovered mask",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            style: .redact
        ), hasUnlimitedAccess: true)
        // A subsequent valid write promotes the previous snapshot to the backup file.
        original.coverLastPositionEnabled.toggle()
        try Data("{not-json".utf8).write(to: url, options: .atomic)

        let restored = MaskStore(storageURL: url)
        XCTAssertEqual(restored.regions.first?.name, "Recovered mask")
        XCTAssertNotNil(restored.recoveryIssue)
    }

    func testUnrecoverableSnapshotPausesMasksInsteadOfLookingLikeFirstLaunch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{not-json".utf8).write(to: url)

        let store = MaskStore(storageURL: url)
        XCTAssertFalse(store.masksEnabled)
        XCTAssertTrue(store.regions.isEmpty)
        XCTAssertNotNil(store.recoveryIssue)
    }

    func testDeleteAllRemovesRecoveryBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        let backupURL = url.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        store.add(MaskRegion(
            name: "Delete me",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            style: .redact
        ), hasUnlimitedAccess: true)
        store.coverLastPositionEnabled.toggle()
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        store.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
        XCTAssertTrue(MaskStore(storageURL: url).regions.isEmpty)
    }

    func testRejectsWindowFrameWhoseDerivedBoundsOverflow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        let anchor = WindowAnchor(
            windowID: 42,
            bundleIdentifier: "com.example.window",
            applicationName: "Example",
            windowTitle: "Example",
            initialFrame: CodableRect(CGRect(x: 1e308, y: 1e308, width: 1e308, height: 1e308)),
            processID: 42
        )
        store.add(MaskRegion(
            name: "Overflowing frame",
            mode: .window,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            windowAnchor: anchor,
            style: .redact
        ), hasUnlimitedAccess: true)

        XCTAssertThrowsError(try store.exportData())
        XCTAssertNotNil(store.recoveryIssue)
    }
}
