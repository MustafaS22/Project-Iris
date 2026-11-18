import XCTest
@testable import IrisCore
final class AnnotationLayoutTests: XCTestCase {
    let size = CGSize(width: 1280, height: 832)
    func layout(_ marks: [ScreenDrawing.Mark], size: CGSize? = nil) -> AnnotationLayout.Result {
        AnnotationLayout.make(.init(marks: marks), size: size ?? self.size) { _ in .init(width: 170, height: 32) }
    }
    func testCalloutsAreAcceptedAndLegacyArrowTailMovesOffText() throws {
        XCTAssertEqual(try ScreenDrawing.decode(#"{"marks":[{"kind":"callout","x":0.5,"y":0.4,"text":"Part"}]}"#).marks.count, 1)
        let result = layout([.init(kind: "label", x: 0.2, y: 0.4, text: "Label"), .init(kind: "arrow", x: 0.21, y: 0.42, width: 0.3, height: -0.1)])
        XCTAssertEqual(result.callouts.count, 1); XCTAssertTrue(result.shapes.isEmpty)
        let item = try XCTUnwrap(result.callouts.first)
        XCTAssertFalse(item.rect.contains(try XCTUnwrap(item.leader.first)))
        XCTAssertEqual(try XCTUnwrap(item.target).x, 0.51 * size.width, accuracy: 0.001)
    }
    func testCrowdedAnchorsProduceSeparateLabelsWithinScreen() {
        let marks = (0..<12).map { i in ScreenDrawing.Mark(kind: "callout", x: i % 2 == 0 ? 0.43 : 0.57, y: 0.42 + Double(i) * 0.005, text: "Part \(i)") }
        let result = layout(marks)
        XCTAssertEqual(result.callouts.count, 12)
        for (i, a) in result.callouts.enumerated() {
            XCTAssertTrue(CGRect(origin: .zero, size: size).contains(a.rect))
            for b in result.callouts.dropFirst(i + 1) { XCTAssertFalse(a.rect.intersects(b.rect), "Label collisions") }
            XCTAssertEqual(a.target, a.leader.last)
        }
    }
    func testDenseSmallDisplayAndLongNamesRemainBounded() {
        let small = CGSize(width: 900, height: 600)
        let marks = (0..<24).map { i in ScreenDrawing.Mark(kind: "callout", x: i % 2 == 0 ? 0.4 : 0.6, y: 0.5, text: String(repeating: "Long name ", count: 8)) }
        let result = layout(marks, size: small)
        for (i, a) in result.callouts.enumerated() {
            XCTAssertTrue(CGRect(origin: .zero, size: small).contains(a.rect))
            for b in result.callouts.dropFirst(i + 1) { XCTAssertFalse(a.rect.intersects(b.rect)) }
        }
    }
    func testLeaderOrderFollowsTargetOrderAndShapeMarksSurvive() {
        let result = layout([.init(kind: "callout", x: 0.4, y: 0.7, text: "Lower"), .init(kind: "callout", x: 0.4, y: 0.3, text: "Upper"), .init(kind: "circle", x: 0.7, y: 0.2, width: 0.1, height: 0.2)])
        XCTAssertEqual(result.shapes.count, 1)
        XCTAssertGreaterThan(result.callouts[0].rect.minY, result.callouts[1].rect.minY)
    }
    func testPlaybackIsFiniteMonotonicAndStaggered() {
        XCTAssertEqual(AnnotationPlayback.progress(elapsed: -1, index: 0), 0)
        XCTAssertEqual(AnnotationPlayback.progress(elapsed: 100, index: 23), 1)
        XCTAssertGreaterThan(AnnotationPlayback.progress(elapsed: 0.3, index: 0), AnnotationPlayback.progress(elapsed: 0.3, index: 1))
        var previous = 0.0
        for i in 0...100 { let p = AnnotationPlayback.progress(elapsed: Double(i) / 60, index: 0); XCTAssertGreaterThanOrEqual(p, previous); previous = p }
        XCTAssertLessThan(AnnotationPlayback.duration(count: 24), 3.1)
    }
}
