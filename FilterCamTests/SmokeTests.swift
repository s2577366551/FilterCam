import XCTest
@testable import FilterCam

final class SmokeTests: XCTestCase {
    func testThemeHitTargetIsAccessible() {
        XCTAssertGreaterThanOrEqual(Theme.hitTarget, 44)
    }
}
