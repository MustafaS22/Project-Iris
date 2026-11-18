import XCTest
@testable import IrisCore
final class DiagramPresentationTests:XCTestCase {
    func testAvatarNeverIntersectsStageAcrossTravelAndDragging() {
        for screen in [CGRect(x:0,y:0,width:1280,height:800),CGRect(x:-1920,y:40,width:1920,height:1080),CGRect(x:0,y:0,width:800,height:600)] {
            let stage=DiagramPresentation.stageSize(screen.size),lane=DiagramPresentation.lane(screen:screen,visible:screen.insetBy(dx:0,dy:25)),size=CGSize(width:148,height:108)
            let diagram=CGRect(origin:screen.origin,size:stage)
            let a=DiagramPresentation.companion(target:CGPoint(x:screen.midX,y:screen.minY),avatar:size,lane:lane)
            let b=DiagramPresentation.companion(target:CGPoint(x:screen.midX,y:screen.maxY),avatar:size,lane:lane)
            let flight=FloatingFlight(start:a,end:b,started:0,duration:1)
            for i in 0...100 { let frame=CGRect(origin:flight.position(at:Double(i)/100),size:size);XCTAssertFalse(frame.intersects(diagram));XCTAssertTrue(lane.contains(frame)) }
            let dragged=FloatingGeometry.clamped(CGPoint(x:screen.midX,y:screen.midY),size:size,bounds:lane)
            XCTAssertFalse(CGRect(origin:dragged,size:size).intersects(diagram))
        }
    }
    func testCameraUsesBoundedUniformZoomAndStartsAtOverview() {
        let drawing=DiagramLibrary.entry("neuron")!.drawing,image=CGSize(width:1600,height:1200),canvas=CGSize(width:1080,height:800)
        let base=ReferenceHighlight.fitted(image:image,canvas:canvas)
        XCTAssertEqual(DiagramPresentation.imageFrame(image:image,canvas:canvas,drawing:drawing,visible:1,revealFrom:0,elapsed:0),base)
        let close=DiagramPresentation.imageFrame(image:image,canvas:canvas,drawing:drawing,visible:1,revealFrom:0,elapsed:1)
        XCTAssertGreaterThan(close.width,base.width);XCTAssertLessThanOrEqual(close.width/base.width,2.3)
        XCTAssertEqual(close.width/close.height,image.width/image.height,accuracy:0.001)
        XCTAssertTrue(close.insetBy(dx:-0.001,dy:-0.001).contains(base))
        let region=DiagramPresentation.focusRect(drawing.marks[0],imageFrame:close)
        XCTAssertTrue(region.intersects(base))
    }
    func testCompletionReturnsToFullFigureFromLastCloseup() {
        let drawing=DiagramLibrary.entry("neuron")!.drawing,image=CGSize(width:1600,height:1200),canvas=CGSize(width:1080,height:800),count=drawing.marks.count
        let close=DiagramPresentation.imageFrame(image:image,canvas:canvas,drawing:drawing,visible:count,revealFrom:drawing.presentationSteps.last!.lowerBound,elapsed:2)
        let start=DiagramPresentation.imageFrame(image:image,canvas:canvas,drawing:drawing,visible:count,revealFrom:count,elapsed:0,complete:true)
        let end=DiagramPresentation.imageFrame(image:image,canvas:canvas,drawing:drawing,visible:count,revealFrom:count,elapsed:1,complete:true)
        XCTAssertEqual(start,close)
        XCTAssertEqual(end,ReferenceHighlight.fitted(image:image,canvas:canvas))
        XCTAssertEqual(drawing.marks.count,count) // Completion preserves the actual diagram.
    }

}
