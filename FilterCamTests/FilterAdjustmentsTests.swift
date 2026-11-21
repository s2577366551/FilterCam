import CoreImage
import XCTest
@testable import FilterCam

final class FilterAdjustmentsTests: XCTestCase {
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    private func solidImage() -> CIImage {
        CIImage(color: CIColor(red: 0.4, green: 0.4, blue: 0.4, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    private func luma(_ image: CIImage) -> UInt8 {
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return bytes[0]
    }

    func testNeutralMatchesBaseline() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let preset = PresetCatalog.byID["sim_standard"]!
        let baseline = pipeline.process(solidImage(), preset: preset, intensity: 1)
        let neutral = pipeline.process(
            solidImage(),
            preset: preset,
            intensity: 1,
            adjustments: .neutral
        )
        XCTAssertEqual(luma(baseline), luma(neutral))
    }

    func testPositiveExposureBrightens() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let preset = PresetCatalog.byID["sim_standard"]!
        let base = pipeline.process(solidImage(), preset: preset, intensity: 1)
        var adjustments = FilterAdjustments.neutral
        adjustments.exposure = 1
        let bright = pipeline.process(
            solidImage(),
            preset: preset,
            intensity: 1,
            adjustments: adjustments
        )
        XCTAssertGreaterThan(luma(bright), luma(base))
    }

    func testNegativeExposureDarkens() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let preset = PresetCatalog.byID["sim_standard"]!
        let base = pipeline.process(solidImage(), preset: preset, intensity: 1)
        var adjustments = FilterAdjustments.neutral
        adjustments.exposure = -1
        let dark = pipeline.process(
            solidImage(),
            preset: preset,
            intensity: 1,
            adjustments: adjustments
        )
        XCTAssertLessThan(luma(dark), luma(base))
    }

    func testNeutralDetection() {
        XCTAssertTrue(FilterAdjustments.neutral.isNeutral)
        var adjustments = FilterAdjustments.neutral
        adjustments.grain = 0.1
        XCTAssertFalse(adjustments.isNeutral)
    }
}
