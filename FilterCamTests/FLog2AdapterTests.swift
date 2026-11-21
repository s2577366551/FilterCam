import XCTest
@testable import FilterCam

final class FLog2AdapterTests: XCTestCase {
    private func constantCube(dimension: Int, value: Float) -> CubeLUT {
        let count = dimension * dimension * dimension
        var rgba = [Float](repeating: 1, count: count * 4)
        for index in 0..<count {
            rgba[index * 4] = value
            rgba[index * 4 + 1] = value
            rgba[index * 4 + 2] = value
        }
        return CubeLUT(title: "constant", dimension: dimension, rgba: rgba)
    }

    func testOutputSizeMatchesInputDimension() {
        let cube = constantCube(dimension: 3, value: 0.5)
        let data = FLog2Adapter.adapt(cube)
        XCTAssertEqual(data.dimension, 3)
        XCTAssertEqual(data.data.count, 27 * 4 * 4)
    }

    func testConstantLUTStaysConstantAfterAdaptation() {
        let cube = constantCube(dimension: 3, value: 0.18)
        let data = FLog2Adapter.adapt(cube)

        let floats: [Float] = data.data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }
        let first = floats[0]
        XCTAssertTrue(first.isFinite)
        XCTAssertGreaterThan(first, 0)

        for index in stride(from: 0, to: floats.count, by: 4) {
            XCTAssertEqual(floats[index], first, accuracy: 0.001)
            XCTAssertEqual(floats[index + 1], first, accuracy: 0.001)
            XCTAssertEqual(floats[index + 2], first, accuracy: 0.001)
        }
    }

    func testIdentityLUTProducesMonotonicGrayRamp() {
        let n = 5
        var rgba = [Float](repeating: 1, count: n * n * n * 4)
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let index = (r + g * n + b * n * n) * 4
                    rgba[index] = Float(r) / Float(n - 1)
                    rgba[index + 1] = Float(g) / Float(n - 1)
                    rgba[index + 2] = Float(b) / Float(n - 1)
                }
            }
        }
        let cube = CubeLUT(title: nil, dimension: n, rgba: rgba)
        let data = FLog2Adapter.adapt(cube)
        let floats: [Float] = data.data.withUnsafeBytes { buffer in
            Array(buffer.bindMemory(to: Float.self))
        }

        var previous: Float = -1
        for b in 0..<n {
            let index = (0 + 0 * n + b * n * n) * 4
            let value = floats[index]
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
    }
}
