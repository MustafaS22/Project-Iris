import XCTest
@testable import IrisCore
final class DiagramLibraryTests: XCTestCase {
    func testEveryPresetIsBoundedAndDecodesWithGroupedNarration() throws {
        XCTAssertEqual(DiagramLibrary.entries.count,21)
        XCTAssertEqual(Set(DiagramLibrary.entries.map(\.id)).count,21)
        for entry in DiagramLibrary.entries {
            let drawing=try ScreenDrawing.decode("{\"preset\":\""+entry.id+"\"}")
            XCTAssertFalse(drawing.marks.isEmpty,entry.id)
            XCTAssertLessThanOrEqual(drawing.marks.count,64,entry.id)
            XCTAssertLessThanOrEqual(drawing.presentationSteps.count,8,entry.id)
            XCTAssertEqual(drawing.presentationSteps.flatMap(Array.init),Array(drawing.marks.indices),entry.id)
            XCTAssertEqual(drawing.presentationSteps.count,drawing.marks.filter{$0.speech != nil}.count,entry.id)
            XCTAssertEqual(try ScreenDrawing.decode(String(decoding:JSONEncoder().encode(drawing),as:UTF8.self)),drawing,entry.id)
        }
        XCTAssertFalse(try ScreenDrawing.decode(#"{"preset":"photosynthesis","narrate":false}"#).narrate ?? true)
        XCTAssertThrowsError(try ScreenDrawing.decode(#"{"preset":"unknown"}"#))
    }
    func testIntentMatchingKeepsScreenAnnotationsAndCustomRequestsOut() {
        for (prompt,id) in [("Draw photosynthesis","photosynthesis"),("Explain blood circulation","circulation"),("Draw a water molecule","water-molecule"),("Draw a binary search tree","binary-tree"),("Explain heat transfer with a diagram","heat-transfer")] {XCTAssertEqual(DiagramLibrary.match(prompt)?.id,id,prompt)}
        for prompt in ["Label this DNA diagram","Draw a custom cell structure","Explain this atom on my screen","Compare conduction versus convection","Draw atomic clocks","What is the weather?", "Explain DNA replication", "Draw photosynthesis and the water cycle"] {XCTAssertNil(DiagramLibrary.match(prompt),prompt)}
    }
    func testGroupingIsContiguousAndLegacyMarksStayIndependent() throws {
        let drawing=ScreenDrawing(marks:[.init(kind:"circle",x:0,y:0,width:0.1,height:0.1,step:0),.init(kind:"circle",x:0.2,y:0,width:0.1,height:0.1,step:0),.init(kind:"circle",x:0.4,y:0,width:0.1,height:0.1,step:1)])
        XCTAssertEqual(drawing.presentationSteps,[0..<2,2..<3])
        XCTAssertEqual(ScreenDrawing(marks:[.init(kind:"label",x:0,y:0,text:"A"),.init(kind:"label",x:0.2,y:0,text:"B")]).presentationSteps,[0..<1,1..<2])
        XCTAssertThrowsError(try ScreenDrawing.decode(#"{"marks":[{"kind":"label","x":0,"y":0,"text":"A","step":99}]}"#))
    }
}
