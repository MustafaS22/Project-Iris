import AppKit
import QuartzCore

/// Click-through marker for the executor's current target.
@MainActor final class IrisComputerCursor {
    private var panel: NSPanel?
    private let drawing = CursorDrawing(frame:NSRect(x:0,y:0,width:48,height:48))
    private var active = false
    var accent: NSColor { get { drawing.accent } set { drawing.accent = newValue } }
    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func show() { active = true }
    func hide() {
        active = false
        drawing.setFloating(false)
        panel?.orderOut(nil)
    }

    func move(to point: CGPoint) async throws {
        guard active else { return }
        if panel == nil {
            let window = NSPanel(contentRect:drawing.bounds,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
            window.contentView = drawing
            panel = window
        }
        guard let panel else { return }
        drawing.setFloating(false)
        let destination = origin(for:point)
        if !panel.isVisible || reducesMotion {
            panel.setFrameOrigin(destination)
            panel.orderFrontRegardless()
        } else {
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
                panel.animator().setFrameOrigin(destination)
            }
        }
        try Task.checkCancellation()
        if active { drawing.setFloating(!reducesMotion) }
    }

    private func origin(for point: CGPoint) -> NSPoint {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSPoint(x:point.x-14,y:top-point.y-34)
    }

    func track(_ point: CGPoint) {
        guard active else { return }
        drawing.setFloating(false)
        panel?.setFrameOrigin(origin(for:point))
    }

    func feedback() {
        guard active else { return }
        drawing.click(reduceMotion:reducesMotion)
        drawing.setFloating(!reducesMotion)
    }
}

@MainActor private final class CursorDrawing: NSView {
    private let arrow = CAShapeLayer()
    private let ripple = CAShapeLayer()
    var accent = NSColor(calibratedRed:0.92,green:0.72,blue:0.48,alpha:1) {
        didSet { arrow.fillColor = accent.cgColor; ripple.strokeColor = accent.cgColor }
    }

    override init(frame: NSRect) {
        super.init(frame:frame)
        wantsLayer = true
        let path = CGMutablePath()
        path.move(to:CGPoint(x:14,y:34))
        path.addLine(to:CGPoint(x:15.5,y:13.5))
        path.addQuadCurve(to:CGPoint(x:17.5,y:13),control:CGPoint(x:15.7,y:11.5))
        path.addLine(to:CGPoint(x:21,y:18))
        path.addLine(to:CGPoint(x:25,y:10.5))
        path.addQuadCurve(to:CGPoint(x:29,y:12.6),control:CGPoint(x:27.5,y:8.8))
        path.addLine(to:CGPoint(x:25,y:20))
        path.addLine(to:CGPoint(x:31.3,y:20.2))
        path.addQuadCurve(to:CGPoint(x:31.9,y:22.4),control:CGPoint(x:33.4,y:20.5))
        path.closeSubpath()
        arrow.path = path
        arrow.fillColor = accent.cgColor
        arrow.strokeColor = NSColor.black.withAlphaComponent(0.8).cgColor
        arrow.lineWidth = 1.8
        arrow.lineJoin = .round
        arrow.shadowColor = NSColor.black.cgColor
        arrow.shadowOpacity = 0.42
        arrow.shadowRadius = 3
        arrow.shadowOffset = CGSize(width:0,height:-2)
        ripple.bounds = CGRect(x:0,y:0,width:24,height:24)
        ripple.position = CGPoint(x:14,y:34)
        ripple.path = CGPath(ellipseIn:CGRect(x:2,y:2,width:20,height:20),transform:nil)
        ripple.fillColor = nil
        ripple.strokeColor = accent.cgColor
        ripple.lineWidth = 1.4
        ripple.opacity = 0
        layer?.addSublayer(ripple)
        layer?.addSublayer(arrow)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    func setFloating(_ floating: Bool) {
        guard floating else { arrow.removeAnimation(forKey:"float"); return }
        guard arrow.animation(forKey:"float") == nil else { return }
        let motion = CABasicAnimation(keyPath:"transform.translation.y")
        motion.fromValue = 0
        motion.toValue = 1.7
        motion.duration = 1.1
        motion.autoreverses = true
        motion.repeatCount = .infinity
        motion.timingFunction = CAMediaTimingFunction(name:.easeInEaseOut)
        arrow.add(motion,forKey:"float")
    }

    func click(reduceMotion: Bool) {
        let fade = CABasicAnimation(keyPath:"opacity")
        fade.fromValue = 0.75
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [fade]
        if !reduceMotion {
            let scale = CABasicAnimation(keyPath:"transform.scale")
            scale.fromValue = 0.4
            scale.toValue = 1
            group.animations = [fade,scale]
        }
        group.duration = 0.24
        for animation in group.animations ?? [] { animation.duration = group.duration }
        ripple.add(group,forKey:"click")
    }
}
