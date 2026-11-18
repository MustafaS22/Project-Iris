import XCTest
@testable import IrisCore

final class OnboardingGuidanceTests: XCTestCase {
    private func guide(_ step: Int, accepted: Bool = false, name: Bool = false, ai: Bool = false, knowledge: Bool = false, working: Bool = false, error: Bool = false) -> OnboardingGuidance {
        .resolve(step: step, accepted: accepted, hasName: name, aiReady: ai, hasKnowledge: knowledge, working: working, hasError: error)
    }
    func testEachUnfinishedStepPointsToItsTask() {
        let targets: [OnboardingGuidance.Target] = [.preview, .name, .themes, .intelligence, .knowledge, .tour]
        for step in 0..<6 { XCTAssertEqual(guide(step).target, targets[step]) }
    }
    func testRealSetupStateReleasesAttention() {
        XCTAssertNil(guide(1, name: true).target)
        XCTAssertNil(guide(3, ai: true).target)
        XCTAssertNil(guide(4, knowledge: true).target)
        XCTAssertEqual(guide(3, knowledge: true).target, .intelligence)
    }
    func testOptionalStepsCanBeAcceptedWithoutConnectingAnything() {
        for step in 0..<6 { XCTAssertNil(guide(step, accepted: true).target) }
    }
    func testWorkAndErrorsTakePriorityOverCompletion() {
        XCTAssertEqual(guide(3, accepted: true, ai: true, working: true).target, .intelligence)
        XCTAssertEqual(guide(4, accepted: true, working: true).target, .knowledge)
        XCTAssertEqual(guide(4, accepted: true, working: true, error: true).target, .error)
        XCTAssertNil(guide(4, working: true).acceptLabel)
    }
    func testDirectedAttentionWorksBeyondTheProximityRadius() {
        let gaze = AvatarCursorMotion.directed(dx: 600, dy: 400, size: 68)
        XCTAssertEqual(gaze.weight, 1)
        XCTAssertGreaterThan(gaze.x, 0); XCTAssertGreaterThan(gaze.y, 0)
        XCTAssertLessThanOrEqual(abs(gaze.x), 0.105)
        XCTAssertLessThanOrEqual(abs(gaze.y), 0.085)
        XCTAssertEqual(AvatarCursorMotion.directed(dx: .nan, dy: 4, size: 68), AvatarCursorGaze())
        XCTAssertEqual(AvatarCursorMotion.directed(dx: 0, dy: 0, size: 68), AvatarCursorGaze(x: 0, y: 0, weight: 1))
    }
}
