import XCTest
@testable import BlurFollow

@MainActor
final class MaskStoreTests: XCTestCase {
    func testFreePlanRejectsEleventhDisplayMaskButKeepsExistingMasks() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        for index in 0..<MaskAccessPolicy.freeDisplayMaskLimit {
            XCTAssertNotNil(store.add(
                makeDisplayRegion(index: index, isEnabled: index.isMultiple(of: 2)),
                hasUnlimitedAccess: false
            ))
        }

        XCTAssertNil(store.add(
            makeDisplayRegion(index: MaskAccessPolicy.freeDisplayMaskLimit),
            hasUnlimitedAccess: false
        ))
        XCTAssertEqual(store.regions.count, MaskAccessPolicy.freeDisplayMaskLimit)
        XCTAssertEqual(
            MaskStore(storageURL: url).regions.count,
            MaskAccessPolicy.freeDisplayMaskLimit
        )
    }

    func testDeletingAMaskReopensAFreeSlot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        var firstID: UUID?
        for index in 0..<MaskAccessPolicy.freeDisplayMaskLimit {
            let added = try XCTUnwrap(store.add(
                makeDisplayRegion(index: index),
                hasUnlimitedAccess: false
            ))
            firstID = firstID ?? added.id
        }

        store.remove(id: try XCTUnwrap(firstID))
        XCTAssertNotNil(store.add(makeDisplayRegion(index: 999), hasUnlimitedAccess: false))
        XCTAssertEqual(store.regions.count, MaskAccessPolicy.freeDisplayMaskLimit)
    }

    func testUnlimitedAccessCanAddBeyondFreeLimitAndReloadAllMasks() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        let expectedCount = MaskAccessPolicy.freeDisplayMaskLimit + 3
        for index in 0..<expectedCount {
            XCTAssertNotNil(store.add(
                makeDisplayRegion(index: index),
                hasUnlimitedAccess: true
            ))
        }

        XCTAssertEqual(store.regions.count, expectedCount)
        let restored = MaskStore(storageURL: url)
        XCTAssertEqual(restored.regions.count, expectedCount)
        XCTAssertFalse(MaskAccessPolicy.canCreate(
            kind: .displayMask,
            usage: restored.planUsage,
            hasUnlimitedAccess: false
        ))
        XCTAssertEqual(
            restored.regions.count,
            expectedCount,
            "Existing masks must never be removed by the plan boundary."
        )
    }

    func testFreePlanUsesIndependentDisplayWindowAndTextRuleSlots() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        for index in 0..<MaskAccessPolicy.freeDisplayMaskLimit {
            XCTAssertNotNil(store.add(
                makeDisplayRegion(index: index),
                hasUnlimitedAccess: false
            ))
        }

        // Filling Display Masks does not consume Window Mask or text-following slots.
        for index in 0..<MaskAccessPolicy.freeWindowMaskLimit {
            XCTAssertNotNil(store.add(
                makeWindowRegion(index: index),
                hasUnlimitedAccess: false
            ))
        }
        for index in 0..<MaskAccessPolicy.freeTextFollowRuleLimit {
            XCTAssertNotNil(store.addTextRule(
                makeTextRule(index: index, isEnabled: !index.isMultiple(of: 2)),
                hasUnlimitedAccess: false
            ))
        }

        XCTAssertEqual(store.planUsage, MaskPlanUsage(
            displayMaskCount: 10,
            windowMaskCount: 5,
            textFollowRuleCount: 2
        ))
        XCTAssertNil(store.add(makeDisplayRegion(index: 100), hasUnlimitedAccess: false))
        XCTAssertNil(store.add(makeWindowRegion(index: 100), hasUnlimitedAccess: false))
        XCTAssertNil(store.addTextRule(makeTextRule(index: 100), hasUnlimitedAccess: false))

        let restored = MaskStore(storageURL: url)
        XCTAssertEqual(restored.planUsage, store.planUsage)
        XCTAssertEqual(restored.regions.count, 15)
        XCTAssertEqual(restored.textRules.count, 2)
    }

    func testDeletingTextRuleReopensExactlyOneFreeRuleSlot() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        let first = try XCTUnwrap(store.addTextRule(
            makeTextRule(index: 0),
            hasUnlimitedAccess: false
        ))
        XCTAssertNotNil(store.addTextRule(makeTextRule(index: 1), hasUnlimitedAccess: false))
        XCTAssertNil(store.addTextRule(makeTextRule(index: 2), hasUnlimitedAccess: false))

        store.removeTextRule(id: first.id)
        XCTAssertNotNil(store.addTextRule(makeTextRule(index: 2), hasUnlimitedAccess: false))
        XCTAssertEqual(store.textRules.count, MaskAccessPolicy.freeTextFollowRuleLimit)
    }

    func testExistingItemsAboveEveryFreeLimitSurviveEntitlementLossAndReload() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        for index in 0...MaskAccessPolicy.freeDisplayMaskLimit {
            XCTAssertNotNil(store.add(makeDisplayRegion(index: index), hasUnlimitedAccess: true))
        }
        for index in 0...MaskAccessPolicy.freeWindowMaskLimit {
            XCTAssertNotNil(store.add(makeWindowRegion(index: index), hasUnlimitedAccess: true))
        }
        for index in 0...MaskAccessPolicy.freeTextFollowRuleLimit {
            XCTAssertNotNil(store.addTextRule(makeTextRule(index: index), hasUnlimitedAccess: true))
        }

        let expectedUsage = MaskPlanUsage(
            displayMaskCount: MaskAccessPolicy.freeDisplayMaskLimit + 1,
            windowMaskCount: MaskAccessPolicy.freeWindowMaskLimit + 1,
            textFollowRuleCount: MaskAccessPolicy.freeTextFollowRuleLimit + 1
        )
        let restored = MaskStore(storageURL: url)
        XCTAssertEqual(restored.planUsage, expectedUsage)
        XCTAssertNil(restored.add(makeDisplayRegion(index: 200), hasUnlimitedAccess: false))
        XCTAssertNil(restored.add(makeWindowRegion(index: 200), hasUnlimitedAccess: false))
        XCTAssertNil(restored.addTextRule(makeTextRule(index: 200), hasUnlimitedAccess: false))
        XCTAssertEqual(restored.planUsage, expectedUsage)
    }

    func testTextRulePersistsMatcherAndMosaicAppearance() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        let rule = TextFollowRule(
            name: "Invoice number",
            matchMode: .regex,
            pattern: #"INV-\d{4}"#,
            windowAnchor: makeWindowAnchor(windowID: 77),
            strength: 0.42,
            granularity: 0.63,
            tint: .warm,
            borderEnabled: false,
            cornerRadius: 11,
            padding: 9,
            isEnabled: false,
            createdAt: Date(timeIntervalSinceReferenceDate: 12_345)
        )
        XCTAssertNotNil(store.addTextRule(rule, hasUnlimitedAccess: false))

        let restored = try XCTUnwrap(MaskStore(storageURL: url).textRules.first)
        XCTAssertEqual(restored, rule)
        XCTAssertTrue(try restored.makeMatcher().matches("Invoice INV-2048"))
    }

    func testContainsTextRulePersistsAndReloadsMatcher() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        let rule = TextFollowRule(
            name: "Embedded label",
            matchMode: .contains,
            pattern: "test",
            windowAnchor: makeWindowAnchor(windowID: 78),
            createdAt: Date(timeIntervalSinceReferenceDate: 12_346)
        )
        XCTAssertNotNil(store.addTextRule(rule, hasUnlimitedAccess: false))

        let restored = try XCTUnwrap(MaskStore(storageURL: url).textRules.first)
        XCTAssertEqual(restored, rule)
        XCTAssertTrue(try restored.makeMatcher().matches("Speed test"))
        XCTAssertFalse(try restored.makeMatcher().matches("Speed Test"))
    }

    func testTextFollowSafetyCoverDefaultsOnPersistsAndMigratesSafely() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        XCTAssertTrue(store.textFollowSafetyCoverEnabled)

        store.textFollowSafetyCoverEnabled = false
        XCTAssertFalse(MaskStore(storageURL: url).textFollowSafetyCoverEnabled)
        store.removeAll()
        XCTAssertFalse(
            MaskStore(storageURL: url).textFollowSafetyCoverEnabled,
            "Delete All removes masks and rules, but must preserve this global preference."
        )

        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: store.exportData()) as? [String: Any]
        )
        legacy.removeValue(forKey: "textFollowSafetyCoverEnabled")
        try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
            .write(to: url, options: .atomic)

        let migrated = MaskStore(storageURL: url)
        XCTAssertNil(migrated.recoveryIssue)
        XCTAssertTrue(migrated.textFollowSafetyCoverEnabled)
        let migratedJSON = try XCTUnwrap(
            JSONSerialization.jsonObject(with: migrated.exportData()) as? [String: Any]
        )
        XCTAssertEqual(migratedJSON["textFollowSafetyCoverEnabled"] as? Bool, true)
    }

    func testLegacySnapshotWithoutTextRulesMigratesToAnEmptyRuleList() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        XCTAssertNotNil(store.add(makeDisplayRegion(index: 0), hasUnlimitedAccess: true))
        var legacy = try XCTUnwrap(
            JSONSerialization.jsonObject(with: store.exportData()) as? [String: Any]
        )
        legacy.removeValue(forKey: "textRules")
        try JSONSerialization.data(withJSONObject: legacy, options: [.sortedKeys])
            .write(to: url, options: .atomic)

        let restored = MaskStore(storageURL: url)
        XCTAssertNil(restored.recoveryIssue)
        XCTAssertEqual(restored.regions.count, 1)
        XCTAssertTrue(restored.textRules.isEmpty)

        let migrated = try XCTUnwrap(
            JSONSerialization.jsonObject(with: restored.exportData()) as? [String: Any]
        )
        XCTAssertNotNil(migrated["textRules"])
    }

    func testRejectsInvalidTextRulePatternsAnchorsAndNonFiniteAppearance() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        XCTAssertNil(store.addTextRule(
            makeTextRule(index: 0, mode: .regex, pattern: "[unterminated"),
            hasUnlimitedAccess: false
        ))
        XCTAssertNil(store.addTextRule(
            makeTextRule(
                index: 1,
                pattern: String(repeating: "x", count: TextFollowRule.maximumPatternLength + 1)
            ),
            hasUnlimitedAccess: false
        ))

        var nonFinite = makeTextRule(index: 2)
        nonFinite.strength = .nan
        XCTAssertNil(store.addTextRule(nonFinite, hasUnlimitedAccess: false))

        var invalidPadding = makeTextRule(index: 3)
        invalidPadding.padding = TextFollowRule.maximumPadding + 1
        XCTAssertNil(store.addTextRule(invalidPadding, hasUnlimitedAccess: false))

        var invalidAnchor = makeTextRule(index: 4)
        invalidAnchor.windowAnchor.windowID = 0
        XCTAssertNil(store.addTextRule(invalidAnchor, hasUnlimitedAccess: false))
        XCTAssertTrue(store.textRules.isEmpty)
    }

    func testLiveTextRuleUpdatePublishesNewestValueAndCoalescesPersistence() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BlurFollowTests-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent("Masks.json")
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = MaskStore(storageURL: url)
        var rule = try XCTUnwrap(store.addTextRule(
            makeTextRule(index: 0),
            hasUnlimitedAccess: true
        ))
        let originalStrength = rule.strength

        rule.strength = 0.3
        store.updateTextRuleLive(rule)
        rule.strength = 0.9
        store.updateTextRuleLive(rule)

        XCTAssertEqual(store.textRules.first?.strength, 0.9)
        XCTAssertEqual(MaskStore(storageURL: url).textRules.first?.strength, originalStrength)

        store.flushPersistence()
        XCTAssertEqual(MaskStore(storageURL: url).textRules.first?.strength, 0.9)
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
        original.textFollowSafetyCoverEnabled = false
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
        original.textFollowSafetyCoverEnabled = false
        // A subsequent valid write promotes the previous snapshot to the backup file.
        original.coverLastPositionEnabled.toggle()
        try Data("{not-json".utf8).write(to: url, options: .atomic)

        let restored = MaskStore(storageURL: url)
        XCTAssertEqual(restored.regions.first?.name, "Recovered mask")
        XCTAssertFalse(restored.textFollowSafetyCoverEnabled)
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
        XCTAssertTrue(store.textFollowSafetyCoverEnabled)
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
        XCTAssertNotNil(store.addTextRule(makeTextRule(index: 0), hasUnlimitedAccess: true))
        store.coverLastPositionEnabled.toggle()
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))

        store.removeAll()
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupURL.path))
        let restored = MaskStore(storageURL: url)
        XCTAssertTrue(restored.regions.isEmpty)
        XCTAssertTrue(restored.textRules.isEmpty)
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

private extension MaskStoreTests {
    func makeDisplayRegion(index: Int, isEnabled: Bool = true) -> MaskRegion {
        MaskRegion(
            name: "Display mask \(index)",
            mode: .display,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            isEnabled: isEnabled
        )
    }

    func makeWindowRegion(index: Int, isEnabled: Bool = true) -> MaskRegion {
        MaskRegion(
            name: "Window mask \(index)",
            mode: .window,
            normalizedRect: UnitRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
            windowAnchor: makeWindowAnchor(windowID: UInt32(index + 1)),
            isEnabled: isEnabled
        )
    }

    func makeTextRule(
        index: Int,
        mode: TextMatchMode = .exact,
        pattern: String? = nil,
        isEnabled: Bool = true
    ) -> TextFollowRule {
        TextFollowRule(
            name: "Text rule \(index)",
            matchMode: mode,
            pattern: pattern ?? "Sensitive value \(index)",
            windowAnchor: makeWindowAnchor(windowID: UInt32(index + 1)),
            isEnabled: isEnabled
        )
    }

    func makeWindowAnchor(windowID: UInt32) -> WindowAnchor {
        WindowAnchor(
            windowID: windowID,
            bundleIdentifier: "com.example.window",
            applicationName: "Example",
            windowTitle: "Example Window \(windowID)",
            initialFrame: CodableRect(CGRect(x: 100, y: 100, width: 800, height: 600)),
            processID: 42
        )
    }
}
