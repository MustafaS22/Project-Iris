import XCTest
@testable import IrisCore
final class ScreenProjectionTests: XCTestCase {
    func testWindowOffsetsAndNormalizedRetinaPixelsMapExactly() {
        let p = ScreenProjection(imageFrame: .init(x: 200, y: 100, width: 800, height: 600), displayFrame: .init(x: 0, y: 0, width: 1440, height: 900))
        // (800,600) pixels in a 1600×1200 Retina capture is its normalized centre.
        let point = p.displayPoint(.init(x: 800.0/1600, y: 600.0/1200))
        XCTAssertEqual(point.x * 1440, 600, accuracy: 0.001)
        XCTAssertEqual(point.y * 900, 400, accuracy: 0.001)
    }
    func testNegativeOriginDisplayAndRoundTripBounds() {
        let p = ScreenProjection(imageFrame: .init(x: -1240, y: -100, width: 800, height: 600), displayFrame: .init(x: -1440, y: -200, width: 1440, height: 900))
        let rect = CGRect(x: 0.25, y: 0.3, width: 0.15, height: 0.1)
        let actual = p.imageRect(p.displayRect(rect))
        XCTAssertEqual(actual.minX, rect.minX, accuracy: 0.0001); XCTAssertEqual(actual.minY, rect.minY, accuracy: 0.0001)
        XCTAssertEqual(actual.width, rect.width, accuracy: 0.0001)
    }
    func testDetectedTargetOverridesWrongModelCoordinates() throws {
        let p = ScreenProjection(imageFrame: .init(x: 200, y: 100, width: 800, height: 600), displayFrame: .init(x: 0, y: 0, width: 1440, height: 900))
        let target = GuidanceTarget(id: "verified", label: "Save", role: "Button", rect: .init(x: 0.7, y: 0.6, width: 0.1, height: 0.04))
        let raw = ScreenDrawing(marks: [.init(kind: "callout", x: 0.1, y: 0.2, text: "Save", targetID: "verified"), .init(kind: "circle", x: 0, y: 0, width: 0.9, height: 0.9, targetID: "verified")])
        let result = try p.resolve(raw, targets: [target])
        XCTAssertEqual(result.marks[0].x, target.rect.midX)
        XCTAssertEqual(result.marks[1].width, target.rect.width)
        XCTAssertEqual(result.marks[1].y, target.rect.minY)
        XCTAssertThrowsError(try p.resolve(raw, targets: []))
    }
    func testEdgeAnchorsStayOnTheirRealPixelRatherThanLabelInset() {
        let result = AnnotationLayout.make(.init(marks: [.init(kind: "callout", x: 0, y: 1, text: "Edge")]), size: .init(width: 1000, height: 700)) { _ in .init(width: 100, height: 20) }
        XCTAssertEqual(result.callouts[0].target, CGPoint(x: 0, y: 700))
        XCTAssertTrue(CGRect(x: 0, y: 0, width: 1000, height: 700).contains(result.callouts[0].rect))
    }
    func testExactControlCanBeCircledWithoutInventedCoordinates() throws {
        let drawing = try ScreenDrawing.decode(#"{"marks":[{"kind":"circle","targetID":"verified"}]}"#)
        let target = GuidanceTarget(id: "verified", label: "Save", role: "Button", rect: .init(x: 0.3, y: 0.4, width: 0.1, height: 0.04))
        let projection = ScreenProjection(imageFrame: .init(x: 0, y: 0, width: 100, height: 100), displayFrame: .init(x: 0, y: 0, width: 100, height: 100))
        let result = try projection.resolve(drawing, targets: [target])
        XCTAssertEqual(result.marks[0].x, 0.3); XCTAssertEqual(result.marks[0].width, 0.1)
    }
    func testNarrationSchemaRemainsBoundedAndBackwardsCompatible() throws {
        let guided = try ScreenDrawing.decode(#"{"narrate":true,"marks":[{"kind":"callout","x":0.5,"y":0.4,"text":"Valve","speech":"This valve separates the chambers.","targetID":"known"}]}"#)
        XCTAssertEqual(guided.narrate, true); XCTAssertEqual(guided.marks.first?.targetID, "known")
        XCTAssertNil(try ScreenDrawing.decode(#"{"marks":[]}"#).narrate)
        var invalid = guided; invalid.marks[0].speech = String(repeating: "x", count: 401)
        XCTAssertThrowsError(try ScreenDrawing.decode(String(decoding: JSONEncoder().encode(invalid), as: UTF8.self)))
    }
}
