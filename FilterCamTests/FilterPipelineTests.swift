import CoreImage
import XCTest
@testable import FilterCam

final class FilterPipelineTests: XCTestCase {
    private let context = CIContext(options: [
        .workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB) as Any
    ])

    private var identityPreset: FilterPreset {
        FilterPreset(
            id: "identity",
            displayName: "恒等",
            category: .simulation,
            lutName: "identity",
            grain: 0,
            vignette: 0
        )
    }

    private func solidImage(
        red: CGFloat = 0.4,
        green: CGFloat = 0.5,
        blue: CGFloat = 0.6
    ) -> CIImage {
        CIImage(color: CIColor(red: red, green: green, blue: blue, alpha: 1))
            .cropped(to: CGRect(x: 0, y: 0, width: 8, height: 8))
    }

    private func pixel(of image: CIImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        context.render(
            image,
            toBitmap: &bytes,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return bytes
    }

    func testIntensityZeroReturnsOriginal() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let input = solidImage()
        let output = pipeline.process(input, preset: identityPreset, intensity: 0)
        XCTAssertEqual(pixel(of: output), pixel(of: input))
    }

    func testIdentityLUTPreservesColor() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let input = solidImage()
        let output = pipeline.process(input, preset: identityPreset, intensity: 1)
        let expected = pixel(of: input)
        let actual = pixel(of: output)
        for index in 0..<3 {
            let difference = abs(Int(actual[index]) - Int(expected[index]))
            XCTAssertLessThanOrEqual(difference, 2, "通道 \(index) 偏差过大")
        }
    }

    func testChromePresetChangesColor() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let input = solidImage()
        let output = pipeline.process(
            input,
            preset: PresetCatalog.byID["sim_chrome"]!,
            intensity: 1
        )
        XCTAssertNotEqual(pixel(of: output), pixel(of: input))
    }

    func testHalfIntensitySitsBetween() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let input = solidImage()
        let preset = PresetCatalog.byID["sim_chrome"]!
        let half = pixel(of: pipeline.process(input, preset: preset, intensity: 0.5))
        let original = pixel(of: input)
        let full = pixel(of: pipeline.process(input, preset: preset, intensity: 1))
        XCTAssertNotEqual(half, original)
        XCTAssertNotEqual(half, full)
    }

    func testOutputExtentMatchesInput() {
        let pipeline = CoreImagePipeline(lutLoader: LUTLoader(), context: context)
        let input = solidImage()
        let output = pipeline.process(
            input,
            preset: PresetCatalog.byID["sim_vivid"]!,
            intensity: 0.7
        )
        XCTAssertEqual(output.extent, input.extent)
    }
}
