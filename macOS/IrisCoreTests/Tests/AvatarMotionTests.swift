import XCTest
@testable import IrisCore

final class AvatarMotionTests: XCTestCase {
    func testBlinkStartsAfterFiveSecondsAndRepeats() {
        XCTAssertEqual(AvatarMotion.blink(at: 0), 0)
        XCTAssertEqual(AvatarMotion.blink(at: 4.99), 0)
        XCTAssertEqual(AvatarMotion.blink(at: 5.09), 1, accuracy: 0.00001)
        XCTAssertEqual(AvatarMotion.blink(at: 10.09), 1, accuracy: 0.00001)
        XCTAssertEqual(AvatarMotion.blink(at: 5.28), 0)
    }
    func testBothEyesBlinkTogetherWithoutCollapsingToZero() {
        let motion = AvatarMotion(state: .idle, at: 0)
        let closed = motion.pose(at: 5.09)
        XCTAssertEqual(closed.leftOpen, closed.rightOpen)
        XCTAssertGreaterThan(closed.leftOpen, 0)
        XCTAssertLessThan(closed.leftOpen, 0.06)
    }
    func testFloatingIsContinuousAndBounded() {
        let motion = AvatarMotion(state: .idle, at: 0)
        var previous = motion.pose(at: 0)
        for frame in 1...3600 {
            let current = motion.pose(at: Double(frame) / 60)
            XCTAssertLessThanOrEqual(abs(current.floatX), 0.028)
            XCTAssertLessThanOrEqual(abs(current.floatY), 0.039)
            XCTAssertLessThan(abs(current.floatX - previous.floatX), 0.001)
            XCTAssertLessThan(abs(current.floatY - previous.floatY), 0.001)
            previous = current
        }
        XCTAssertNotEqual(motion.pose(at: 2).floatY, 0)
    }
    func testThinkingLooksBothWaysAndItsGazeTransitionsSmoothly() {
        let motion = AvatarMotion(state: .thinking, at: 0, expressionSeed: 42)
        XCTAssertLessThan(motion.pose(at: 0.5).gazeX, 0)
        XCTAssertGreaterThan(motion.pose(at: 5.2).gazeX, 0)
        let before = motion.pose(at: 4.4 - 0.0001)
        let after = motion.pose(at: 4.4 + 0.0001)
        XCTAssertEqual(before.gazeX, after.gazeX, accuracy: 0.0001)
    }
    func testOnlyErrorsHaveAnAngryExpression() {
        for state in IrisState.allCases {
            let motion = AvatarMotion(state: state, at: 0, expressionSeed: 42)
            for time in [1.0, 6, 11, 27, 80] {
                XCTAssertEqual(motion.pose(at: time).anger, state == .error ? 1 : 0, state.rawValue)
            }
        }
    }
    func testIdleThinkingAndNudgesHaveVariedExpressionsWithoutAbruptChanges() {
        for state in [IrisState.idle, .thinking, .attention] {
            let motion = AvatarMotion(state: state, at: 0, expressionSeed: 42)
            let differentAvatar = AvatarMotion(state: state, at: 0, expressionSeed: 101)
            var previous = motion.pose(at: 0)
            var asymmetry = false, signature = false, distinctTiming = false
            for frame in 1...14400 {
                let time = Double(frame) / 60
                let pose = motion.pose(at: time)
                asymmetry = asymmetry || abs(pose.leftOpen - pose.rightOpen) > 0.12
                signature = signature || (state == .thinking ? pose.leftOpen > 1.19 && pose.rightOpen > 1.19 : pose.happiness > 0.85)
                distinctTiming = distinctTiming || pose.leftOpen != differentAvatar.pose(at: time).leftOpen
                XCTAssertLessThan(abs(pose.happiness - previous.happiness), 0.05)
                XCTAssertLessThan(abs(pose.gazeX - previous.gazeX), 0.04)
                previous = pose
            }
            XCTAssertTrue(asymmetry && signature && distinctTiming, state.rawValue)
            XCTAssertEqual(motion.pose(at: 1, reducedMotion: true), motion.pose(at: 19, reducedMotion: true))
        }
    }
    func testStateChangesStartAtTheExistingPose() {
        var motion = AvatarMotion(state: .thinking, at: 0)
        let before = motion.pose(at: 2)
        motion.transition(to: .error, at: 2)
        XCTAssertEqual(motion.pose(at: 2), before)
        XCTAssertEqual(motion.pose(at: 2.7).anger, 1)
        let halfway = motion.pose(at: 2.2)
        XCTAssertGreaterThan(halfway.anger, 0)
        XCTAssertLessThan(halfway.anger, 1)
    }
    func testWorkingGlancesUseFourToEightSecondIntervals() {
        XCTAssertEqual(AvatarMotion.glanceInterval(unitRandom: 0), 4)
        XCTAssertEqual(AvatarMotion.glanceInterval(unitRandom: 0.5), 6)
        XCTAssertEqual(AvatarMotion.glanceInterval(unitRandom: 1), 8)
        XCTAssertEqual(AvatarMotion.glanceInterval(unitRandom: -10), 4)
        XCTAssertEqual(AvatarMotion.glanceInterval(unitRandom: 10), 8)
    }
    func testFirstWorkingGlanceStartsSooner() {
        XCTAssertEqual(AvatarMotion.glanceInterval(unitRandom: 0, first: true), 1.5)
        XCTAssertEqual(AvatarMotion.glanceInterval(unitRandom: 1, first: true), 2.5)
    }
    func testWritingGlanceLooksDownThenReturnsSmoothly() {
        let motion = AvatarMotion(state: .thinking, at: 0)
        let before = motion.pose(at: 20, glanceStarted: 20)
        let down = motion.pose(at: 21, glanceStarted: 20)
        XCTAssertGreaterThan(down.gazeY, 0.1)
        XCTAssertEqual(down.gazeX, 0, accuracy: 0.00001)
        XCTAssertEqual(before, motion.pose(at: 20))
        XCTAssertEqual(motion.pose(at: 23, glanceStarted: 20), motion.pose(at: 23))
    }
    func testQuietHoursKeepsEyesOpenWithoutDrifting() {
        let motion = AvatarMotion(state: .sleeping, at: 0)
        let pose = motion.pose(at: 7)
        XCTAssertGreaterThan(pose.leftOpen, 0.65)
        XCTAssertGreaterThan(pose.rightOpen, 0.65)
        XCTAssertEqual(pose, motion.pose(at: 15))
    }
    func testReduceMotionKeepsExpressionAndStopsAllMovement() {
        let motion = AvatarMotion(state: .error, at: 0)
        let first = motion.pose(at: 1, reducedMotion: true)
        XCTAssertEqual(first, motion.pose(at: 5.09, glanceStarted: 14, reducedMotion: true))
        XCTAssertEqual(first.anger, 1)
        XCTAssertEqual(first.floatX, 0); XCTAssertEqual(first.floatY, 0)
        XCTAssertEqual(first.roll, 0); XCTAssertEqual(first.gazeY, 0)
    }
    func testEveryStateHasFiniteMotionEvenAfterLongUptime() {
        for state in IrisState.allCases {
            let pose = AvatarMotion(state: state, at: 1_000_000).pose(at: 1_100_000)
            for value in [pose.gazeX, pose.gazeY, pose.floatX, pose.floatY, pose.roll, pose.leftOpen, pose.rightOpen, pose.anger, pose.happiness] { XCTAssertTrue(value.isFinite) }
        }
    }
}
