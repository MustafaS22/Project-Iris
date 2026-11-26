import SwiftUI

struct IrisAvatar: View {
    let state: IrisState
    let color: Color
    var size: CGFloat = 40
    var animated = false
    var desktop = false
    var isWriting = false
    var guidance: CGSize?
    var movement: CGSize?
    var followsCursorAnywhere = false
    @StateObject private var pointer = AvatarPointerProbe()
    @State private var motion: AvatarMotion
    @State private var visible = false
    @State private var attention = 0.0
    @State private var glanceStarted: TimeInterval?
    @Environment(\.irisReduceMotion) private var systemReduceMotion
    @AppStorage("IrisReduceMotion") private var appReduceMotion = false
    private var reduceMotion: Bool { systemReduceMotion || appReduceMotion }

    init(state: IrisState, color: Color, size: CGFloat = 40, animated: Bool = false, desktop: Bool = false, isWriting: Bool = false, guidance: CGSize? = nil, movement: CGSize? = nil, followsCursorAnywhere: Bool = false) {
        self.state = state; self.color = color; self.size = size
        self.animated = animated; self.desktop = desktop; self.isWriting = isWriting
        self.guidance = guidance; self.movement = movement; self.followsCursorAnywhere = followsCursorAnywhere
        _motion = State(initialValue: AvatarMotion(state: state, at: ProcessInfo.processInfo.systemUptime))
    }
    private var watchesWriting: Bool { animated && desktop && isWriting && visible && !reduceMotion }
    var body: some View {
        Group {
            if animated && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !visible)) { _ in
                    let time = ProcessInfo.processInfo.systemUptime
                    let pose = motion.pose(at: time, glanceStarted: glanceStarted)
                    IrisAvatarFace(pose: pointer.following(pose, at: time, size: size, enabled: visible && state != .sleeping && state != .dormant, guidance: movement ?? guidance, followsCursorAnywhere: followsCursorAnywhere), color: color, size: size, desktop: desktop, attention: attention, pulse: 0.88 + 0.12 * sin(time * 3))
                }
            } else { IrisAvatarFace(pose: motion.pose(at: ProcessInfo.processInfo.systemUptime, reducedMotion: true), color: color, size: size, desktop: desktop, attention: attention) }
        }
        .background { if animated && !reduceMotion { AvatarPointerAnchor(probe: pointer).allowsHitTesting(false).accessibilityHidden(true) } }
        .accessibilityElement(children: .ignore).accessibilityLabel("Iris · \(state.label)")
        .onAppear { visible = true; attention = state == .permission ? 1 : 0 }
        .onDisappear { visible = false }
        .onChange(of: state) { _, value in
            motion.transition(to: value, at: ProcessInfo.processInfo.systemUptime, glanceStarted: glanceStarted)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) { attention = value == .permission ? 1 : 0 }
        }
        .task(id: watchesWriting) {
            guard watchesWriting else { return }
            do {
                var first = true
                while !Task.isCancelled {
                    let interval = AvatarMotion.glanceInterval(unitRandom: Double.random(in: 0...1), first: first)
                    first = false
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    try Task.checkCancellation()
                    glanceStarted = ProcessInfo.processInfo.systemUptime
                }
            } catch { /* View removal, Reduce Motion or the end of writing cancels this schedule. */ }
        }
    }
}

/// Stateless rendering shared by the live avatar and visual verification.
struct IrisAvatarFace: View, Animatable {
    let pose: AvatarPose
    let color: Color
    let size: CGFloat
    var desktop = false
    var attention = 0.0
    var pulse = 1.0
    var animatableData: Double { get { attention } set { attention = newValue } }
    var body: some View {
        ZStack {
            if desktop { RoundedRectangle(cornerRadius: size * 0.5, style: .continuous).fill(.black) }
            Canvas { context, canvas in
                for left in [true, false] {
                    let width = size * 0.20
                    let openness = left ? pose.leftOpen : pose.rightOpen
                    let height = max(size * 0.025, size * 0.35 * openness)
                    let centerX = canvas.width / 2 + (left ? -1 : 1) * size * 0.18 + size * pose.gazeX
                    let centerY = canvas.height / 2 + size * pose.gazeY
                    let rect = CGRect(x: centerX - width / 2, y: centerY - height / 2, width: width, height: height)
                    var eye = context
                    // The inward-sloping lid is a real angry expression, rather than rotated capsules.
                    if pose.anger > 0 {
                        let cut = height * 0.20 * pose.anger
                        let outerY = rect.minY
                        var mask = Path()
                        mask.move(to: CGPoint(x: rect.minX, y: outerY + (left ? 0 : cut)))
                        mask.addLine(to: CGPoint(x: rect.maxX, y: outerY + (left ? cut : 0)))
                        mask.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                        mask.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); mask.closeSubpath()
                        eye.clip(to: mask)
                    }
                    eye.fill(eyeShape(in: rect, openness: openness, smile: pose.happiness), with: .color(color.opacity(1 - attention)))
                    if attention > 0 {
                        let markWidth = size * 0.115
                        let stem = CGRect(x: centerX - markWidth / 2, y: centerY - size * 0.215, width: markWidth, height: size * 0.26)
                        let dot = CGRect(x: stem.minX, y: centerY + size * 0.105, width: markWidth, height: markWidth)
                        let ink = GraphicsContext.Shading.color(color.opacity(attention * pulse))
                        context.fill(Path(roundedRect: stem, cornerRadius: markWidth / 2), with: ink)
                        context.fill(Path(ellipseIn: dot), with: ink)
                    }
                }
            }
        }
        .frame(width: desktop ? size * 1.375 : size, height: desktop ? size * 1.125 : size)
        .rotationEffect(.degrees(pose.roll))
        .offset(x: pose.floatX * size, y: pose.floatY * size)
    }

    /// Squash and bend the capsule itself, so a smile never draws a second set of eyes.
    private func eyeShape(in original: CGRect, openness: Double, smile: Double) -> Path {
        guard smile > 0.0001 else {
            return Path(roundedRect: original, cornerRadius: original.width / 2)
        }
        let visible = min(1, openness / 0.7)
        let width = original.width * (1 + smile * 0.12)
        let height = max(size * 0.025, original.height * (1 - smile) + size * 0.075 * visible * smile)
        let radius = min(width, height) / 2
        let x = width / 2 - radius, y = height / 2 - radius
        let bend = size * 0.062 * smile * visible
        var path = Path()
        let centers = [CGPoint(x: x, y: y), CGPoint(x: -x, y: y), CGPoint(x: -x, y: -y), CGPoint(x: x, y: -y)]
        // Sample the straight sides too, so they bow with the rounded ends.
        var contour: [CGPoint] = []
        for (quarter, center) in centers.enumerated() {
            for step in 0...8 {
                let angle = (Double(quarter) + Double(step) / 8) * .pi / 2
                contour.append(CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            }
        }
        for index in contour.indices {
            let start = contour[index], end = contour[(index + 1) % contour.count]
            for step in 0..<4 {
                let fraction = Double(step) / 4
                let px = start.x + (end.x - start.x) * fraction
                let py = start.y + (end.y - start.y) * fraction
                let normalized = px / (width / 2)
                let point = CGPoint(x: original.midX + px, y: original.midY + py - bend * (1 - normalized * normalized))
                if index == 0 && step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
        }
        path.closeSubpath()
        return path
    }
}
