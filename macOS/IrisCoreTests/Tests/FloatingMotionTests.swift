import XCTest
@testable import IrisCore
import CoreGraphics
final class FloatingMotionTests: XCTestCase {
    func testTravelGazeFollowsAllDirectionsWithCorrectVerticalAxis() throws {
        for (end, horizontal, vertical) in [(CGPoint(x:100,y:0), 1.0, 0.0), (CGPoint(x:-100,y:0), -1.0, 0.0), (CGPoint(x:0,y:100), 0.0, -1.0), (CGPoint(x:0,y:-100), 0.0, 1.0)] {
            let flight = FloatingFlight(start: .zero, end: end, started: 0, duration: 4)
            let gaze = try XCTUnwrap(flight.travelGaze(at: 2))
            XCTAssertEqual(gaze.width, horizontal * 180, accuracy: 0.001)
            XCTAssertEqual(gaze.height, vertical * 180, accuracy: 0.001)
        }
    }
    func testTravelGazeEasesAtDepartureAndArrivalAndStopsWhenIdle() throws {
        let flight = FloatingFlight(start: .zero, end: CGPoint(x:100,y:100), started: 10, duration: 4)
        XCTAssertNil(flight.travelGaze(at: 9))
        XCTAssertNil(flight.travelGaze(at: 10))
        XCTAssertNil(flight.travelGaze(at: 14))
        let departing = try XCTUnwrap(flight.travelGaze(at: 10.01))
        let cruising = try XCTUnwrap(flight.travelGaze(at: 12))
        let arriving = try XCTUnwrap(flight.travelGaze(at: 13.99))
        XCTAssertLessThan(hypot(departing.width, departing.height), 1)
        XCTAssertEqual(hypot(cruising.width, cruising.height), 180, accuracy: 0.001)
        XCTAssertLessThan(hypot(arriving.width, arriving.height), 1)
        XCTAssertNil(FloatingFlight(start: .zero, end: .zero, started: 0, duration: 4).travelGaze(at: 2))
    }
    func testDragGazeUsesRecentMovementAndReversesWithTheDrag() throws {
        var motion = FloatingDragGaze()
        motion.record(from: .zero, to: CGPoint(x:20,y:10), at: 10)
        let rightUp = try XCTUnwrap(motion.gaze(at: 10.05))
        XCTAssertGreaterThan(rightUp.width, 0); XCTAssertLessThan(rightUp.height, 0)
        motion.record(from: CGPoint(x:20,y:10), to: CGPoint(x:10,y:-10), at: 10.1)
        let leftDown = try XCTUnwrap(motion.gaze(at: 10.15))
        XCTAssertLessThan(leftDown.width, 0); XCTAssertGreaterThan(leftDown.height, 0)
        XCTAssertEqual(hypot(leftDown.width, leftDown.height), 180, accuracy: 0.001)
    }
    func testDragGazeDecaysWhenPausedAndIgnoresJitterOrClampedMovement() throws {
        var motion = FloatingDragGaze()
        XCTAssertNil(motion.gaze(at: 1))
        motion.record(from: .zero, to: CGPoint(x:10,y:0), at: 1)
        motion.record(from: .zero, to: CGPoint(x:0.1,y:0), at: 1.2)
        motion.record(from: .zero, to: .zero, at: 1.3)
        XCTAssertGreaterThan(try XCTUnwrap(motion.gaze(at: 1.2)).width, 0)
        XCTAssertLessThan(try XCTUnwrap(motion.gaze(at: 1.2)).width, 180)
        XCTAssertNil(motion.gaze(at: 1.33))
        XCTAssertNil(motion.gaze(at: 0.9))
    }
    func testDragUsesPointerDeltaNotMovingViewTranslation() {
        let bounds = CGRect(x: -1440, y: 20, width: 1440, height: 900)
        let start = CGPoint(x: -800, y: 300), pointer = CGPoint(x: -740, y: 350)
        let result = FloatingPlacement.dragged(origin: start, startPointer: pointer, pointer: CGPoint(x: -640, y: 390), size: CGSize(width: 148, height: 108), bounds: bounds)
        XCTAssertEqual(result, CGPoint(x: -700, y: 340))
        // Repeated events at the same screen position must never accumulate motion.
        XCTAssertEqual(FloatingPlacement.dragged(origin: start, startPointer: pointer, pointer: CGPoint(x: -640, y: 390), size: CGSize(width:148,height:108),bounds:bounds), result)
    }
    func testFlightHasNoOvershootAndCanBeInterruptedAtCurrentPosition() {
        let flight = FloatingFlight(start:.init(x:10,y:20),end:.init(x:210,y:420),started:100,duration:2)
        XCTAssertEqual(flight.position(at:99),flight.start); XCTAssertEqual(flight.position(at:103),flight.end)
        XCTAssertEqual(flight.position(at:101),CGPoint(x:110,y:220))
        XCTAssertFalse(flight.finished(at:101)); XCTAssertTrue(flight.finished(at:102))
        var previous = flight.start.x
        for step in 0...120 { let p = flight.position(at:100 + Double(step)/60); XCTAssertGreaterThanOrEqual(p.x,previous); previous = p.x }
    }
    func testGuideCoordinatesMatchFullScreenIncludingNegativeOrigins() {
        let frame = FloatingPlacement.appKitRect(normalized:.init(x:0.1,y:0.2,width:0.3,height:0.1),screen:.init(x:-1440,y:100,width:1440,height:900))
        XCTAssertEqual(frame.minX,-1296,accuracy:0.001); XCTAssertEqual(frame.minY,730,accuracy:0.001)
        XCTAssertEqual(frame.width,432,accuracy:0.001)
    }
    func testGuidanceRejectsStaleOrChangedAppOrWindow() {
        let frame = CGRect(x:30,y:40,width:800,height:600)
        XCTAssertTrue(GuidancePolicy.fresh(captured:100,now:110,targetPID:1,foregroundPID:1,originalWindow:frame,currentWindow:frame))
        XCTAssertFalse(GuidancePolicy.fresh(captured:100,now:221,targetPID:1,foregroundPID:1,originalWindow:frame,currentWindow:frame))
        XCTAssertFalse(GuidancePolicy.fresh(captured:100,now:110,targetPID:1,foregroundPID:2,originalWindow:frame,currentWindow:frame))
        XCTAssertFalse(GuidancePolicy.fresh(captured:100,now:110,targetPID:1,foregroundPID:1,originalWindow:frame,currentWindow:frame.offsetBy(dx:10,dy:0)))
        XCTAssertFalse(GuidancePolicy.fresh(captured:100,now:110,targetPID:1,foregroundPID:1,originalWindow:frame,currentWindow:nil))
    }
    func testTargetNormalizationAndAnnotationStayBounded() throws {
        let rect = GuidancePolicy.normalized(.init(x:-20,y:50,width:80,height:20),in:.init(x:0,y:0,width:100,height:100))!
        XCTAssertEqual(rect,CGRect(x:0,y:0.5,width:0.6,height:0.2))
        let target = GuidanceTarget(id:"snapshot-A1",label:"Save",role:"Button",rect:rect)
        let encoded = try JSONEncoder().encode(GuidancePolicy.drawing(for:target))
        XCTAssertEqual(try ScreenDrawing.decode(String(decoding:encoded,as:UTF8.self)).marks.count,2)
    }
    func testGuidanceApproachAvoidsTargetAndCompanionsStayInsideDisplay() {
        let bounds = CGRect(x:-1440,y:20,width:1440,height:900), size = CGSize(width:148,height:108)
        let target = CGRect(x:-200,y:100,width:180,height:50)
        let origin = FloatingPlacement.near(target,size:size,bounds:bounds)
        XCTAssertFalse(CGRect(origin:origin,size:size).intersects(target))
        let companion = FloatingPlacement.companion(avatar:.init(x:-160,y:20,width:148,height:108),size:.init(width:370,height:320),bounds:bounds)
        XCTAssertTrue(bounds.contains(companion))
    }
    func testTypingPanelCanUseTheSideInsteadOfCoveringTheAvatar() {
        let bounds = CGRect(x:0,y:20,width:1200,height:620), avatar = CGRect(x:520,y:270,width:148,height:108)
        let companion = FloatingPlacement.companion(avatar:avatar,size:CGSize(width:370,height:320),bounds:bounds)
        XCTAssertTrue(bounds.contains(companion)); XCTAssertFalse(avatar.intersects(companion))
    }
    func testGuidanceOnlyChangesOurOverlayNotComputerPermissionPolicy() {
        for kind in ["guideControl","focusControl"] { XCTAssertTrue(ActionPolicy.mayRunAutomatically(.init(type:kind,target:"snapshot-A1"),enabled:false)) }
        XCTAssertFalse(ActionPolicy.mayRunAutomatically(.init(type:"writeFile"),enabled:false))
    }
}
