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
        let insideRectCorner = try pixel(at: CGPoint(x: 26, y: 26), in: image)
        let center = try pixel(at: CGPoint(x: 50, y: 50), in: image)
        XCTAssertGreaterThan(corner.red, 240)
        XCTAssertLessThan(corner.green, 10)
        // Redact always covers the complete saved rectangle, regardless of cornerRadius.
        XCTAssertLessThan(insideRectCorner.red, 20)
        XCTAssertLessThan(insideRectCorner.green, 20)
        XCTAssertLessThan(insideRectCorner.blue, 30)
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
            SharePreviewFrameGeometry.appearanceScale(
                scaleFactor: 2,
                contentScale: 0.75
            ),
            1.5
        )
        XCTAssertNil(
            SharePreviewFrameGeometry.appearanceScale(
                scaleFactor: 2,
                contentScale: 0
            )
        )
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

    func testMosaicTintChangesRenderedColorTone() throws {
        let extent = CGRect(x: 0, y: 0, width: 80, height: 80)
        let source = CIImage(
            color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ).cropped(to: extent)
        let cool = MaskRegion(
            name: "cool",
            mode: .window,
            normalizedRect: .full,
            style: .mosaic,
            strength: 1,
            granularity: 0.5,
            tint: .cool,
            borderEnabled: false,
            cornerRadius: 0
        )
        var warm = cool
        warm.tint = .warm

        let coolPixel = try pixel(
            at: CGPoint(x: 40, y: 40),
            in: try render(SharePreviewCompositor.applying(regions: [cool], to: source), extent: extent)
        )
        let warmPixel = try pixel(
            at: CGPoint(x: 40, y: 40),
            in: try render(SharePreviewCompositor.applying(regions: [warm], to: source), extent: extent)
        )

        XCTAssertGreaterThan(Int(coolPixel.blue) - Int(coolPixel.red), 15)
        XCTAssertGreaterThan(Int(warmPixel.red) - Int(warmPixel.blue), 15)
    }

    func testConfiguredBorderChangesOnlyMaskEdge() throws {
        let extent = CGRect(x: 0, y: 0, width: 100, height: 100)
        let source = CIImage(
            color: CIColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ).cropped(to: extent)
        var withoutBorder = MaskRegion(
            name: "border",
            mode: .window,
            normalizedRect: UnitRect(x: 0.2, y: 0.2, width: 0.6, height: 0.6),
            style: .frost,
            strength: 0.7,
            granularity: 0.5,
            tint: .warm,
            borderEnabled: false,
            cornerRadius: 0
        )
        let withoutImage = try render(
            SharePreviewCompositor.applying(regions: [withoutBorder], to: source),
            extent: extent
        )
        withoutBorder.borderEnabled = true
        let withImage = try render(
            SharePreviewCompositor.applying(regions: [withoutBorder], to: source),
            extent: extent
        )

        let edgeWithout = try pixel(at: CGPoint(x: 20, y: 50), in: withoutImage)
        let edgeWith = try pixel(at: CGPoint(x: 20, y: 50), in: withImage)
        let centerWithout = try pixel(at: CGPoint(x: 50, y: 50), in: withoutImage)
        let centerWith = try pixel(at: CGPoint(x: 50, y: 50), in: withImage)

        let edgeDifference = abs(Int(edgeWith.red) - Int(edgeWithout.red))
            + abs(Int(edgeWith.green) - Int(edgeWithout.green))
            + abs(Int(edgeWith.blue) - Int(edgeWithout.blue))
        XCTAssertGreaterThan(edgeDifference, 20)
        XCTAssertLessThanOrEqual(abs(Int(centerWith.red) - Int(centerWithout.red)), 2)
        XCTAssertLessThanOrEqual(abs(Int(centerWith.green) - Int(centerWithout.green)), 2)
        XCTAssertLessThanOrEqual(abs(Int(centerWith.blue) - Int(centerWithout.blue)), 2)
    }

    func testMosaicGranularityChangesPixelationIndependently() throws {
        let extent = CGRect(x: 0, y: 0, width: 120, height: 120)
        let source = try XCTUnwrap(CIFilter(
            name: "CICheckerboardGenerator",
            parameters: [
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black,
                "inputWidth": 5,
                "inputSharpness": 1
            ]
        )?.outputImage?.cropped(to: extent))
        var fine = MaskRegion(
            name: "fine",
            mode: .window,
            normalizedRect: .full,
            style: .mosaic,
            strength: 0.8,
            granularity: 0,
            tint: .neutral,
            borderEnabled: false,
            cornerRadius: 0
        )
        let fineImage = try render(
            SharePreviewCompositor.applying(regions: [fine], to: source),
            extent: extent
        )
        fine.granularity = 1
        let coarseImage = try render(
            SharePreviewCompositor.applying(regions: [fine], to: source),
            extent: extent
        )

        XCTAssertNotEqual(try imageData(fineImage), try imageData(coarseImage))
    }

    func testFrostGranularityChangesBlurIndependently() throws {
        let extent = CGRect(x: 0, y: 0, width: 120, height: 120)
        let source = try XCTUnwrap(CIFilter(
            name: "CICheckerboardGenerator",
            parameters: [
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black,
                "inputWidth": 4,
                "inputSharpness": 1
            ]
        )?.outputImage?.cropped(to: extent))
        var fine = MaskRegion(
            name: "fine frost",
            mode: .window,
            normalizedRect: .full,
            style: .frost,
            strength: 0.8,
            granularity: 0,
            tint: .neutral,
            borderEnabled: false,
            cornerRadius: 0
        )
        let fineImage = try render(
            SharePreviewCompositor.applying(regions: [fine], to: source),
            extent: extent
        )
        fine.granularity = 1
        let coarseImage = try render(
            SharePreviewCompositor.applying(regions: [fine], to: source),
            extent: extent
        )

        XCTAssertNotEqual(try imageData(fineImage), try imageData(coarseImage))
    }

    private func render(_ image: CIImage, extent: CGRect) throws -> CGImage {
        try XCTUnwrap(
            CIContext(options: [.useSoftwareRenderer: true]).createCGImage(image, from: extent)
        )
    }

    private func imageData(_ image: CGImage) throws -> Data {
        let data = try XCTUnwrap(image.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        return Data(bytes: bytes, count: CFDataGetLength(data))
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
