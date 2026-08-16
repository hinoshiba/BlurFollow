import CoreImage
import XCTest
@testable import BlurFollow

final class SharePreviewCompositorTests: XCTestCase {
    func testRedactChangesOnlySelectedArea() throws {
        let extent = CGRect(x: 0, y: 0, width: 100, height: 100)
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        let region = MaskRegion(
            name: "secret",
            mode: .window,
            normalizedRect: UnitRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            style: .redact
        )

        let output = SharePreviewCompositor.applying(regions: [region], to: source)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let image = context.createCGImage(output, from: extent) else {
            return XCTFail("Could not render compositor output")
        }

        let corner = try pixel(at: CGPoint(x: 10, y: 10), in: image)
        let center = try pixel(at: CGPoint(x: 50, y: 50), in: image)
        XCTAssertGreaterThan(corner.red, 240)
        XCTAssertLessThan(corner.green, 10)
        XCTAssertLessThan(center.red, 20)
        XCTAssertLessThan(center.green, 20)
        XCTAssertLessThan(center.blue, 30)
    }

    func testDisabledRegionDoesNotAlterFrame() throws {
        let extent = CGRect(x: 0, y: 0, width: 20, height: 20)
        let source = CIImage(color: CIColor(red: 0, green: 1, blue: 0, alpha: 1)).cropped(to: extent)
        var region = MaskRegion(
            name: "disabled",
            mode: .window,
            normalizedRect: .full,
            style: .redact
        )
        region.isEnabled = false
        let output = SharePreviewCompositor.applying(regions: [region], to: source)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let image = context.createCGImage(output, from: extent) else {
            return XCTFail("Could not render compositor output")
        }
        let sample = try pixel(at: CGPoint(x: 10, y: 10), in: image)
        XCTAssertGreaterThan(sample.green, 240)
        XCTAssertLessThan(sample.red, 10)
    }

    func testMaskUsesContentRectInsteadOfLetterboxExtent() throws {
        let extent = CGRect(x: 0, y: 0, width: 200, height: 100)
        let contentRect = CGRect(x: 50, y: 0, width: 100, height: 100)
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        let region = MaskRegion(
            name: "left quarter",
            mode: .window,
            normalizedRect: UnitRect(x: 0, y: 0, width: 0.25, height: 1),
            style: .redact
        )

        let output = SharePreviewCompositor.applying(
            regions: [region],
            to: source,
            contentRect: contentRect
        )
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let image = context.createCGImage(output, from: extent) else {
            return XCTFail("Could not render compositor output")
        }

        XCTAssertGreaterThan(try pixel(at: CGPoint(x: 20, y: 50), in: image).red, 240)
        XCTAssertLessThan(try pixel(at: CGPoint(x: 60, y: 50), in: image).red, 20)
        XCTAssertGreaterThan(try pixel(at: CGPoint(x: 100, y: 50), in: image).red, 240)
    }

    func testRedactWinsWhenMasksOverlapRegardlessOfInputOrder() throws {
        let extent = CGRect(x: 0, y: 0, width: 100, height: 100)
        let source = CIImage(color: CIColor(red: 1, green: 0, blue: 0, alpha: 1)).cropped(to: extent)
        let redact = MaskRegion(
            name: "redact",
            mode: .window,
            normalizedRect: UnitRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
            style: .redact
        )
        let frost = MaskRegion(
            name: "frost",
            mode: .window,
            normalizedRect: UnitRect(x: 0.4, y: 0.4, width: 0.5, height: 0.5),
            style: .frost
        )

        let output = SharePreviewCompositor.applying(regions: [redact, frost], to: source)
        let context = CIContext(options: [.useSoftwareRenderer: true])
        guard let image = context.createCGImage(output, from: extent) else {
            return XCTFail("Could not render compositor output")
        }
        let overlap = try pixel(at: CGPoint(x: 50, y: 50), in: image)
        XCTAssertLessThan(overlap.red, 20)
        XCTAssertLessThan(overlap.green, 20)
        XCTAssertLessThan(overlap.blue, 30)
    }

    func testFrameGeometryConvertsPointsToPixelsAndRejectsClipping() {
        let extent = CGRect(x: 0, y: 0, width: 200, height: 100)
        XCTAssertEqual(
            SharePreviewFrameGeometry.contentPixelRect(
                contentRectInPoints: CGRect(x: 10, y: 5, width: 80, height: 40),
                scaleFactor: 2,
                extent: extent
            ),
            CGRect(x: 20, y: 10, width: 160, height: 80)
        )
        XCTAssertNil(
            SharePreviewFrameGeometry.contentPixelRect(
                contentRectInPoints: CGRect(x: 90, y: 0, width: 80, height: 40),
                scaleFactor: 2,
                extent: extent
            )
        )
    }

    func testValidatedCompositorRejectsSubpixelMask() {
        let extent = CGRect(x: 0, y: 0, width: 100, height: 100)
        let source = CIImage(color: .red).cropped(to: extent)
        let tiny = MaskRegion(
            name: "too small for this output",
            mode: .window,
            normalizedRect: UnitRect(x: 0, y: 0, width: 0.002, height: 0.002),
            style: .redact
        )
        XCTAssertNil(
            SharePreviewCompositor.applyingValidated(
                regions: [tiny],
                to: source,
                contentRect: extent
            )
        )
    }

    private func pixel(at point: CGPoint, in image: CGImage) throws -> (red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8) {
        guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else {
            throw NSError(domain: "SharePreviewCompositorTests", code: 1)
        }
        let x = min(max(Int(point.x), 0), image.width - 1)
        let y = min(max(Int(point.y), 0), image.height - 1)
        let offset = y * image.bytesPerRow + x * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2], bytes[offset + 3])
    }
}
