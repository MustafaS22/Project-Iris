import XCTest
@testable import IrisCore
final class ScreenSolutionTests:XCTestCase {
    func testSolveThisCapturesScreenInsteadOfMakingANewDiagram() {
        for text in ["Solve this", "Solve the question on my screen", "Calculate the answer to this problem"] {XCTAssertTrue(ScreenQuestionPolicy.wantsSnapshot(text));XCTAssertFalse(ScreenQuestionPolicy.wantsNewDrawing(text))}
        XCTAssertFalse(ScreenQuestionPolicy.wantsSnapshot("Don't capture my screen; solve 2x=4"))
    }
    func testSolutionIsBoundedAndProjectsQuestionExactly()throws {
        let raw=#"{"solution":{"question":{"x":0.2,"y":0.1,"width":0.5,"height":0.2},"steps":[{"text":"2x = 4","speech":"Divide both sides by two."},{"text":"x = 2","speech":"So x equals two."}]}}"#
        let drawing=try ScreenDrawing.decode(raw)
        XCTAssertEqual(drawing.mode,"solution");XCTAssertEqual(drawing.presentationSteps.count,2)
        let projection=ScreenProjection(imageFrame:CGRect(x:100,y:100,width:800,height:600),displayFrame:CGRect(x:0,y:0,width:1200,height:900))
        let resolved=try projection.resolve(drawing,targets:[])
        XCTAssertEqual(resolved.question!.x,(100+0.2*800)/1200,accuracy:0.001)
        let frame=ScreenSolution.frame(question:CGRect(x:100,y:100,width:450,height:100),canvas:CGSize(width:1280,height:800))
        XCTAssertEqual(frame.minY,212);XCTAssertLessThanOrEqual(frame.width,460)
        XCTAssertTrue(CGRect(x:16,y:16,width:1248,height:768).contains(frame))
        XCTAssertEqual(ScreenSolution.frame(question:CGRect(x:0,y:0,width:1280,height:800),canvas:CGSize(width:1280,height:800)),.zero)
        XCTAssertThrowsError(try ScreenDrawing.decode(raw.replacingOccurrences(of:"\"width\":0.5",with:"\"width\":2")))
    }
    func testRealisticResponseVariantsDoNotNeedAnotherModelCall()throws {
        let bounds=#""question":{"x":"0.2","y":"0.1","w":"0.5","h":"0.2"}"#
        for steps in [#"["2x = 4", "x = 2"]"#,#"[{"text":"2x = 4"},{"content":"x = 2","narration":"X equals two."}]"#,#"[{"equation":"2x = 4","explanation":"Divide by two."},{"text":"x=2","speech":null}]"#] {
            let direct="{"+bounds+",\"steps\":"+steps+"}"
            let drawing=try ScreenDrawing.decode(direct)
            XCTAssertEqual(drawing.marks.count,2);XCTAssertTrue(drawing.marks.allSatisfy{!($0.speech ?? "").isEmpty})
            let fenced="```json\n"+direct+"\n```"
            XCTAssertEqual(try ScreenDrawing.decode(fenced).question,drawing.question)
        }
    }
    func testObjectActionContentPreservesMathWithoutDoubleEncoding()throws {
        let content:[String:Any]=["solution":["question":["x":0.2,"y":0.1,"width":0.4,"height":0.2],"steps":[["text":#"$\frac{1}{2}$"#,"speech":"One half."]]]]
        let data=try JSONSerialization.data(withJSONObject:["actions":[["type":"drawOnScreen","content":content]]])
        let plan=try XCTUnwrap(ActionPolicy.parse("```iris-actions\n"+String(decoding:data,as:UTF8.self)+"\n```"))
        XCTAssertEqual(try ScreenDrawing.decode(plan[0].content!).marks[0].text,#"$\frac{1}{2}$"#)
        let bad=try JSONSerialization.data(withJSONObject:["actions":[["type":"writeFile","content":content]]])
        XCTAssertNil(ActionPolicy.parse("```iris-actions\n"+String(decoding:bad,as:UTF8.self)+"\n```"))
    }
    func testMissingOrPixelCoordinatesFailClearlyWithoutGuessing() {
        for raw in [#"{"steps":["x=2"]}"#,#"{"question":{"x":200,"y":100,"width":400,"height":200},"steps":["x=2"]}"#] {
            XCTAssertThrowsError(try ScreenDrawing.decode(raw)){XCTAssertTrue($0.localizedDescription.contains("locate"));XCTAssertFalse($0.localizedDescription.contains("correct format"))}
        }
    }

}
