import CoreImage

enum SharePreviewCompositor {
    static func applyingValidated(
        regions: [MaskRegion],
        to source: CIImage,
        contentRect: CGRect
    ) -> CIImage? {
        let container = contentRect.intersection(source.extent)
        let enabled = regions.filter(\.isEnabled)
        guard !enabled.isEmpty, container.width > 1, container.height > 1 else { return nil }
        guard enabled.allSatisfy({ region in
            let rect = region.normalizedRect.rect(in: container).intersection(container)
            return rect.width > 1 && rect.height > 1
        }) else { return nil }
        return applying(regions: enabled, to: source, contentRect: container)
    }

    static func applying(
        regions: [MaskRegion],
        to source: CIImage,
        contentRect: CGRect? = nil
    ) -> CIImage {
        let extent = source.extent
        let container = (contentRect ?? extent).intersection(extent)
        guard container.width > 1, container.height > 1 else { return blocked(source) }
        var result = source

        let orderedRegions = regions.filter(\.isEnabled).sorted {
            maskStrengthRank($0.style) < maskStrengthRank($1.style)
        }
        for region in orderedRegions {
            let maskRect = region.normalizedRect.rect(in: container).intersection(container)
            guard maskRect.width > 1, maskRect.height > 1 else { continue }
            // Each effect consumes the accumulated result. Otherwise a later frost/mosaic mask
            // could reconstruct source pixels underneath an earlier redact mask where they overlap.
            let maskedImage = effectImage(for: region, source: result, extent: extent)
            let black = CIImage(color: CIColor.black).cropped(to: extent)
            let white = CIImage(color: CIColor.white).cropped(to: maskRect)
            let mask = white.composited(over: black)
            result = maskedImage.applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: result,
                    kCIInputMaskImageKey: mask
                ]
            )
        }
        return result.cropped(to: extent)
    }

    static func blocked(_ source: CIImage) -> CIImage {
        CIImage(color: CIColor(red: 0.035, green: 0.04, blue: 0.07, alpha: 1))
            .cropped(to: source.extent)
    }

    private static func maskStrengthRank(_ style: MaskStyle) -> Int {
        switch style {
        case .frost: return 0
        case .mosaic: return 1
        case .redact: return 2
        }
    }

    private static func effectImage(for region: MaskRegion, source: CIImage, extent: CGRect) -> CIImage {
        switch region.style {
        case .frost:
            let radius = 12 + region.strength * 26
            return source
                .clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: extent)
        case .mosaic:
            let scale = 12 + region.strength * 28
            return source.applyingFilter(
                "CIPixellate",
                parameters: [
                    kCIInputScaleKey: scale,
                    kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY)
                ]
            ).cropped(to: extent)
        case .redact:
            return CIImage(color: CIColor(red: 0.035, green: 0.04, blue: 0.07, alpha: 1))
                .cropped(to: extent)
        }
    }
}

enum SharePreviewFrameGeometry {
    /// ScreenCaptureKit reports contentRect in logical points in the output surface and
    /// scaleFactor as output pixels per point. Convert that metadata to the CIImage pixel space.
    /// Invalid or materially clipped metadata returns nil so callers render a full cover.
    static func contentPixelRect(
        contentRectInPoints: CGRect,
        scaleFactor: CGFloat,
        extent: CGRect
    ) -> CGRect? {
        let values = [
            contentRectInPoints.minX, contentRectInPoints.minY,
            contentRectInPoints.width, contentRectInPoints.height,
            scaleFactor, extent.minX, extent.minY, extent.width, extent.height
        ]
        guard values.allSatisfy(\.isFinite),
              scaleFactor >= 1, scaleFactor <= 4,
              contentRectInPoints.width > 0, contentRectInPoints.height > 0,
              extent.width > 0, extent.height > 0 else { return nil }

        let pixelRect = CGRect(
            x: extent.minX + contentRectInPoints.minX * scaleFactor,
            y: extent.minY + contentRectInPoints.minY * scaleFactor,
            width: contentRectInPoints.width * scaleFactor,
            height: contentRectInPoints.height * scaleFactor
        )
        let clipped = pixelRect.intersection(extent)
        guard !clipped.isNull, clipped.width > 1, clipped.height > 1 else { return nil }

        let originalArea = pixelRect.width * pixelRect.height
        let retainedArea = clipped.width * clipped.height
        guard originalArea > 0, retainedArea / originalArea >= 0.995 else { return nil }
        return clipped.integral
    }
}
