import CoreImage

enum SharePreviewCompositor {
    static func applyingValidated(
        regions: [MaskRegion],
        to source: CIImage,
        contentRect: CGRect,
        appearanceScale: CGFloat = 1
    ) -> CIImage? {
        let container = contentRect.intersection(source.extent)
        let enabled = regions.filter(\.isEnabled)
        guard appearanceScale.isFinite, appearanceScale > 0,
              !enabled.isEmpty, container.width > 1, container.height > 1 else { return nil }
        guard enabled.allSatisfy({ region in
            let rect = region.normalizedRect.rect(in: container).intersection(container)
            return rect.width > 1 && rect.height > 1
        }) else { return nil }
        return applying(
            regions: enabled,
            to: source,
            contentRect: container,
            appearanceScale: appearanceScale
        )
    }

    static func applying(
        regions: [MaskRegion],
        to source: CIImage,
        contentRect: CGRect? = nil,
        appearanceScale: CGFloat = 1
    ) -> CIImage {
        let extent = source.extent
        let container = (contentRect ?? extent).intersection(extent)
        guard appearanceScale.isFinite, appearanceScale > 0,
              container.width > 1, container.height > 1 else { return blocked(source) }
        var result = source

        let orderedRegions = regions.filter(\.isEnabled).sorted {
            maskStrengthRank($0.style) < maskStrengthRank($1.style)
        }
        for region in orderedRegions {
            let maskRect = region.normalizedRect.rect(in: container).intersection(container)
            guard maskRect.width > 1, maskRect.height > 1 else { continue }
            // Each effect consumes the accumulated result. Otherwise a later frost/mosaic mask
            // could reconstruct source pixels underneath an earlier redact mask where they overlap.
            let maskedImage = effectImage(
                for: region,
                source: result,
                maskRect: maskRect,
                extent: extent,
                appearanceScale: appearanceScale
            )
            let mask = roundedMask(
                rect: maskRect,
                // Redact is the opaque fail-safe style. Preserve its full saved rectangle so
                // source pixels can never remain visible in rounded corners.
                cornerRadius: region.style == .redact
                    ? 0
                    : CGFloat(region.cornerRadius) * appearanceScale,
                extent: extent
            )
            result = maskedImage.applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: result,
                    kCIInputMaskImageKey: mask
                ]
            )
            if region.style != .redact && region.borderEnabled {
                result = applyingBorder(
                    to: result,
                    region: region,
                    maskRect: maskRect,
                    extent: extent,
                    appearanceScale: appearanceScale
                )
            }
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

    private static func effectImage(
        for region: MaskRegion,
        source: CIImage,
        maskRect: CGRect,
        extent: CGRect,
        appearanceScale: CGFloat
    ) -> CIImage {
        let logicalMaskSize = CGSize(
            width: maskRect.width / appearanceScale,
            height: maskRect.height / appearanceScale
        )
        let parameters = MaskVisualParameters.resolve(
            strength: region.strength,
            granularity: region.granularity,
            maskSize: logicalMaskSize
        )
        switch region.style {
        case .frost:
            let blurred = source
                .clampedToExtent()
                .applyingFilter(
                    "CIGaussianBlur",
                    parameters: [
                        kCIInputRadiusKey:
                            (6 + parameters.frostAdditionalBlurRadius) * Double(appearanceScale)
                    ]
                )
                .cropped(to: extent)
            return styledEffect(
                blurred,
                over: source,
                tint: region.tint,
                effectOpacity: parameters.frostEffectOpacity,
                tintOpacity: parameters.frostTintOpacity,
                extent: extent
            )
        case .mosaic:
            let pixelated = source.applyingFilter(
                "CIPixellate",
                parameters: [
                    kCIInputScaleKey: parameters.mosaicCellSize * Double(appearanceScale),
                    kCIInputCenterKey: CIVector(x: extent.midX, y: extent.midY)
                ]
            ).cropped(to: extent)
            return styledEffect(
                pixelated,
                over: source,
                tint: region.tint,
                effectOpacity: parameters.mosaicOpacity,
                tintOpacity: parameters.frostTintOpacity,
                extent: extent
            )
        case .redact:
            return CIImage(color: CIColor(red: 0.035, green: 0.04, blue: 0.07, alpha: 1))
                .cropped(to: extent)
        }
    }

    private static func styledEffect(
        _ effect: CIImage,
        over source: CIImage,
        tint: MaskTint,
        effectOpacity: Double,
        tintOpacity: Double,
        extent: CGRect
    ) -> CIImage {
        let opacity = min(max(effectOpacity, 0), 1)
        let blendMask = CIImage(color: CIColor(
            red: CGFloat(opacity),
            green: CGFloat(opacity),
            blue: CGFloat(opacity),
            alpha: 1
        )).cropped(to: extent)
        let blended = effect.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: source,
                kCIInputMaskImageKey: blendMask
            ]
        )

        let components = tint.components
        let tintImage = CIImage(color: CIColor(
            red: CGFloat(components.red),
            green: CGFloat(components.green),
            blue: CGFloat(components.blue),
            alpha: CGFloat(min(max(tintOpacity, 0), 1))
        )).cropped(to: extent)
        return tintImage.composited(over: blended).cropped(to: extent)
    }

    private static func applyingBorder(
        to image: CIImage,
        region: MaskRegion,
        maskRect: CGRect,
        extent: CGRect,
        appearanceScale: CGFloat
    ) -> CIImage {
        let width = min(
            max(0.5, appearanceScale),
            min(maskRect.width, maskRect.height) / 2
        )
        let innerRect = maskRect.insetBy(dx: width, dy: width)
        guard innerRect.width > 0, innerRect.height > 0 else { return image }

        let outerMask = roundedMask(
            rect: maskRect,
            cornerRadius: CGFloat(region.cornerRadius) * appearanceScale,
            extent: extent
        )
        let innerBlack = roundedRectangle(
            rect: innerRect,
            cornerRadius: max(0, CGFloat(region.cornerRadius) * appearanceScale - width),
            color: .black
        )
        let borderMask = innerBlack.composited(over: outerMask).cropped(to: extent)
        let tint = region.tint.components
        let border = CIImage(color: CIColor(
            red: CGFloat(min(1, tint.red * 1.4 + 0.18)),
            green: CGFloat(min(1, tint.green * 1.4 + 0.18)),
            blue: CGFloat(min(1, tint.blue * 1.4 + 0.18)),
            alpha: 0.82
        )).cropped(to: extent)
        return border.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: image,
                kCIInputMaskImageKey: borderMask
            ]
        ).cropped(to: extent)
    }

    private static func roundedMask(
        rect: CGRect,
        cornerRadius: CGFloat,
        extent: CGRect
    ) -> CIImage {
        let background = CIImage(color: .black).cropped(to: extent)
        return roundedRectangle(rect: rect, cornerRadius: cornerRadius, color: .white)
            .composited(over: background)
            .cropped(to: extent)
    }

    private static func roundedRectangle(
        rect: CGRect,
        cornerRadius: CGFloat,
        color: CIColor
    ) -> CIImage {
        guard cornerRadius > 0,
              let generated = CIFilter(
                name: "CIRoundedRectangleGenerator",
                parameters: [
                    "inputExtent": CIVector(cgRect: rect),
                    "inputRadius": min(cornerRadius, min(rect.width, rect.height) / 2),
                    "inputColor": color
                ]
              )?.outputImage else {
            return CIImage(color: color).cropped(to: rect)
        }
        return generated.cropped(to: rect)
    }
}

enum SharePreviewFrameGeometry {
    /// Converts point-sized mask appearance values into the stream's output pixels.
    static func appearanceScale(
        scaleFactor: CGFloat,
        contentScale: CGFloat
    ) -> CGFloat? {
        guard scaleFactor.isFinite, contentScale.isFinite,
              (1...4).contains(scaleFactor), contentScale > 0 else { return nil }
        let result = scaleFactor * contentScale
        return result.isFinite && result > 0 ? result : nil
    }

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
