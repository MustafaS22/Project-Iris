import XCTest
@testable import IrisCore

final class AvatarCursorTests: XCTestCase {
    func testOnlyNearbyPointersAttractTheGaze() {
        XCTAssertEqual(AvatarCursorMotion.target(dx: 300, dy: 0, size: 64).weight, 0)
        XCTAssertEqual(AvatarCursorMotion.target(dx: 30, dy: 20, size: 64).weight, 1)
        XCTAssertEqual(AvatarCursorMotion.target(dx: .nan, dy: 0, size: 64), AvatarCursorGaze())
    }
    func testDirectionsAndMovementStayBounded() {
        let rightDown = AvatarCursorMotion.target(dx: 90, dy: 70, size: 64)
        let leftUp = AvatarCursorMotion.target(dx: -90, dy: -70, size: 64)
        XCTAssertGreaterThan(rightDown.x, 0); XCTAssertGreaterThan(rightDown.y, 0)
        XCTAssertLessThan(leftUp.x, 0); XCTAssertLessThan(leftUp.y, 0)
        XCTAssertLessThanOrEqual(abs(rightDown.x), 0.105)
        XCTAssertLessThanOrEqual(abs(rightDown.y), 0.085)
    }
    func testProximityFadesContinuouslyAtTheBoundary() {
        let near = AvatarCursorMotion.target(dx: 191.99, dy: 0, size: 64)
        let far = AvatarCursorMotion.target(dx: 192.01, dy: 0, size: 64)
        XCTAssertEqual(near.weight, far.weight, accuracy: 0.00001)
    }
    func testEntryAndExitEaseWithoutOvershoot() {
        var motion = AvatarCursorMotion()
        let target = AvatarCursorMotion.target(dx: 60, dy: 0, size: 64)
        let first = motion.update(target: target, at: 0)
        XCTAssertGreaterThan(first.weight, 0); XCTAssertLessThan(first.weight, 0.2)
        for frame in 1...60 { _ = motion.update(target: target, at: Double(frame) / 60) }
        XCTAssertGreaterThan(motion.gaze.weight, 0.99)
        let exit = motion.update(target: .init(), at: 1 + 1.0 / 60)
        XCTAssertGreaterThan(exit.weight, 0.8)
        for frame in 62...150 { _ = motion.update(target: .init(), at: Double(frame) / 60) }
        XCTAssertLessThan(motion.gaze.weight, 0.0001)
    }
    func testCursorDoesNotChangeBlinksExpressionsOrFloating() {
        let pose = AvatarMotion(state: .error, at: 0).pose(at: 15.09)
        let result = AvatarCursorMotion.apply(.init(x: 0.1, y: -0.08, weight: 1), to: pose)
        XCTAssertEqual(result.anger, pose.anger)
        XCTAssertEqual(result.leftOpen, pose.leftOpen)
        XCTAssertEqual(result.rightOpen, pose.rightOpen)
        XCTAssertEqual(result.floatY, pose.floatY)
        XCTAssertEqual(result.gazeX, 0.1)
        XCTAssertEqual(result.gazeY, -0.08)
    }
}
