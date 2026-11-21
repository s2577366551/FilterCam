import XCTest
@testable import FilterCam

final class UserLUTLibraryTests: XCTestCase {
    private var directory: URL!
    private let cubeText = """
    TITLE "My LUT"
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

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserLUTLibraryTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeCubeFile(name: String = "test.cube") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try cubeText.data(using: .utf8)!.write(to: url)
        return url
    }

    func testImportStoresLUTAndFile() throws {
        let library = UserLUTLibrary(directory: directory)
        let url = try makeCubeFile()
        let entry = try library.importLUT(from: url, isFLog2: false)

        XCTAssertEqual(entry.displayName, "My LUT")
        XCTAssertEqual(entry.dimension, 2)
        XCTAssertEqual(library.currentLUTs().count, 1)

        let data = try XCTUnwrap(try library.lut(for: entry.id))
        XCTAssertEqual(data.dimension, 2)
        XCTAssertEqual(data.data.count, 8 * 4 * 4)
    }

    func testImportPersistsAcrossInstances() throws {
        let first = UserLUTLibrary(directory: directory)
        _ = try first.importLUT(from: try makeCubeFile(), isFLog2: true)

        let second = UserLUTLibrary(directory: directory)
        XCTAssertEqual(second.currentLUTs().count, 1)
        XCTAssertTrue(second.currentLUTs()[0].isFLog2)
    }

    func testRenameAndDelete() throws {
        let library = UserLUTLibrary(directory: directory)
        let entry = try library.importLUT(from: try makeCubeFile(), isFLog2: false)

        library.rename(entry.id, to: "新名字")
        XCTAssertEqual(library.currentLUTs().first?.displayName, "新名字")

        library.delete(entry.id)
        XCTAssertTrue(library.currentLUTs().isEmpty)
        XCTAssertNil(try library.lut(for: entry.id))
    }

    func testInvalidFileThrows() throws {
        let library = UserLUTLibrary(directory: directory)
        let url = directory.appendingPathComponent("bad.cube")
        try "not a lut".data(using: .utf8)!.write(to: url)

        XCTAssertThrowsError(try library.importLUT(from: url, isFLog2: false))
        XCTAssertTrue(library.currentLUTs().isEmpty)
    }
}
