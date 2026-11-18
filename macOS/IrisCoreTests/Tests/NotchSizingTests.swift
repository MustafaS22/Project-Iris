import XCTest
@testable import IrisCore
final class NotchSizingTests: XCTestCase {
    func testNonNotchedDisplayMatchesCurrentMac() {
        let current = NotchSizing.compact(housing: NotchSizing.housing(safeTop: 28, physicalWidth: 156))
        let plain = NotchSizing.compact(housing: NotchSizing.housing(safeTop: 0, physicalWidth: nil))
        XCTAssertEqual(current, CGSize(width: 272, height: 33)); XCTAssertEqual(plain, current)
    }
    func testLargerCameraHousingKeepsItsClearance() {
        XCTAssertEqual(NotchSizing.compact(housing: NotchSizing.housing(safeTop: 38, physicalWidth: 190)), CGSize(width: 306, height: 43))
    }
}
