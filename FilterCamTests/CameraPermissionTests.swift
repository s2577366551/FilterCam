import AVFoundation
import XCTest
@testable import FilterCam

final class CameraPermissionTests: XCTestCase {
    func testMapsNotDetermined() {
        XCTAssertEqual(CameraAuthorization.map(.notDetermined), .notDetermined)
    }

    func testMapsAuthorized() {
        XCTAssertEqual(CameraAuthorization.map(.authorized), .authorized)
    }

    func testMapsDenied() {
        XCTAssertEqual(CameraAuthorization.map(.denied), .denied)
    }

    func testMapsRestricted() {
        XCTAssertEqual(CameraAuthorization.map(.restricted), .restricted)
    }
}
