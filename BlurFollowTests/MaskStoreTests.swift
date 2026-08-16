import XCTest
@testable import BlurFollow

@MainActor
final class MaskStoreTests: XCTestCase {
    func testLiveUpdatePersistsOnlyNewestValueWhenFlushed() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        var region = store.add(MaskRegion(
            name: "Live strength",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        ))
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
        var region = store.add(MaskRegion(
            name: "Live then toggle",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        ))
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
        ))

        let restored = MaskStore(storageURL: url)
        XCTAssertEqual(restored.regions.count, 1)
        XCTAssertEqual(restored.regions.first?.name, "Customer email")
        XCTAssertEqual(restored.regions.first?.style, .redact)
        XCTAssertFalse(restored.coverLastPositionEnabled)
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
        ))

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
        store.add(displayMask)
        store.add(windowMask)

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
        var region = store.add(MaskRegion(
            name: "Toolbar mask",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        ))
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
        ))
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
        ))
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
        ))

        XCTAssertThrowsError(try store.exportData())
        XCTAssertNotNil(store.recoveryIssue)
    }
}
