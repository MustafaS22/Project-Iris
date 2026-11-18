import XCTest
@testable import IrisCore
final class WelcomeJourneyTests: XCTestCase {
    func testInterviewOnlyAcceptsNonemptyAnswersAndAdvancesOneQuestion() {
        var p = WelcomeProgress(); p.recordAnswer("  "); XCTAssertEqual(p.questionIndex, 0)
        for i in 0..<4 { p.recordAnswer("answer \(i)") }
        XCTAssertEqual(p.stage, .notch); XCTAssertEqual(p.answers.count, 4); XCTAssertFalse(p.canAdvance)
        p.recordAnswer("stray"); XCTAssertEqual(p.answers.count, 4)
    }
    func testPracticeRequiresActualEvidenceAndSkipDoesNotCountAsDone() {
        var p = WelcomeProgress(stage: .notch)
        p.advance(); XCTAssertEqual(p.stage, .notch)
        p.noteReply(); XCTAssertFalse(p.canAdvance)
        p.notchOpened = true; p.noteReply(); XCTAssertTrue(p.canAdvance)
        p.advance(); XCTAssertEqual(p.stage, .floating)
        p.floatingOpened = true; p.noteReply(); XCTAssertFalse(p.canAdvance)
        p.floatingDragged = true; p.noteReply(); XCTAssertTrue(p.canAdvance)
        p.advance(); XCTAssertEqual(p.stage, .drafting); p.noteReply(); XCTAssertFalse(p.canAdvance)
        p.advance(skipping: true); XCTAssertEqual(p.stage, .explore)
        XCTAssertTrue(p.skipped.contains("drafting")); XCTAssertFalse(p.completed.contains("drafting"))
    }
    func testSkippableInterviewAndBoundedPersistedState() throws {
        var p = WelcomeProgress(); p.recordAnswer(String(repeating: "a", count: 1000))
        XCTAssertEqual(p.answers["name"]?.count, 480)
        for _ in 0..<3 { p.advance(skipping: true) }
        XCTAssertEqual(p.stage, .notch); XCTAssertEqual(p.savedDetails.count, 1)
        let copy = try JSONDecoder().decode(WelcomeProgress.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(copy, p)
        p.questionIndex = -8; p.answers["unexpected"] = "bad"; p.normalize()
        XCTAssertEqual(p.questionIndex, 0); XCTAssertNil(p.answers["unexpected"])
    }
}

extension WelcomeJourneyTests {
    func testLegacyProgressRemainsReadableAndPersonalizationDoesNotInventFacts() throws {
        let legacy = #"{"stage":"floating","questionIndex":3,"answers":{"project":"My robotics exam"},"completed":[],"skipped":[],"notchOpened":true,"floatingOpened":false,"floatingDragged":false}"#
        let p = try JSONDecoder().decode(WelcomeProgress.self, from: Data(legacy.utf8))
        XCTAssertNil(p.starterPlan); XCTAssertNil(p.demoTarget)
        XCTAssertTrue(p.starterPrompt.contains("My robotics exam")); XCTAssertTrue(p.starterPrompt.contains("don’t invent"))
        XCTAssertEqual(p.cue, "Bring me out onto your desktop.")
    }
    func testCoachPlacementStaysOnScreenAndAvoidsAvatarWhenThereIsRoom() {
        let bounds = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        for avatar in [CGRect(x: -1850, y: 900, width: 88, height: 72), CGRect(x: -120, y: 20, width: 88, height: 72), CGRect(x: -950, y: 500, width: 88, height: 72)] {
            let frame = WelcomeCoachPlacement.frame(near: avatar, size: CGSize(width: 322, height: 228), bounds: bounds)
            XCTAssertTrue(bounds.contains(frame)); XCTAssertFalse(frame.intersects(avatar))
        }
        let tiny = CGRect(x: 0, y: 0, width: 240, height: 160)
        XCTAssertTrue(tiny.contains(WelcomeCoachPlacement.frame(near: .zero, size: CGSize(width: 322, height: 228), bounds: tiny)))
    }
}

extension WelcomeJourneyTests {
    func testCoachAvoidsAnExpandedNotch() {
        let bounds = CGRect(x: 0, y: 0, width: 1280, height: 832)
        let notch = CGRect(x: 350, y: 132, width: 580, height: 700)
        let coach = WelcomeCoachPlacement.frame(near: notch, size: CGSize(width: 322, height: 332), bounds: bounds)
        XCTAssertTrue(bounds.contains(coach)); XCTAssertFalse(coach.intersects(notch))
    }
}
