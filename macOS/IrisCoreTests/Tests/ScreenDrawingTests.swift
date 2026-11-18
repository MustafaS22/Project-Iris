import XCTest
@testable import IrisCore
final class ScreenDrawingTests: XCTestCase {
    func testLabelsShapesAndNegativeArrowDirections() throws {
        let raw = #"{"marks":[{"kind":"label","x":0.2,"y":0.3,"text":"Hello"},{"kind":"arrow","x":0.8,"y":0.8,"width":-0.4,"height":-0.2},{"kind":"circle","x":0.1,"y":0.2,"width":0.2,"height":0.3}]}"#
        XCTAssertEqual(try ScreenDrawing.decode(raw).marks.count, 3)
        XCTAssertTrue(try ScreenDrawing.decode(#"{"marks":[]}"#).marks.isEmpty)
    }
    func testMalformedOrUnboundedDrawingsAreRejected() throws {
        for raw in [#"{"marks":[{"kind":"shell","x":0,"y":0}]}"#, #"{"marks":[{"kind":"label","x":2,"y":0,"text":"No"}]}"#, #"{"marks":[{"kind":"arrow","x":0,"y":0}]}"#, #"{"marks":[{"kind":"label","x":0,"y":0,"text":""}]}"#] {
            XCTAssertThrowsError(try ScreenDrawing.decode(raw))
        }
        let mark = ScreenDrawing.Mark(kind: "label", x: 0, y: 0, text: "A")
        let many = try JSONEncoder().encode(ScreenDrawing(marks: Array(repeating: mark, count: 25)))
        XCTAssertThrowsError(try ScreenDrawing.decode(String(decoding: many, as: UTF8.self)))
    }
    func testResizingAndRoamingStayOnNegativeOriginDisplays() {
        let bounds = CGRect(x: -1440, y: 20, width: 1440, height: 900)
        XCTAssertEqual(FloatingGeometry.clamped(CGPoint(x: 100, y: -30), size: CGSize(width: 360, height: 370), bounds: bounds), CGPoint(x: -360, y: 20))
        XCTAssertEqual(FloatingGeometry.clamped(CGPoint(x: -2000, y: 1200), size: CGSize(width: 156, height: 174), bounds: bounds), CGPoint(x: -1440, y: 746))
    }
    func testDrawingsUseTheHiddenActionProtocolAndNeedNoFilePermission() {
        let action = AssistantAction(type: "drawOnScreen", content: #"{"marks":[]}"#)
        XCTAssertTrue(ActionPolicy.mayRunAutomatically(action, enabled: false))
        XCTAssertEqual(ActionPolicy.parse("```iris-actions\n{\"actions\":[{\"type\":\"drawOnScreen\",\"content\":\"{\\\"marks\\\":[]}\"}]}\n```")?.first?.type, "drawOnScreen")
        XCTAssertFalse(ActionPolicy.mayRunAutomatically(AssistantAction(type: "generateImage"), enabled: true))
    }
}
