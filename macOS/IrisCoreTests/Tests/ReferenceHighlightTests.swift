import XCTest
@testable import IrisCore
final class ReferenceHighlightTests: XCTestCase {
    func testEveryBundledFigureHasBoundedNarratedRegions() throws {
        XCTAssertEqual(Set(ReferenceHighlight.regions.keys),DiagramReference.bundledIDs)
        for id in DiagramReference.preferredIDs {
            let d=try XCTUnwrap(DiagramLibrary.entry(id)).drawing
            XCTAssertFalse(d.marks.isEmpty,id)
            XCTAssertEqual(d.presentationSteps.count,ReferenceHighlight.regions[id]?.count,id)
            for step in d.presentationSteps { XCTAssertEqual(d.marks[step].filter{$0.speech != nil}.count,1,id) }
            for m in d.marks {XCTAssertEqual(m.kind,"focus");XCTAssertGreaterThan(m.width ?? 0,0);XCTAssertGreaterThan(m.height ?? 0,0);XCTAssertLessThanOrEqual(m.x+(m.width ?? 0),1);XCTAssertLessThanOrEqual(m.y+(m.height ?? 0),1)}
            _=try ScreenDrawing.decode(String(decoding:JSONEncoder().encode(d),as:UTF8.self))
        }
    }
    func testSimpleTopicsUseNativeDrawings() throws {
        for id in ["water-molecule","wave","photosynthesis","client-server","binary-tree","neural-network","electric-circuit","ionic-bond","heat-transfer"] {
            let d=try XCTUnwrap(DiagramLibrary.entry(id)).drawing
            XCTAssertNil(d.figure,id);XCTAssertFalse(d.marks.isEmpty,id)
        }
        XCTAssertEqual(DiagramLibrary.match("Draw an electric circuit")?.id,"electric-circuit")
        XCTAssertFalse(DiagramReference.wantsOnline("Draw an electric circuit"))
        XCTAssertFalse(DiagramReference.wantsOnline("Draw your own neuron without images"))
    }
    func testOnlyCurrentHighlightSurvivesIncludingMissingStepIDs() {
        let d=ScreenDrawing(marks:[.init(kind:"focus",x:0.1,y:0.1,width:0.1,height:0.1),.init(kind:"focus",x:0.4,y:0.4,width:0.1,height:0.1)])
        XCTAssertEqual(ReferenceHighlight.opacity(index:0,drawing:d,visible:2,revealFrom:1,elapsed:1),0)
        XCTAssertEqual(ReferenceHighlight.opacity(index:1,drawing:d,visible:2,revealFrom:1,elapsed:1),1)
    }
    func testImageCoordinatesSurviveLetterboxingAndRetinaScaling() {
        let m=ScreenDrawing.Mark(kind:"focus",x:0.25,y:0.5,width:0.5,height:0.25)
        for image in [CGSize(width:400,height:1200),CGSize(width:1600,height:400)] {
            let size=CGSize(width:1280,height:900), fitted=ReferenceHighlight.fitted(image:image,canvas:size), r=ReferenceHighlight.rect(m,image:image,canvas:size)
            XCTAssertEqual(r.midX,fitted.midX,accuracy:0.001)
            XCTAssertEqual(r.minY,fitted.midY,accuracy:0.001)
            let doubled=ReferenceHighlight.rect(m,image:CGSize(width:image.width*2,height:image.height*2),canvas:CGSize(width:2560,height:1800))
            XCTAssertEqual(doubled.minX,r.minX*2,accuracy:0.001);XCTAssertEqual(doubled.height,r.height*2,accuracy:0.001)
        }
    }
    func testFocusCannotOverflowImage() {
        XCTAssertThrowsError(try ScreenDrawing.decode("{\"figure\":\"neuron\",\"marks\":[{\"kind\":\"focus\",\"x\":0.9,\"y\":0.2,\"width\":0.4,\"height\":0.2}]}"))
    }
}
