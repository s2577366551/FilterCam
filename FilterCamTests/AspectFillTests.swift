import XCTest
@testable import FilterCam

final class AspectFillTests: XCTestCase {
    func testWideContentFillsTallBounds() {
        let transform = AspectFill.transform(
            contentSize: CGSize(width: 100, height: 200),
            in: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        let origin = CGPoint.zero.applying(transform)
        XCTAssertEqual(origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(origin.y, -150, accuracy: 0.001)
    }

    func testTallContentFillsWideBounds() {
        let transform = AspectFill.transform(
            contentSize: CGSize(width: 200, height: 100),
            in: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        let origin = CGPoint.zero.applying(transform)
        XCTAssertEqual(origin.x, -150, accuracy: 0.001)
        XCTAssertEqual(origin.y, 0, accuracy: 0.001)
    }

    func testMatchingAspectRatioHasNoOffset() {
        let transform = AspectFill.transform(
            contentSize: CGSize(width: 100, height: 100),
            in: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        let origin = CGPoint.zero.applying(transform)
        XCTAssertEqual(origin.x, 0, accuracy: 0.001)
        XCTAssertEqual(origin.y, 0, accuracy: 0.001)
    }

    func testZeroSizeReturnsIdentity() {
        let transform = AspectFill.transform(
            contentSize: .zero,
            in: CGRect(x: 0, y: 0, width: 300, height: 300)
        )
        XCTAssertEqual(transform, .identity)
    }
}
