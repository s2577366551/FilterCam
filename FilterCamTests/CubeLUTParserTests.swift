import XCTest
@testable import FilterCam

final class CubeLUTParserTests: XCTestCase {
    private let identity2 = """
    TITLE "Test LUT"
    LUT_3D_SIZE 2
    0 0 0
    1 0 0
    0 1 0
    1 1 0
    0 0 1
    1 0 1
    0 1 1
    1 1 1
    """

    func testParsesMinimalCube() throws {
        let cube = try CubeLUTParser.parse(text: identity2)
        XCTAssertEqual(cube.dimension, 2)
        XCTAssertEqual(cube.title, "Test LUT")
        XCTAssertEqual(cube.rgba.count, 8 * 4)

        let red = cube.sample(SIMD3(1, 0, 0))
        XCTAssertEqual(red.x, 1, accuracy: 0.001)
        XCTAssertEqual(red.y, 0, accuracy: 0.001)
        XCTAssertEqual(red.z, 0, accuracy: 0.001)
    }

    func testMissingSizeThrows() {
        XCTAssertThrowsError(try CubeLUTParser.parse(text: "0 0 0\n")) { error in
            XCTAssertEqual(error as? CubeLUTError, .missingSize)
        }
    }

    func testUnsupported1DThrows() {
        let text = "LUT_1D_SIZE 2\n0 0 0\n1 1 1\n"
        XCTAssertThrowsError(try CubeLUTParser.parse(text: text)) { error in
            XCTAssertEqual(error as? CubeLUTError, .unsupported1D)
        }
    }

    func testWrongRowCountThrows() {
        let text = """
        LUT_3D_SIZE 2
        0 0 0
        1 1 1
        """
        XCTAssertThrowsError(try CubeLUTParser.parse(text: text)) { error in
            XCTAssertEqual(error as? CubeLUTError, .wrongRowCount(expected: 8, actual: 2))
        }
    }

    func testInvalidRowThrows() {
        let text = """
        LUT_3D_SIZE 2
        0 0 0
        1 1
        """
        XCTAssertThrowsError(try CubeLUTParser.parse(text: text)) { error in
            XCTAssertEqual(error as? CubeLUTError, .invalidRow(2))
        }
    }

    func testDomainIsNormalized() throws {
        let text = """
        LUT_3D_SIZE 2
        DOMAIN_MIN 0 0 0
        DOMAIN_MAX 2 2 2
        0 0 0
        2 0 0
        0 2 0
        2 2 0
        0 0 2
        2 0 2
        0 2 2
        2 2 2
        """
        let cube = try CubeLUTParser.parse(text: text)
        let white = cube.sample(SIMD3(1, 1, 1))
        XCTAssertEqual(white.x, 1, accuracy: 0.001)
        XCTAssertEqual(white.y, 1, accuracy: 0.001)
        XCTAssertEqual(white.z, 1, accuracy: 0.001)
    }

    func testInvalidSizeThrows() {
        let text = "LUT_3D_SIZE 1\n0 0 0\n"
        XCTAssertThrowsError(try CubeLUTParser.parse(text: text)) { error in
            XCTAssertEqual(error as? CubeLUTError, .invalidSize(1))
        }
    }
}
