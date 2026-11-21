import CoreImage

protocol FilterPipeline {
    func process(
        _ image: CIImage,
        preset: FilterPreset,
        intensity: Float,
        adjustments: FilterAdjustments
    ) -> CIImage
}

extension FilterPipeline {
    func process(_ image: CIImage, preset: FilterPreset, intensity: Float) -> CIImage {
        process(image, preset: preset, intensity: intensity, adjustments: .neutral)
    }
}
