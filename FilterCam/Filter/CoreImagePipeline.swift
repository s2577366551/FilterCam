import CoreImage
import CoreImage.CIFilterBuiltins

final class CoreImagePipeline: FilterPipeline {
    private let lutLoader: LUTLoading
    private let context: CIContext
    private let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)

    init(lutLoader: LUTLoading, context: CIContext) {
        self.lutLoader = lutLoader
        self.context = context
    }

    func process(
        _ image: CIImage,
        preset: FilterPreset,
        intensity: Float,
        adjustments: FilterAdjustments
    ) -> CIImage {
        let clamped = min(max(intensity, 0), 1)
        guard let lutName = preset.lutName, clamped > 0 else {
            return image
        }

        let safe = adjustments.clamped()
        var output = applyLUT(image, name: lutName)
        output = applyAdjustments(output, adjustments: safe)
        output = applyVignette(output, amount: preset.vignette)
        let grain = min(max(preset.grain + safe.grain * 0.3, 0), 1)
        output = applyGrain(output, amount: grain)
        output = output.cropped(to: image.extent)

        guard clamped < 1 else {
            return output
        }
        let dissolve = CIFilter.dissolveTransition()
        dissolve.inputImage = image
        dissolve.targetImage = output
        dissolve.time = clamped
        return (dissolve.outputImage ?? output).cropped(to: image.extent)
    }

    private func applyLUT(_ image: CIImage, name: String) -> CIImage {
        guard let lut = try? lutLoader.load(named: name) else {
            Log.filter.error("LUT 加载失败: \(name)")
            return image
        }
        let filter = CIFilter.colorCubeWithColorSpace()
        filter.inputImage = image
        filter.cubeDimension = Float(lut.dimension)
        filter.cubeData = lut.data
        filter.colorSpace = colorSpace
        return filter.outputImage ?? image
    }

    private func applyAdjustments(_ image: CIImage, adjustments: FilterAdjustments) -> CIImage {
        guard !adjustments.isNeutral else { return image }
        var output = image

        if adjustments.exposure != 0 {
            let filter = CIFilter.exposureAdjust()
            filter.inputImage = output
            filter.ev = adjustments.exposure * 0.25
            output = filter.outputImage ?? output
        }

        if adjustments.contrast != 0 {
            let filter = CIFilter.colorControls()
            filter.inputImage = output
            filter.contrast = 1 + adjustments.contrast * 0.5
            output = filter.outputImage ?? output
        }

        if adjustments.temperature != 0 {
            let filter = CIFilter.temperatureAndTint()
            filter.inputImage = output
            filter.neutral = CIVector(x: 6500, y: 0)
            filter.targetNeutral = CIVector(
                x: 6500 + CGFloat(adjustments.temperature) * 3000,
                y: 0
            )
            output = filter.outputImage ?? output
        }

        return output.cropped(to: image.extent)
    }

    private func applyVignette(_ image: CIImage, amount: Float) -> CIImage {
        guard amount > 0 else { return image }
        let filter = CIFilter.vignette()
        filter.inputImage = image
        filter.intensity = amount * 2.0
        filter.radius = 1.6
        return filter.outputImage ?? image
    }

    private func applyGrain(_ image: CIImage, amount: Float) -> CIImage {
        guard amount > 0 else { return image }
        let extent = image.extent
        guard let noise = CIFilter.randomGenerator().outputImage?.cropped(to: extent) else {
            return image
        }
        let gray = noise.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: 0
        ])
        let blended = gray.applyingFilter("CISoftLightBlendMode", parameters: [
            kCIInputBackgroundImageKey: image
        ])
        let dissolve = CIFilter.dissolveTransition()
        dissolve.inputImage = image
        dissolve.targetImage = blended
        dissolve.time = amount * 0.35
        return (dissolve.outputImage ?? image).cropped(to: extent)
    }
}
