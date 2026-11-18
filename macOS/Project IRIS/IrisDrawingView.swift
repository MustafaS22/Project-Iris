import SwiftUI

/// A finite draw-on sequence. Leaders are painted beneath labels, never across their text.
struct IrisDrawingView: View {
    let drawing: ScreenDrawing
    let accent: Color
    var revision = 0
    var visibleMarkCount: Int? = nil
    var revealFromIndex = 0
    var presentationComplete = false
    var previewElapsed: Double? = nil
    @Environment(\.irisReduceMotion) private var reduceMotion
    @State private var started = Date()
    @State private var activeRevision = -1
    @State private var animating = false
    private struct PlaybackKey: Hashable { let drawing: ScreenDrawing; let revision: Int }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !animating || reduceMotion || previewElapsed != nil)) { timeline in
            Canvas { context, size in
                let elapsed = previewElapsed ?? (reduceMotion ? 100 : (activeRevision == revision ? timeline.date.timeIntervalSince(started) : 0))
                if drawing.mode == "conceptual", !drawing.marks.isEmpty {
                    let board = CGRect(x: size.width * 0.06, y: size.height * 0.12, width: size.width * 0.88, height: size.height * 0.78)
                    let path = Path(roundedRect: board, cornerRadius: 24)
                    context.fill(path, with: .color(Color(red: 0.055, green: 0.065, blue: 0.06).opacity(0.96)))
                    context.stroke(path, with: .color(accent.opacity(0.24)), lineWidth: 1)
                    if let title = drawing.title {
                        context.draw(context.resolve(Text(title).font(.system(size: min(24, size.width / 40), weight: .semibold)).foregroundStyle(.white)), in: CGRect(x: size.width * 0.18, y: size.height * 0.18, width: size.width * 0.64, height: size.height * 0.1))
                    }
                }
                if let figure=drawing.figure, let image=DiagramReferenceStore.image(figure) {
                    let fitted=ReferenceHighlight.fitted(image:image.size,canvas:size)
                    var paper=context
                    paper.opacity = reduceMotion || revealFromIndex > 0 ? 1 : min(1,max(0,elapsed/0.9))
                    paper.fill(Path(roundedRect:fitted.insetBy(dx:-10,dy:-10),cornerRadius:10),with:.color(.white))
                    paper.clip(to:Path(fitted))
                    let imageFrame=DiagramPresentation.imageFrame(image:image.size,canvas:size,drawing:drawing,visible:visibleMarkCount,revealFrom:revealFromIndex,elapsed:elapsed,complete:presentationComplete)
                    paper.draw(Image(nsImage:image),in:imageFrame)
                    if let reference=DiagramReferenceStore.reference(figure) {
                        context.draw(Text(String(reference.credit.prefix(150))).font(.system(size:9)).foregroundStyle(.white.opacity(0.65)),in:CGRect(x:size.width*0.16,y:size.height*0.87,width:size.width*0.68,height:20))
                    }
                }
                let layout = AnnotationLayout.make(drawing, size: size) { text in
                    context.resolve(labelText(text, height: 50)).measure(in: CGSize(width: 190, height: 36))
                }
                func progress(_ index: Int) -> Double {
                    if let visibleMarkCount, index >= visibleMarkCount { return 0 }
                    if index < revealFromIndex { return 1 }
                    return AnnotationPlayback.progress(elapsed: elapsed, index: index - revealFromIndex, duration: drawing.marks[index].kind == "object" ? 1.1 : 0.52)
                }
                if !presentationComplete, drawing.mode == "conceptual", let visibleMarkCount,
                   let sentence = drawing.marks.prefix(visibleMarkCount).last(where: { $0.speech != nil })?.speech {
                    let caption = Text(String(sentence.prefix(260))).font(.system(size: min(18, max(13, size.width / 80)))).foregroundStyle(.white.opacity(0.85))
                    context.draw(context.resolve(caption), in: CGRect(x: size.width * 0.18, y: size.height * 0.81, width: size.width * 0.64, height: size.height * 0.09))
                }
                if !presentationComplete, let figure=drawing.figure, let image=DiagramReferenceStore.image(figure),
                   let visibleMarkCount, visibleMarkCount > 0,
                   let name=drawing.marks[drawing.presentationSteps.first(where: { $0.contains(min(visibleMarkCount,drawing.marks.count)-1) }) ?? 0..<0].compactMap(\.text).first {
                    let fitted=ReferenceHighlight.fitted(image:image.size,canvas:size)
                    context.draw(Text(name).font(.system(size:12,weight:.semibold)).foregroundStyle(accent),at:CGPoint(x:fitted.midX,y:fitted.maxY+21))
                }
                // Paint all geometry first, regardless of the provider's mark order.
                for shape in layout.shapes {
                    let mark = shape.mark, p = CGPoint(x: mark.x * size.width, y: mark.y * size.height)
                    let end = CGPoint(x: (mark.x + (mark.width ?? 0)) * size.width, y: (mark.y + (mark.height ?? 0)) * size.height)
                    let value = progress(shape.index)
                    guard value > 0 else { continue }
                    if mark.kind == "focus" {
                        guard !presentationComplete, let figure=drawing.figure,let image=DiagramReferenceStore.image(figure),
                              let visibleMarkCount,visibleMarkCount > 0 else { continue }
                        let current=shape.index >= revealFromIndex
                        let opacity=ReferenceHighlight.opacity(index:shape.index,drawing:drawing,visible:visibleMarkCount,revealFrom:revealFromIndex,elapsed:elapsed)
                        guard opacity > 0, (mark.width ?? 0) > 0, (mark.height ?? 0) > 0 else {continue}
                        let viewport=ReferenceHighlight.fitted(image:image.size,canvas:size)
                        let imageFrame=DiagramPresentation.imageFrame(image:image.size,canvas:size,drawing:drawing,visible:visibleMarkCount,revealFrom:revealFromIndex,elapsed:elapsed,complete:presentationComplete)
                        let rect=DiagramPresentation.focusRect(mark,imageFrame:imageFrame)
                        let path=Path(ellipseIn:rect.insetBy(dx:-3,dy:-3))
                        var highlight=context;highlight.opacity=opacity;highlight.clip(to:Path(viewport))
                        highlight.stroke(path,with:.color(.white.opacity(0.85)),lineWidth:4)
                        highlight.stroke(path.trimmedPath(from:0,to:current ? min(1,elapsed/0.45) : 1),with:.color(accent),style:StrokeStyle(lineWidth:2,lineCap:.round,lineJoin:.round))
                        continue
                    }
                    if mark.kind == "caption" {
                        var ink = context; ink.opacity = value
                        let rect = CGRect(x: mark.x * size.width, y: mark.y * size.height, width: (mark.width ?? 0.18) * size.width, height: (mark.height ?? 0.04) * size.height)
                        let label = ink.resolve(Text(mark.text ?? "").font(.system(size: min(18,max(12,size.width/70)),weight:.medium)).foregroundStyle(DiagramArtwork.palette(mark.color,accent:accent)))
                        let measured = label.measure(in: rect.size)
                        ink.draw(label, in: CGRect(x:rect.midX-measured.width/2,y:rect.midY-measured.height/2,width:measured.width,height:measured.height))
                        continue
                    }
                    if mark.kind == "object" {
                        DiagramArtwork.draw(mark, progress: value, context: context, size: size, accent: accent)
                        continue
                    }
                    var path = Path()
                    if mark.kind == "path" { path = DiagramArtwork.customPath(mark, size: size) }
                    else if mark.kind == "circle" || mark.kind == "rectangle" || mark.kind == "node" {
                        let rect = CGRect(x: min(p.x, end.x), y: min(p.y, end.y), width: abs(end.x - p.x), height: abs(end.y - p.y))
                        if mark.kind == "circle" { path.addEllipse(in: rect) }
                        else { path.addRoundedRect(in: rect, cornerSize: CGSize(width: 8, height: 8)) }
                    } else { path.move(to: p); path.addLine(to: end) }
                    if mark.kind == "node" {
                        var fill = context; fill.opacity = value
                        fill.fill(path, with: .color(Color(red: 0.12, green: 0.15, blue: 0.13)))
                        let rect = CGRect(x: min(p.x, end.x), y: min(p.y, end.y), width: abs(end.x - p.x), height: abs(end.y - p.y)).insetBy(dx: 12, dy: 10)
                        let text = fill.resolve(Text(mark.text ?? "").font(.system(size: min(20, max(12, size.width / 80)), weight: .semibold)).foregroundStyle(.white))
                        let measured = text.measure(in: rect.size)
                        fill.draw(text, in: CGRect(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2, width: measured.width, height: measured.height))
                    }
                    let ink = DiagramArtwork.palette(mark.color, accent: accent)
                    if mark.kind == "circle", mark.closed == true {
                        var fill = context; fill.opacity = value
                        let rect = path.boundingRect
                        fill.fill(path, with: .radialGradient(Gradient(colors:[ink.opacity(0.38),ink.opacity(0.10)]),center:CGPoint(x:rect.midX-rect.width*0.18,y:rect.midY-rect.height*0.18),startRadius:0,endRadius:max(rect.width,rect.height)))
                    }
                    if mark.kind == "path", mark.closed == true { var fill = context; fill.opacity = value * 0.16; fill.fill(path, with: .color(ink)) }
                    stroke(path.trimmedPath(from: 0, to: value), in: context, color: ink)
                    if mark.kind == "arrow", value > 0.84 {
                        var head = Path(); let angle = atan2(end.y - p.y, end.x - p.x)
                        for offset in [-0.48, 0.48] {
                            head.move(to: CGPoint(x: end.x - 9 * cos(angle + offset), y: end.y - 9 * sin(angle + offset))); head.addLine(to: end)
                        }
                        var tip = context; tip.opacity = (value - 0.84) / 0.16; stroke(head, in: tip, color: ink)
                    }
                }
                for callout in layout.callouts {
                    let value = progress(callout.id)
                    guard value > 0 else { continue }
                    guard callout.leader.count == 3, let target = callout.target else { continue }
                    let start = callout.leader[0], elbow = callout.leader[1]
                    var leader = Path(); leader.move(to: start)
                    // A soft bend leaves the label horizontally before meeting the anchor.
                    leader.addQuadCurve(to: target, control: elbow)
                    stroke(leader.trimmedPath(from: 0, to: value), in: context)
                    if value > 0.82 {
                        var tip = context; tip.opacity = (value - 0.82) / 0.18
                        let dot = CGRect(x: target.x - 3, y: target.y - 3, width: 6, height: 6)
                        tip.fill(Path(ellipseIn: dot.insetBy(dx: -2, dy: -2)), with: .color(.black.opacity(0.3)))
                        tip.fill(Path(ellipseIn: dot), with: .color(accent))
                    }
                }
                // Labels ease in only after their leader has begun drawing.
                for (number, callout) in layout.callouts.enumerated() {
                    let value = progress(callout.id)
                    let opacity = min(1, max(0, (value - 0.42) / 0.58))
                    guard opacity > 0 else { continue }
                    var card = context; card.opacity = opacity
                    card.translateBy(x: 0, y: reduceMotion ? 0 : 4 * (1 - opacity))
                    let rect = callout.rect
                    let shape = Path(roundedRect: rect, cornerRadius: 10)
                    var shadow = card
                    shadow.addFilter(.shadow(color: .black.opacity(0.16), radius: 7, x: 0, y: 3))
                    shadow.fill(shape, with: .color(Color(red: 0.075, green: 0.085, blue: 0.08).opacity(0.97)))
                    card.stroke(shape, with: .color(.white.opacity(0.14)), lineWidth: 0.75)
                    let badge = CGRect(x: rect.minX + 10, y: rect.midY - 11, width: 22, height: 22)
                    card.fill(Path(ellipseIn: badge), with: .color(accent.opacity(0.16)))
                    card.draw(Text(String(number + 1)).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(accent), at: CGPoint(x: badge.midX, y: badge.midY))
                    let textRect = CGRect(x: rect.minX + 41, y: rect.minY + 8, width: rect.width - 51, height: rect.height - 16)
                    card.draw(card.resolve(labelText(callout.text, height: rect.height)), in: textRect)
                }
            }
        }
        .task(id: PlaybackKey(drawing: drawing, revision: revision)) {
            started = Date(); activeRevision = revision; animating = !reduceMotion && previewElapsed == nil && !drawing.marks.isEmpty
            guard animating else { return }
            do { try await Task.sleep(for: .seconds(max(1.2, AnnotationPlayback.duration(count: drawing.marks.count)))) } catch { return }
            guard !Task.isCancelled else { return }; animating = false
        }
        .onChange(of: reduceMotion) { _, value in if value { animating = false } }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Iris annotations. " + drawing.marks.compactMap(\.text).joined(separator: ". "))
    }
    private func labelText(_ text: String, height: CGFloat) -> Text {
        Text(text).font(.system(size: height < 40 ? 12 : 14, weight: .medium)).foregroundStyle(.white.opacity(0.95))
    }
    private func stroke(_ path: Path, in context: GraphicsContext, color: Color? = nil) {
        context.stroke(path, with: .color(.black.opacity(0.38)), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
        context.stroke(path, with: .color((color ?? accent).opacity(0.96)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }
}
