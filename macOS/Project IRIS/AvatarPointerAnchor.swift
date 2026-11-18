import SwiftUI
import AppKit
import Combine

/// Reads position only while the live face renders. No event monitors, logging or extra permissions.
@MainActor
final class AvatarPointerProbe: ObservableObject {
    weak var view: NSView?
    private var motion = AvatarCursorMotion()
    func following(_ pose: AvatarPose, at time: TimeInterval, size: CGFloat, enabled: Bool, guidance: CGSize? = nil, followsCursorAnywhere: Bool = false) -> AvatarPose {
        var target = AvatarCursorGaze()
        // Explicit travel/drag attention already uses view-space coordinates. It must not
        // depend on the invisible cursor anchor being attached to a native window.
        if enabled, let guidance {
            target = AvatarCursorMotion.directed(dx: guidance.width, dy: guidance.height, size: size)
        } else if enabled, let view, let window = view.window, window.isVisible, !window.isMiniaturized, !view.isHiddenOrHasHiddenAncestor {
            let localCenter = NSPoint(x: view.bounds.midX, y: view.bounds.midY)
            let center = window.convertPoint(toScreen: view.convert(localCenter, to: nil))
            let pointer = NSEvent.mouseLocation
            let dx = pointer.x - center.x, dy = center.y - pointer.y
            target = followsCursorAnywhere ? AvatarCursorMotion.directed(dx: dx, dy: dy, size: size) : AvatarCursorMotion.target(dx: dx, dy: dy, size: size)
        }
        return AvatarCursorMotion.apply(motion.update(target: target, at: time), to: pose)
    }
}

struct AvatarPointerAnchor: NSViewRepresentable {
    let probe: AvatarPointerProbe
    func makeNSView(context: Context) -> NSView {
        let view = PassiveAvatarAnchor(); probe.view = view; return view
    }
    func updateNSView(_ nsView: NSView, context: Context) { probe.view = nsView }
    private final class PassiveAvatarAnchor: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
