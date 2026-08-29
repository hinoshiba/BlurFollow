import XCTest
@testable import BlurFollow

final class TextFollowOverlayPanelTests: XCTestCase {
    @MainActor
    func testOneWindowSizedPanelRendersEveryMatchAsSubview() throws {
        let panel = TextFollowOverlayPanel()
        let rule = makeRule()
        let windowFrame = CGRect(x: 100, y: 200, width: 500, height: 300)
        let matches = [
            UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.25),
            UnitRect(x: 0.6, y: 0.5, width: 0.2, height: 0.1)
        ]
        defer { panel.close() }

        panel.update(rule: rule, windowFrame: windowFrame, normalizedRects: matches)

        XCTAssertEqual(panel.frame, windowFrame)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertFalse(panel.canBecomeKey)
        let views = try XCTUnwrap(panel.contentView).subviews.compactMap { $0 as? MaskEffectView }
        XCTAssertEqual(views.count, 2)
        XCTAssertEqual(views[0].frame, CGRect(x: 50, y: 60, width: 150, height: 75))
        XCTAssertEqual(views[1].frame, CGRect(x: 300, y: 150, width: 100, height: 30))
    }

    @MainActor
    func testMatchViewsAreReusedAndExcessViewsAreRemoved() throws {
        let panel = TextFollowOverlayPanel()
        let rule = makeRule()
        let windowFrame = CGRect(x: 100, y: 200, width: 500, height: 300)
        defer { panel.close() }

        panel.update(
            rule: rule,
            windowFrame: windowFrame,
            normalizedRects: [
                UnitRect(x: 0.1, y: 0.2, width: 0.3, height: 0.25),
                UnitRect(x: 0.6, y: 0.5, width: 0.2, height: 0.1)
            ]
        )
        var views = try XCTUnwrap(panel.contentView).subviews.compactMap { $0 as? MaskEffectView }
        let firstIdentifier = ObjectIdentifier(views[0])
        let secondIdentifier = ObjectIdentifier(views[1])

        panel.update(
            rule: rule,
            windowFrame: CGRect(x: 300, y: 400, width: 800, height: 600),
            normalizedRects: [
                UnitRect(x: 0.2, y: 0.3, width: 0.1, height: 0.1),
                UnitRect(x: 0.5, y: 0.6, width: 0.3, height: 0.2)
            ]
        )
        views = try XCTUnwrap(panel.contentView).subviews.compactMap { $0 as? MaskEffectView }
        XCTAssertEqual(views.map(ObjectIdentifier.init), [firstIdentifier, secondIdentifier])

        let removedView = views[1]
        panel.update(
            rule: rule,
            windowFrame: windowFrame,
            normalizedRects: [UnitRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2)]
        )
        views = try XCTUnwrap(panel.contentView).subviews.compactMap { $0 as? MaskEffectView }
        XCTAssertEqual(views.count, 1)
        XCTAssertEqual(ObjectIdentifier(views[0]), firstIdentifier)
        XCTAssertNil(removedView.superview)

        panel.clearMatches()
        XCTAssertTrue(try XCTUnwrap(panel.contentView).subviews.isEmpty)
    }

    @MainActor
    func testFullWindowSafetyCoverHasNoTransparentRoundedCorners() throws {
        let panel = TextFollowOverlayPanel()
        var rule = makeRule()
        rule.cornerRadius = 40
        rule.borderEnabled = true
        let windowFrame = CGRect(x: 100, y: 200, width: 500, height: 300)
        defer { panel.close() }

        panel.update(
            rule: rule,
            windowFrame: windowFrame,
            normalizedRects: [.full],
            usesSafetyCover: true
        )

        let view = try XCTUnwrap(
            panel.contentView?.subviews.compactMap { $0 as? MaskEffectView }.first
        )
        XCTAssertEqual(view.frame, CGRect(origin: .zero, size: windowFrame.size))
        XCTAssertEqual(view.layer?.cornerRadius, 0)
    }

    private func makeRule() -> TextFollowRule {
        TextFollowRule(
            name: "Sensitive text",
            matchMode: .exact,
            pattern: "secret",
            windowAnchor: WindowAnchor(
                windowID: 42,
                bundleIdentifier: "com.example.app",
                applicationName: "Example",
                windowTitle: "Example Window",
                initialFrame: CodableRect(CGRect(x: 100, y: 200, width: 500, height: 300)),
                processID: 123
            )
        )
    }
}
