import XCTest
@testable import IrisCore
final class ConceptDiagramTests: XCTestCase {
    func testNewIllustrationDoesNotRequireScreenEvenWithDiagramWord() {
        for prompt in ["Draw a diagram of photosynthesis", "Explain gravity using a diagram", "Make a flowchart", "Sketch a cell", "Illustrate the water cycle", "Draw your own diagram without looking at my screen"] {
            XCTAssertTrue(ScreenQuestionPolicy.wantsNewDrawing(prompt), prompt)
            XCTAssertFalse(ScreenQuestionPolicy.wantsSnapshot(prompt), prompt)
        }
        for prompt in ["Label this diagram", "Explain this diagram on my screen", "Circle the button here", "Draw a circle around the button"] {
            XCTAssertFalse(ScreenQuestionPolicy.wantsNewDrawing(prompt), prompt)
            XCTAssertTrue(ScreenQuestionPolicy.wantsSnapshot(prompt), prompt)
        }
    }
    func testSemanticDiagramCompilesIntoNarratedNodesAndEdgeOutsideNodes() throws {
        let raw = #"{"mode":"conceptual","title":"Energy flow","nodes":[{"id":"a","text":"Sun","speech":"Sunlight supplies energy."},{"id":"b","text":"Plant","speech":"Plants use that energy."}],"edges":[{"from":"a","to":"b"}]}"#
        let drawing = try ScreenDrawing.decode(raw)
        XCTAssertEqual(drawing.mode, "conceptual"); XCTAssertEqual(drawing.narrate, true)
        XCTAssertEqual(drawing.marks.map(\.kind), ["object", "arrow", "object"])
        XCTAssertEqual(drawing.marks[0].speech, "Sunlight supplies energy.")
        let a = drawing.marks[0], edge = drawing.marks[1], b = drawing.marks[2]
        XCTAssertEqual(edge.x, a.x + a.width!, accuracy: 0.001)
        XCTAssertEqual(edge.x + edge.width!, b.x, accuracy: 0.001)
        XCTAssertNil(edge.speech)
        XCTAssertEqual(try ScreenDrawing.decode(String(decoding: JSONEncoder().encode(drawing), as: UTF8.self)), drawing)
    }
    func testBranchAndCycleLayoutsStayBoundedAndNonOverlapping() throws {
        for edges in [#"[{"from":"a","to":"b"},{"from":"a","to":"c"}]"#, #"[{"from":"a","to":"b"},{"from":"b","to":"c"},{"from":"c","to":"a"}]"#] {
            let raw = #"{"nodes":[{"id":"a","text":"A"},{"id":"b","text":"B"},{"id":"c","text":"C"}],"edges":\#(edges)}"#
            let nodes = try ScreenDrawing.decode(raw).marks.filter { $0.kind == "node" }
            let rects = nodes.map { CGRect(x:$0.x,y:$0.y,width:$0.width!,height:$0.height!) }
            for (i, rect) in rects.enumerated() {
                XCTAssertTrue(CGRect(x:0.1,y:0.25,width:0.8,height:0.6).contains(rect))
                for other in rects.dropFirst(i + 1) { XCTAssertFalse(rect.intersects(other)) }
            }
        }
    }
    func testInvalidGraphsRejectedAndExistingAnnotationsPreserved() throws {
        for raw in [#"{"nodes":[]}"#, #"{"nodes":[{"id":"a","text":"A"},{"id":"a","text":"B"}]}"#, #"{"nodes":[{"id":"a","text":"A"}],"edges":[{"from":"a","to":"missing"}]}"#, #"{"mode":"unknown","marks":[]}"#, #"{"mode":"conceptual","marks":[{"kind":"node","x":0.3,"y":0.4,"width":-0.1,"height":0.1,"text":"Bad"}]}"#] { XCTAssertThrowsError(try ScreenDrawing.decode(raw)) }
        let annotation = try ScreenDrawing.decode(#"{"narrate":true,"marks":[{"kind":"callout","x":0.4,"y":0.4,"text":"Valve","speech":"This valve controls flow."}]}"#)
        XCTAssertNil(annotation.mode); XCTAssertEqual(annotation.marks.first?.kind, "callout")
    }
}
