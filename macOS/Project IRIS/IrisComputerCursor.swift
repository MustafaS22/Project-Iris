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
    private let outerRim = CAShapeLayer()
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
        silhouette.move(to: CGPoint(x: 15.15, y: 35.1))
        silhouette.addLine(to: CGPoint(x: 34.2, y: 28.7))
        silhouette.addQuadCurve(to: CGPoint(x: 34.5, y: 25.3), control: CGPoint(x: 37.2, y: 27.25))
        silhouette.addLine(to: CGPoint(x: 26.6, y: 21.55))
        silhouette.addLine(to: CGPoint(x: 23.2, y: 13.15))
        silhouette.addQuadCurve(to: CGPoint(x: 19.7, y: 13.3), control: CGPoint(x: 21.45, y: 10.15))
        silhouette.addLine(to: CGPoint(x: 13.05, y: 32.95))
        silhouette.addQuadCurve(to: CGPoint(x: 15.15, y: 35.1), control: CGPoint(x: 12.2, y: 36.15))
        silhouette.closeSubpath()

        outerRim.frame = bounds
        outerRim.path = silhouette
        outerRim.fillColor = nil
        outerRim.lineWidth = 5.5
        outerRim.lineJoin = .round
        outerRim.shadowColor = NSColor.black.cgColor
        outerRim.shadowPath = silhouette
        outerRim.shadowOpacity = 0.35
        outerRim.shadowRadius = 2.1
        outerRim.shadowOffset = CGSize(width: 0, height: -1)
        glyph.frame = bounds
        glyph.path = silhouette
        glyph.fillColor = NSColor(srgbRed: 0.041, green: 0.041, blue: 0.045, alpha: 1).cgColor
        glyph.lineWidth = 2.55
        glyph.lineJoin = .round
        ripple.bounds = CGRect(x: 0, y: 0, width: 21, height: 21)
        ripple.position = Self.tip
        ripple.path = CGPath(ellipseIn: CGRect(x: 2, y: 2, width: 17, height: 17), transform: nil)
        ripple.fillColor = nil
        ripple.lineWidth = 1.1
        ripple.opacity = 0
        updateInk()
        layer?.addSublayer(ripple)
        bodyLayer.addSublayer(outerRim)
        bodyLayer.addSublayer(glyph)
        layer?.addSublayer(bodyLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    private func updateInk() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let tint = accent.usingColorSpace(.sRGB) ?? accent
        glyph.strokeColor = tint.withAlphaComponent(1).cgColor
        outerRim.strokeColor = (tint.blended(withFraction: 0.66, of: .white) ?? tint).cgColor
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
