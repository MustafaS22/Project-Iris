import Foundation
import CoreGraphics

/// A dedicated companion lane keeps every avatar frame outside the diagram,
/// including during travel and user dragging. Coordinates here are AppKit points.
enum DiagramPresentation {
    static func stageSize(_ screen: CGSize) -> CGSize { CGSize(width:max(1,screen.width-200),height:screen.height) }
    static func lane(screen: CGRect, visible: CGRect) -> CGRect {
        CGRect(x:screen.maxX-188,y:visible.minY+12,width:176,height:max(0,visible.height-24))
    }
    static func companion(target: CGPoint, avatar: CGSize, lane: CGRect) -> CGPoint {
        FloatingGeometry.clamped(CGPoint(x:lane.midX-avatar.width/2,y:target.y-avatar.height/2),size:avatar,bounds:lane)
    }
    static func imageFrame(image: CGSize, canvas: CGSize, drawing: ScreenDrawing, visible: Int?, revealFrom: Int, elapsed: Double, complete: Bool = false) -> CGRect {
        let base=ReferenceHighlight.fitted(image:image,canvas:canvas)
        guard let visible,visible>0,visible<=drawing.marks.count else {return base}
        func frame(_ range: Range<Int>?) -> CGRect {
            guard let range else {return base}
            let boxes=drawing.marks[range].filter{$0.kind == "focus" && ($0.width ?? 0)>0 && ($0.height ?? 0)>0}.map {CGRect(x:$0.x,y:$0.y,width:$0.width ?? 0,height:$0.height ?? 0)}
            guard let region=boxes.reduce(nil as CGRect?,{ $0?.union($1) ?? $1 }) else {return base}
            // Small parts get a readable close-up; large overviews stay unchanged.
            let zoom=min(2.3,max(1,0.65/max(region.width,region.height)))
            let width=base.width*zoom,height=base.height*zoom
            let x=min(base.minX,max(base.maxX-width,base.midX-region.midX*width))
            let y=min(base.minY,max(base.maxY-height,base.midY-region.midY*height))
            return CGRect(x:x,y:y,width:width,height:height)
        }
        let target=complete ? base : frame(drawing.presentationSteps.first{$0.contains(visible-1)})
        let previous=frame(complete ? drawing.presentationSteps.first{$0.contains(visible-1)} : drawing.presentationSteps.last{$0.upperBound<=revealFrom})
        let t=min(1,max(0,elapsed/0.85)),e=t*t*t*(t*(t*6-15)+10)
        return CGRect(x:previous.minX+(target.minX-previous.minX)*e,y:previous.minY+(target.minY-previous.minY)*e,width:previous.width+(target.width-previous.width)*e,height:previous.height+(target.height-previous.height)*e)
    }
    static func focusRect(_ mark: ScreenDrawing.Mark, imageFrame: CGRect) -> CGRect {
        CGRect(x:imageFrame.minX+mark.x*imageFrame.width,y:imageFrame.minY+mark.y*imageFrame.height,width:(mark.width ?? 0)*imageFrame.width,height:(mark.height ?? 0)*imageFrame.height)
    }
}
