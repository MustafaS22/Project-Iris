import AppKit

/// A click-through indicator for actual native actions, not a second WindowServer pointer.
@MainActor final class IrisComputerCursor {
    private var panel: NSPanel?
    private let drawing = CursorDrawing(frame: NSRect(x:0,y:0,width:150,height:48))
    private var active = false
    var accent: NSColor { get { drawing.accent } set { drawing.accent = newValue } }
    func show() { active = true }
    func hide() { active = false; panel?.orderOut(nil) }
    func move(to point: CGPoint, application: String, independent: Bool, applicationEvents: Bool = false) async throws {
        guard active else { return }
        if panel == nil {
            let window = NSPanel(contentRect:drawing.bounds,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
            window.ignoresMouseEvents = true; window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            window.contentView = drawing; panel = window
        }
        guard let panel else { return }
        drawing.caption = independent ? "Iris · Accessibility" : applicationEvents ? "Iris · app events" : "Iris · shared pointer"
        drawing.application = application; drawing.needsDisplay = true
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let origin = NSPoint(x:point.x-8,y:top-point.y-40)
        if !panel.isVisible { panel.setFrameOrigin(origin); panel.orderFrontRegardless() }
        else { await NSAnimationContext.runAnimationGroup { context in context.duration = 0.14; context.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut); panel.animator().setFrameOrigin(origin) } }
        try await Task.sleep(for:.milliseconds(145)); try Task.checkCancellation()
    }
    func track(_ point: CGPoint) {
        guard active else { return }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        panel?.setFrameOrigin(NSPoint(x:point.x-8,y:top-point.y-40))
    }
    func feedback() {
        guard active else { return }
        drawing.pulse = true; drawing.needsDisplay = true
        Task { [weak self] in try? await Task.sleep(for:.milliseconds(180)); self?.drawing.pulse = false; self?.drawing.needsDisplay = true }
    }
}
import QuartzCore
@MainActor private final class CursorDrawing: NSView {
    var caption = "Iris", application = "", pulse = false
    var accent = NSColor(calibratedRed:0.92,green:0.72,blue:0.48,alpha:1)
    override func draw(_ dirtyRect: NSRect) {
        if pulse { accent.withAlphaComponent(0.24).setFill(); NSBezierPath(ovalIn:NSRect(x:0,y:19,width:27,height:27)).fill() }
        let pointer = NSBezierPath(); pointer.move(to:NSPoint(x:8,y:40)); pointer.line(to:NSPoint(x:8,y:20)); pointer.line(to:NSPoint(x:14,y:25)); pointer.line(to:NSPoint(x:19,y:15)); pointer.line(to:NSPoint(x:23,y:17)); pointer.line(to:NSPoint(x:18,y:27)); pointer.line(to:NSPoint(x:26,y:27)); pointer.close()
        NSColor.black.withAlphaComponent(0.9).setStroke(); pointer.lineWidth = 3; pointer.stroke(); accent.setFill(); pointer.fill()
        NSColor.black.withAlphaComponent(0.8).setFill(); NSBezierPath(roundedRect:NSRect(x:30,y:5,width:118,height:36),xRadius:10,yRadius:10).fill()
        for x: CGFloat in [37,43] { accent.setFill(); NSBezierPath(roundedRect:NSRect(x:x,y:26,width:3,height:7),xRadius:1.5,yRadius:1.5).fill() }
        (caption as NSString).draw(at:NSPoint(x:51,y:25),withAttributes:[.font:NSFont.systemFont(ofSize:8,weight:.semibold),.foregroundColor:accent])
        (String(application.prefix(23)) as NSString).draw(at:NSPoint(x:37,y:11),withAttributes:[.font:NSFont.systemFont(ofSize:10,weight:.medium),.foregroundColor:NSColor.white])
    }
}
