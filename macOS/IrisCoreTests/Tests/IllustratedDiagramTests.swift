import XCTest
@testable import IrisCore
final class IllustratedDiagramTests: XCTestCase {
    func testConcreteConceptsBecomeObjectsInsteadOfBoxes() throws {
        let raw = #"{"nodes":[{"id":"a","text":"Sunlight"},{"id":"b","text":"Chloroplasts"},{"id":"c","text":"Plant"}],"edges":[{"from":"a","to":"b"},{"from":"b","to":"c"}]}"#
        let drawing = try ScreenDrawing.decode(raw)
        XCTAssertFalse(drawing.marks.contains { $0.kind == "node" })
        XCTAssertEqual(drawing.marks.compactMap(\.object), ["sun","chloroplast","plant"])
    }
    func testObjectsAndCurvesRoundTripWithNarration() throws {
        let raw = #"{"mode":"conceptual","narrate":true,"marks":[{"kind":"object","object":"plant","x":0.4,"y":0.3,"width":0.2,"height":0.3,"speech":"The leaf captures light.","text":"Plant"},{"kind":"path","x":0.2,"y":0.3,"width":0.2,"height":0.2,"color":"yellow","points":[{"x":0,"y":0},{"x":1,"y":1,"cx":0.2,"cy":0,"c2x":0.8,"c2y":1}]}]}"#
        let drawing=try ScreenDrawing.decode(raw)
        XCTAssertEqual(drawing.marks[1].points?.count,2)
        XCTAssertEqual(try ScreenDrawing.decode(String(decoding:JSONEncoder().encode(drawing),as:UTF8.self)),drawing)
    }
    func testMalformedArtRejected() throws {
        for raw in [
            #"{"marks":[{"kind":"object","object":"unknown","x":0,"y":0,"width":0.1,"height":0.1}]}"#,
            #"{"marks":[{"kind":"object","object":"plant","x":0.9,"y":0.9,"width":0.3,"height":0.3}]}"#,
            #"{"marks":[{"kind":"path","x":0,"y":0,"width":0.1,"height":0.1,"points":[{"x":0,"y":0}]}]}"#,
            #"{"marks":[{"kind":"path","x":0,"y":0,"width":0.1,"height":0.1,"points":[{"x":0,"y":0},{"x":1,"y":1,"cx":0.5}]}]}"#,
            #"{"marks":[{"kind":"path","x":0,"y":0,"width":0.1,"height":0.1,"points":[{"x":0,"y":0},{"x":2,"y":1}]}]}"#,
            #"{"nodes":[{"id":"a","text":"Thing","object":"unknown"}]}"#
        ] {XCTAssertThrowsError(try ScreenDrawing.decode(raw),raw)}
        XCTAssertNil(DiagramObject.infer("Sunday plans"))
        XCTAssertNil(DiagramObject.infer("Oxygen")) // do not imply an incorrect molecular structure
    }
}
