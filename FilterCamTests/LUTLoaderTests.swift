import CoreImage
import XCTest
@testable import FilterCam

final class LUTLoaderTests: XCTestCase {
    func testLoadsEveryPresetLUT() throws {
        let loader = LUTLoader()
        let names = PresetCatalog.all.compactMap(\.lutName)
        XCTAssertEqual(names.count, 42)
        for name in names {
            let cube = try loader.colorCube(named: name)
            XCTAssertEqual(cube.dimension, 32, "\(name) 维度错误")
            XCTAssertEqual(
                cube.cubeData?.count,
                32 * 32 * 32 * 4 * 4,
                "\(name) 数据长度错误"
            )
        }
    }

    func testMissingResourceThrows() {
        let loader = LUTLoader()
        XCTAssertThrowsError(try loader.colorCube(named: "does_not_exist")) { error in
            XCTAssertEqual(error as? LUTError, .missingResource("does_not_exist"))
        }
    }

    func testCacheReturnsEquivalentCube() throws {
        let loader = LUTLoader()
        let first = try loader.colorCube(named: "sim_chrome")
        let second = try loader.colorCube(named: "sim_chrome")
        XCTAssertEqual(first.cubeData, second.cubeData)
    }
}
