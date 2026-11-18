import SwiftUI

/// Editable vector anatomy, not raster images or generic boxed icons.
/// Each outline draws in order; fill follows the pen rather than popping in.
enum DiagramArtwork {
    struct Layer { var path: Path; var color: String; var filled = false }
    static func palette(_ name: String?, accent: Color) -> Color {
        switch name {
        case "yellow": Color(red:1,green:0.81,blue:0.30)
        case "orange": Color(red:1,green:0.58,blue:0.27)
        case "red": Color(red:1,green:0.40,blue:0.42)
        case "green": Color(red:0.43,green:0.84,blue:0.59)
        case "cyan": Color(red:0.39,green:0.85,blue:0.94)
        case "blue": Color(red:0.43,green:0.66,blue:1)
        case "purple": Color(red:0.77,green:0.63,blue:1)
        case "white": .white.opacity(0.9)
        default: accent
        }
    }
    static func layers(_ object: String) -> [Layer] {
        var result: [Layer] = []
        func path(_ color: String, filled: Bool = false, _ body: (inout Path) -> Void) {
            var p = Path(); body(&p); result.append(.init(path:p,color:color,filled:filled))
        }
        func line(_ points: [CGPoint], _ color: String) { path(color) { p in guard let first=points.first else{return}; p.move(to:first); for point in points.dropFirst(){p.addLine(to:point)} } }
        func ellipse(_ x: Double,_ y: Double,_ w: Double,_ h: Double,_ color: String,filled: Bool = false) { path(color,filled:filled){$0.addEllipse(in:CGRect(x:x,y:y,width:w,height:h))} }
        func leaf(_ x: Double,_ y: Double,_ right: Bool) {
            path("green",filled:true) { p in
                p.move(to:CGPoint(x:0.5,y:y+0.22))
                p.addQuadCurve(to:CGPoint(x:x,y:y),control:CGPoint(x: right ? 0.9:0.1,y:y+0.24))
                p.addQuadCurve(to:CGPoint(x:0.5,y:y+0.22),control:CGPoint(x:0.5,y:y-0.05))
            }
            line([CGPoint(x:0.5,y:y+0.22),CGPoint(x:x,y:y)],"green")
        }
        switch object {
        case "sun":
            ellipse(0.28,0.28,0.44,0.44,"yellow",filled:true)
            for i in 0..<12 { let a=Double(i)*Double.pi/6; line([CGPoint(x:0.5+0.31*cos(a),y:0.5+0.31*sin(a)),CGPoint(x:0.5+0.43*cos(a),y:0.5+0.43*sin(a))],"yellow") }
        case "plant":
            path("green") { p in p.move(to:CGPoint(x:0.5,y:0.84));p.addCurve(to:CGPoint(x:0.5,y:0.18),control1:CGPoint(x:0.43,y:0.58),control2:CGPoint(x:0.58,y:0.35)) }
            leaf(0.12,0.44,false);leaf(0.87,0.26,true);leaf(0.24,0.12,false)
            line([CGPoint(x:0.2,y:0.85),CGPoint(x:0.8,y:0.85)],"orange")
            for x in [0.32,0.5,0.68] { line([CGPoint(x:0.5,y:0.85),CGPoint(x:x,y:0.97)],"orange") }
        case "leaf":
            path("green",filled:true) { p in p.move(to:CGPoint(x:0.15,y:0.82));p.addCurve(to:CGPoint(x:0.85,y:0.12),control1:CGPoint(x:0.05,y:0.05),control2:CGPoint(x:0.61,y:0.12));p.addCurve(to:CGPoint(x:0.15,y:0.82),control1:CGPoint(x:0.92,y:0.68),control2:CGPoint(x:0.65,y:0.95)) }
            line([CGPoint(x:0.08,y:0.92),CGPoint(x:0.76,y:0.23)],"green")
            for i in 0..<3 {let t=Double(i)*0.16;line([CGPoint(x:0.28+t,y:0.72-t),CGPoint(x:0.23+t,y:0.42-t)],"green");line([CGPoint(x:0.34+t,y:0.66-t),CGPoint(x:0.64+t,y:0.70-t)],"green")}
        case "chloroplast":
            ellipse(0.06,0.21,0.88,0.58,"green",filled:true);ellipse(0.10,0.25,0.80,0.50,"green")
            for x in [0.25,0.5,0.75] {for y in [0.40,0.46,0.52,0.58]{ellipse(x-0.07,y,0.14,0.045,"green",filled:true)}}
            line([CGPoint(x:0.3,y:0.53),CGPoint(x:0.7,y:0.53)],"green")
        case "cell":
            path("cyan",filled:true){ p in p.move(to:CGPoint(x:0.18,y:0.28));p.addCurve(to:CGPoint(x:0.79,y:0.18),control1:CGPoint(x:0.28,y:0.06),control2:CGPoint(x:0.58,y:0.08));p.addCurve(to:CGPoint(x:0.82,y:0.77),control1:CGPoint(x:1,y:0.35),control2:CGPoint(x:0.89,y:0.59));p.addCurve(to:CGPoint(x:0.18,y:0.77),control1:CGPoint(x:0.57,y:0.98),control2:CGPoint(x:0.19,y:0.9));p.addCurve(to:CGPoint(x:0.18,y:0.28),control1:CGPoint(x:0.01,y:0.59),control2:CGPoint(x:0.11,y:0.44)) }
            ellipse(0.37,0.32,0.30,0.32,"purple",filled:true);ellipse(0.48,0.43,0.07,0.08,"purple",filled:true)
            for (x,y) in [(0.2,0.42),(0.65,0.68),(0.25,0.72)] {ellipse(x,y,0.15,0.07,"orange");line([CGPoint(x:x+0.03,y:y+0.035),CGPoint(x:x+0.12,y:y+0.035)],"orange")}
        case "atom":
            for angle in [0.0,Double.pi/3,-Double.pi/3] { var p=Path(ellipseIn:CGRect(x:0.08,y:0.34,width:0.84,height:0.32));p=p.applying(CGAffineTransform(translationX:-0.5,y:-0.5).concatenating(CGAffineTransform(rotationAngle:angle)).concatenating(CGAffineTransform(translationX:0.5,y:0.5)));result.append(.init(path:p,color:"cyan")) }
            ellipse(0.43,0.43,0.14,0.14,"orange",filled:true)
            for (x,y) in [(0.07,0.46),(0.66,0.17),(0.70,0.73)]{ellipse(x,y,0.08,0.08,"cyan",filled:true)}
        case "molecule":
            line([CGPoint(x:0.2,y:0.65),CGPoint(x:0.5,y:0.38),CGPoint(x:0.8,y:0.65)],"white")
            ellipse(0.34,0.20,0.32,0.32,"red",filled:true);ellipse(0.09,0.55,0.22,0.22,"cyan",filled:true);ellipse(0.69,0.55,0.22,0.22,"cyan",filled:true)
        case "cloud":
            path("cyan",filled:true){p in p.move(to:CGPoint(x:0.19,y:0.72));p.addCurve(to:CGPoint(x:0.19,y:0.40),control1:CGPoint(x:-0.02,y:0.70),control2:CGPoint(x:0.02,y:0.41));p.addCurve(to:CGPoint(x:0.61,y:0.30),control1:CGPoint(x:0.18,y:0.07),control2:CGPoint(x:0.55,y:0.06));p.addCurve(to:CGPoint(x:0.83,y:0.43),control1:CGPoint(x:0.82,y:0.16),control2:CGPoint(x:0.93,y:0.31));p.addCurve(to:CGPoint(x:0.82,y:0.72),control1:CGPoint(x:1,y:0.45),control2:CGPoint(x:1,y:0.74));p.closeSubpath()}
        case "droplet":
            path("blue",filled:true){p in p.move(to:CGPoint(x:0.5,y:0.06));p.addCurve(to:CGPoint(x:0.5,y:0.94),control1:CGPoint(x:-0.08,y:0.72),control2:CGPoint(x:0.22,y:0.94));p.addCurve(to:CGPoint(x:0.5,y:0.06),control1:CGPoint(x:0.9,y:0.94),control2:CGPoint(x:1.02,y:0.65))}
            path("cyan"){p in p.move(to:CGPoint(x:0.29,y:0.62));p.addQuadCurve(to:CGPoint(x:0.4,y:0.82),control:CGPoint(x:0.27,y:0.78))}
        case "earth":
            ellipse(0.08,0.08,0.84,0.84,"blue",filled:true)
            path("green",filled:true){p in p.move(to:CGPoint(x:0.22,y:0.20));for q in [CGPoint(x:0.48,y:0.15),CGPoint(x:0.57,y:0.3),CGPoint(x:0.4,y:0.42),CGPoint(x:0.46,y:0.61),CGPoint(x:0.3,y:0.73),CGPoint(x:0.27,y:0.48),CGPoint(x:0.12,y:0.40)]{p.addLine(to:q)};p.closeSubpath()}
            path("green",filled:true){p in p.move(to:CGPoint(x:0.7,y:0.45));p.addLine(to:CGPoint(x:0.88,y:0.52));p.addLine(to:CGPoint(x:0.72,y:0.8));p.addLine(to:CGPoint(x:0.58,y:0.62));p.closeSubpath()}
        case "flame":
            path("orange",filled:true){p in p.move(to:CGPoint(x:0.51,y:0.06));p.addCurve(to:CGPoint(x:0.83,y:0.72),control1:CGPoint(x:0.48,y:0.43),control2:CGPoint(x:0.97,y:0.32));p.addCurve(to:CGPoint(x:0.18,y:0.72),control1:CGPoint(x:0.83,y:1),control2:CGPoint(x:0.18,y:1));p.addCurve(to:CGPoint(x:0.51,y:0.06),control1:CGPoint(x:0.03,y:0.47),control2:CGPoint(x:0.4,y:0.4))}
            path("yellow",filled:true){p in p.move(to:CGPoint(x:0.5,y:0.47));p.addQuadCurve(to:CGPoint(x:0.5,y:0.91),control:CGPoint(x:0.12,y:0.91));p.addQuadCurve(to:CGPoint(x:0.5,y:0.47),control:CGPoint(x:0.86,y:0.89))}
        case "thermometer":
            path("white"){p in p.move(to:CGPoint(x:0.4,y:0.66));p.addLine(to:CGPoint(x:0.4,y:0.15));p.addCurve(to:CGPoint(x:0.6,y:0.15),control1:CGPoint(x:0.4,y:0.02),control2:CGPoint(x:0.6,y:0.02));p.addLine(to:CGPoint(x:0.6,y:0.66))}
            ellipse(0.34,0.63,0.32,0.32,"red",filled:true);line([CGPoint(x:0.5,y:0.76),CGPoint(x:0.5,y:0.28)],"red")
            for y in [0.2,0.32,0.44,0.56]{line([CGPoint(x:0.67,y:y),CGPoint(x:0.78,y:y)],"white")}
        case "beaker":
            path("cyan",filled:true){p in p.move(to:CGPoint(x:0.3,y:0.08));p.addLine(to:CGPoint(x:0.3,y:0.35));p.addLine(to:CGPoint(x:0.12,y:0.86));p.addQuadCurve(to:CGPoint(x:0.88,y:0.86),control:CGPoint(x:0.5,y:0.98));p.addLine(to:CGPoint(x:0.7,y:0.35));p.addLine(to:CGPoint(x:0.7,y:0.08))}
            line([CGPoint(x:0.25,y:0.08),CGPoint(x:0.75,y:0.08)],"cyan");line([CGPoint(x:0.23,y:0.57),CGPoint(x:0.77,y:0.57)],"blue")
            for (x,y) in [(0.4,0.68),(0.6,0.77),(0.5,0.46)]{ellipse(x,y,0.05,0.05,"blue")}
        case "battery":
            path("green",filled:true){$0.addRoundedRect(in:CGRect(x:0.1,y:0.25,width:0.73,height:0.5),cornerSize:CGSize(width:0.06,height:0.06))}
            line([CGPoint(x:0.84,y:0.4),CGPoint(x:0.92,y:0.4),CGPoint(x:0.92,y:0.6),CGPoint(x:0.84,y:0.6)],"green")
            line([CGPoint(x:0.23,y:0.5),CGPoint(x:0.37,y:0.5)],"white");line([CGPoint(x:0.57,y:0.5),CGPoint(x:0.73,y:0.5)],"white");line([CGPoint(x:0.65,y:0.42),CGPoint(x:0.65,y:0.58)],"white")
        case "resistor":
            line([CGPoint(x:0.03,y:0.5),CGPoint(x:0.2,y:0.5),CGPoint(x:0.27,y:0.3),CGPoint(x:0.38,y:0.7),CGPoint(x:0.49,y:0.3),CGPoint(x:0.6,y:0.7),CGPoint(x:0.71,y:0.3),CGPoint(x:0.8,y:0.5),CGPoint(x:0.97,y:0.5)],"orange")
        case "magnet":
            path("red",filled:true){p in p.move(to:CGPoint(x:0.12,y:0.18));p.addLine(to:CGPoint(x:0.12,y:0.57));p.addCurve(to:CGPoint(x:0.88,y:0.57),control1:CGPoint(x:0.12,y:1.12),control2:CGPoint(x:0.88,y:1.12));p.addLine(to:CGPoint(x:0.88,y:0.18));p.addLine(to:CGPoint(x:0.66,y:0.18));p.addLine(to:CGPoint(x:0.66,y:0.57));p.addCurve(to:CGPoint(x:0.34,y:0.57),control1:CGPoint(x:0.66,y:0.84),control2:CGPoint(x:0.34,y:0.84));p.addLine(to:CGPoint(x:0.34,y:0.18));p.closeSubpath()}
            line([CGPoint(x:0.12,y:0.36),CGPoint(x:0.34,y:0.36)],"blue");line([CGPoint(x:0.66,y:0.36),CGPoint(x:0.88,y:0.36)],"blue")
        case "heart":
            path("red",filled:true){p in p.move(to:CGPoint(x:0.49,y:0.91));p.addCurve(to:CGPoint(x:0.22,y:0.21),control1:CGPoint(x:-0.06,y:0.57),control2:CGPoint(x:0.05,y:0.08));p.addCurve(to:CGPoint(x:0.56,y:0.23),control1:CGPoint(x:0.32,y:0.1),control2:CGPoint(x:0.45,y:0.2));p.addCurve(to:CGPoint(x:0.49,y:0.91),control1:CGPoint(x:1.03,y:0.05),control2:CGPoint(x:1,y:0.68))}
            path("red"){p in p.move(to:CGPoint(x:0.48,y:0.4));p.addQuadCurve(to:CGPoint(x:0.52,y:0.85),control:CGPoint(x:0.62,y:0.55))}
            line([CGPoint(x:0.48,y:0.28),CGPoint(x:0.43,y:0.05)],"blue");line([CGPoint(x:0.59,y:0.28),CGPoint(x:0.68,y:0.06)],"red")
        case "lungs":
            line([CGPoint(x:0.5,y:0.05),CGPoint(x:0.5,y:0.48),CGPoint(x:0.32,y:0.65)],"cyan");line([CGPoint(x:0.5,y:0.48),CGPoint(x:0.7,y:0.65)],"cyan")
            for right in [false,true] {let sign=right ? 1.0:-1.0;path("purple",filled:true){p in p.move(to:CGPoint(x:0.5+sign*0.08,y:0.32));p.addCurve(to:CGPoint(x:0.5+sign*0.39,y:0.88),control1:CGPoint(x:0.5+sign*0.36,y:0.1),control2:CGPoint(x:0.5+sign*0.53,y:0.78));p.addQuadCurve(to:CGPoint(x:0.5+sign*0.08,y:0.32),control:CGPoint(x:0.5+sign*0.02,y:0.98))}}
        default: break
        }
        return result
    }
    static func draw(_ mark: ScreenDrawing.Mark, progress: Double, context: GraphicsContext, size: CGSize, accent: Color) {
        let rect=CGRect(x:mark.x*size.width,y:mark.y*size.height,width:(mark.width ?? 0)*size.width,height:(mark.height ?? 0)*size.height)
        let side=min(rect.width,rect.height)
        let transform=CGAffineTransform(scaleX:side,y:side).concatenating(CGAffineTransform(translationX:rect.midX-side/2,y:rect.midY-side/2))
        let layers=layers(mark.object ?? "")
        for (index,layer) in layers.enumerated() {
            let t=min(1,max(0,progress*Double(layers.count)-Double(index)))
            guard t>0 else {continue}
            let path=layer.path.applying(transform),color=palette(mark.color ?? layer.color,accent:accent)
            if layer.filled {var fill=context;fill.opacity=t*0.16;fill.fill(path,with:.color(color))}
            context.stroke(path.trimmedPath(from:0,to:t),with:.color(color),style:StrokeStyle(lineWidth: max(1.7,side/75),lineCap:.round,lineJoin:.round))
        }
        if let label=mark.text,progress>0.75 {
            var text=context;text.opacity=min(1,(progress-0.75)/0.25)
            let resolved=text.resolve(Text(label).font(.system(size:min(18,max(12,size.width/80)),weight:.medium)).foregroundStyle(.white))
            let box=CGRect(x:rect.midX-max(rect.width,side+30)/2,y:rect.maxY+8,width:max(rect.width,side+30),height:42)
            let measured=resolved.measure(in:box.size)
            text.draw(resolved,in:CGRect(x:box.midX-measured.width/2,y:box.minY,width:measured.width,height:measured.height))
        }
    }
    static func customPath(_ mark: ScreenDrawing.Mark, size: CGSize) -> Path {
        let points=mark.points ?? []
        func point(_ x:Double,_ y:Double)->CGPoint{CGPoint(x:(mark.x+x*(mark.width ?? 0))*size.width,y:(mark.y+y*(mark.height ?? 0))*size.height)}
        var path=Path();guard let first=points.first else{return path};path.move(to:point(first.x,first.y))
        for p in points.dropFirst(){if let cx=p.cx,let cy=p.cy,let c2x=p.c2x,let c2y=p.c2y{path.addCurve(to:point(p.x,p.y),control1:point(cx,cy),control2:point(c2x,c2y))}else{path.addLine(to:point(p.x,p.y))}}
        if mark.closed == true {path.closeSubpath()};return path
    }
}
