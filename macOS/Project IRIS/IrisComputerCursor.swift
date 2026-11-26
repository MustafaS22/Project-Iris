import AppKit
import QuartzCore

/// Click-through marker for the executor's current target.
@MainActor final class IrisComputerCursor {
    private var panel: NSPanel?
    private let drawing = CursorDrawing(frame: NSRect(x: 0, y: 0, width: 46, height: 46))
    private var active = false
    private var fadeOut: Task<Void, Never>?
    var accent: NSColor { get { drawing.accent } set { drawing.accent = newValue } }

    func show() { active = true }

    func hide() {
        active = false
        drawing.setFloating(false)
        fadeOut?.cancel()
        guard let panel, panel.isVisible else { return }
        if IrisMotion.reduced { panel.orderOut(nil); return }
        drawing.fade(to: 0, duration: 0.18)
        fadeOut = Task { [weak panel] in
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            panel?.orderOut(nil)
        }
    }

    func move(to point: CGPoint) throws {
        try Task.checkCancellation()
        guard active else { return }
        if panel == nil {
            let window = NSPanel(contentRect: drawing.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.level = .floating
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.contentView = drawing
            panel = window
        }
        guard let panel else { return }
        let entering = !panel.isVisible || fadeOut != nil
        fadeOut?.cancel()
        fadeOut = nil
        let reduced = IrisMotion.reduced
        let destination = origin(for: point)
        if entering || reduced {
            panel.setFrameOrigin(destination)
            if !panel.isVisible {
                drawing.fade(to: reduced ? 1 : 0, duration: 0)
                panel.orderFrontRegardless()
            }
            drawing.fade(to: 1, duration: reduced ? 0 : 0.16)
        } else if destination != panel.frame.origin {
            let current = panel.frame.origin
            let distance = hypot(current.x - destination.x, current.y - destination.y)
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = min(0.23, 0.10 + 0.0003 * distance)
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrameOrigin(destination)
            }, completionHandler: nil)
        }
        drawing.setFloating(!reduced)
    }

    private func origin(for point: CGPoint) -> NSPoint {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return NSPoint(x: point.x - CursorDrawing.tip.x, y: top - point.y - CursorDrawing.tip.y)
    }

    func track(_ point: CGPoint) {
        guard active else { return }
        drawing.setFloating(false)
        panel?.setFrameOrigin(origin(for: point))
    }

    #if DEBUG
    func renderSample(to url: URL) throws {
        let window = NSWindow(contentRect: drawing.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = drawing
        defer { window.contentView = nil }
        guard let bitmap = drawing.bitmapImageRepForCachingDisplay(in: drawing.bounds) else {
            throw IrisFailure.message("Could not render the cursor preview.")
        }
        drawing.cacheDisplay(in: drawing.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif

    func feedback(typing: Bool = false) {
        guard active else { return }
        drawing.respond(typing: typing, reduced: IrisMotion.reduced)
        drawing.setFloating(!IrisMotion.reduced)
    }
}

@MainActor private final class CursorDrawing: NSView {
    static let tip = CGPoint(x: 14, y: 34)
    private let bodyLayer = CALayer()
    private let glyph = CAShapeLayer()
    private let eyes = CAShapeLayer()
    private let ripple = CAShapeLayer()
    var accent = NSColor(calibratedRed: 0.92, green: 0.72, blue: 0.48, alpha: 1) {
        didSet { updateInk() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        bodyLayer.bounds = bounds
        bodyLayer.anchorPoint = CGPoint(x: Self.tip.x / bounds.width, y: Self.tip.y / bounds.height)
        bodyLayer.position = Self.tip
        let silhouette = CGMutablePath()
        silhouette.move(to: Self.tip)
        silhouette.addQuadCurve(to: CGPoint(x: 16.1, y: 33.7), control: CGPoint(x: 14.3, y: 34.65))
        silhouette.addCurve(to: CGPoint(x: 27.1, y: 26.4), control1: CGPoint(x: 20.5, y: 31.4), control2: CGPoint(x: 25.1, y: 29.1))
        silhouette.addCurve(to: CGPoint(x: 29.0, y: 21.8), control1: CGPoint(x: 28.7, y: 24.5), control2: CGPoint(x: 29.2, y: 23.2))
        silhouette.addCurve(to: CGPoint(x: 22.0, y: 17.0), control1: CGPoint(x: 28.6, y: 18.4), control2: CGPoint(x: 25.5, y: 16.2))
        silhouette.addCurve(to: CGPoint(x: 17.8, y: 22.3), control1: CGPoint(x: 19.9, y: 17.4), control2: CGPoint(x: 18.5, y: 19.6))
        silhouette.addCurve(to: Self.tip, control1: CGPoint(x: 16.7, y: 26.3), control2: CGPoint(x: 14.4, y: 32.0))
        silhouette.closeSubpath()
        glyph.frame = bounds
        glyph.path = silhouette
        glyph.fillColor = NSColor(srgbRed: 0.066, green: 0.065, blue: 0.075, alpha: 0.97).cgColor
        glyph.lineWidth = 1.15
        glyph.lineJoin = .round
        glyph.shadowPath = silhouette
        glyph.shadowOpacity = 0.47
        glyph.shadowRadius = 2.6
        glyph.shadowOffset = CGSize(width: 0, height: -1)

        let eyePath = CGMutablePath()
        for x in [21.1, 24.15] {
            eyePath.addRoundedRect(in: CGRect(x: x, y: 21.15, width: 1.45, height: 3.05),
                                   cornerWidth: 0.7, cornerHeight: 0.7)
        }
        eyes.frame = bounds
        eyes.path = eyePath
        ripple.bounds = CGRect(x: 0, y: 0, width: 21, height: 21)
        ripple.position = Self.tip
        ripple.path = CGPath(ellipseIn: CGRect(x: 2, y: 2, width: 17, height: 17), transform: nil)
        ripple.fillColor = nil
        ripple.lineWidth = 1.1
        ripple.opacity = 0
        updateInk()
        layer?.addSublayer(ripple)
        bodyLayer.addSublayer(glyph)
        bodyLayer.addSublayer(eyes)
        layer?.addSublayer(bodyLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private func updateInk() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glyph.strokeColor = accent.withAlphaComponent(0.95).cgColor
        eyes.fillColor = accent.cgColor
        glyph.shadowColor = accent.blended(withFraction: 0.62, of: .black)?.cgColor
        ripple.strokeColor = accent.cgColor
        CATransaction.commit()
    }

    func fade(to opacity: Float, duration: Double) {
        guard let layer else { return }
        let current = layer.presentation()?.opacity ?? layer.opacity
        layer.removeAnimation(forKey: "presence")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.opacity = opacity
        CATransaction.commit()
        if duration > 0 {
            let animation = CABasicAnimation(keyPath: "opacity")
            animation.fromValue = current
            animation.toValue = opacity
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(animation, forKey: "presence")
        }
    }

    func setFloating(_ floating: Bool) {
        if !floating {
            bodyLayer.removeAnimation(forKey: "float")
            return
        }
        guard bodyLayer.animation(forKey: "float") == nil else { return }
        let motion = CABasicAnimation(keyPath: "transform.translation.y")
        motion.fromValue = 0
        motion.toValue = 1.35
        motion.duration = 1.42
        motion.autoreverses = true
        motion.repeatCount = .infinity
        motion.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        bodyLayer.add(motion, forKey: "float")
    }

    func respond(typing: Bool, reduced: Bool) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = typing ? 0.25 : 0.65
        fade.toValue = 0
        fade.duration = 0.24
        if reduced {
            ripple.add(fade, forKey: "response")
            return
        }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = typing ? 0.34 : 0.38
        scale.toValue = typing ? 0.8 : 1
        scale.duration = fade.duration
        let group = CAAnimationGroup()
        group.animations = [fade, scale]
        group.duration = fade.duration
        ripple.add(group, forKey: "response")

        let press = CAKeyframeAnimation(keyPath: "transform.scale")
        press.values = [1, typing ? 0.97 : 0.90, 1]
        press.keyTimes = [0, 0.29, 1]
        press.duration = 0.20
        press.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        bodyLayer.add(press, forKey: "press")
    }
}
