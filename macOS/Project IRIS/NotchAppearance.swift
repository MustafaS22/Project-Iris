import SwiftUI

/// The upper corners flare out into the display edge; the body keeps its existing width.
struct IrisNotchShape: Shape {
    static let shoulder: CGFloat = 10
    var shoulderRadius: CGFloat = Self.shoulder
    var bottomRadius: CGFloat = 26
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(shoulderRadius, bottomRadius) }
        set { shoulderRadius = newValue.first; bottomRadius = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let r = min(max(0, shoulderRadius), rect.width / 4, rect.height / 2)
        let b = min(max(0, bottomRadius), (rect.width - 2 * r) / 2, rect.height / 2)
        let left = rect.minX + r, right = rect.maxX - r, top = rect.minY, bottom = rect.maxY
        let k: CGFloat = 0.55228475
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: top))
        path.addLine(to: CGPoint(x: rect.maxX, y: top))
        path.addCurve(to: CGPoint(x: right, y: top + r), control1: CGPoint(x: rect.maxX - k * r, y: top), control2: CGPoint(x: right, y: top + r * (1 - k)))
        path.addLine(to: CGPoint(x: right, y: bottom - b))
        path.addQuadCurve(to: CGPoint(x: right - b, y: bottom), control: CGPoint(x: right, y: bottom))
        path.addLine(to: CGPoint(x: left + b, y: bottom))
        path.addQuadCurve(to: CGPoint(x: left, y: bottom - b), control: CGPoint(x: left, y: bottom))
        path.addLine(to: CGPoint(x: left, y: top + r))
        path.addCurve(to: CGPoint(x: rect.minX, y: top), control1: CGPoint(x: left, y: top + r * (1 - k)), control2: CGPoint(x: rect.minX + k * r, y: top))
        path.closeSubpath()
        return path
    }
}
struct IrisNotchBackground: View {
    var expanded: Bool
    var accent: Color
    var body: some View {
        ZStack {
            Color.black
            if expanded {
                EllipticalGradient(stops: [
                    .init(color: .black, location: 0),
                    .init(color: .black, location: 0.23),
                    .init(color: accent.opacity(0.025), location: 0.48),
                    .init(color: accent.opacity(0.065), location: 0.80),
                    .init(color: accent.opacity(0.10), location: 1)
                ], center: .top, startRadiusFraction: 0, endRadiusFraction: 1)
                .transition(.opacity)
            }
        }.allowsHitTesting(false)
    }
}

/// Uses the same path as the notch fill and hit region. The even-odd mask removes all interior light.
struct IrisNotchComputerGlow: View, Animatable {
    static let margin: CGFloat = 14
    var shape: IrisNotchShape
    let phase: ComputerUsePresentation
    let accent: Color
    @Environment(\.irisReduceMotion) private var reduceMotion

    var animatableData: IrisNotchShape.AnimatableData {
        get { shape.animatableData }
        set { shape.animatableData = newValue }
    }

    var body: some View {
        let strength: Double = switch phase {
        case .executing: 0.84
        case .waiting: 0.50
        case .paused: 0.25
        default: 0
        }
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || phase != .executing)) { clock in
            let cycle = clock.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 6.8)
            let breath = reduceMotion || phase != .executing ? 0.93 : 0.90 + 0.10 * cos(cycle * 2 * .pi / 6.8)
            Canvas { context, size in
                let canvas = CGRect(origin: .zero, size: size)
                let body = canvas.insetBy(dx: Self.margin, dy: Self.margin)
                let outline = shape.path(in: body)
                var exterior = Path(canvas)
                exterior.addPath(outline)
                var outside = context
                outside.clip(to: exterior, style: .init(eoFill: true))
                outside.drawLayer { diffusion in
                    diffusion.addFilter(.blur(radius: 4.2))
                    let light = GraphicsContext.Shading.linearGradient(
                        Gradient(colors: [accent.opacity(0.30), accent.opacity(0.84)]),
                        startPoint: CGPoint(x: body.midX, y: body.minY),
                        endPoint: CGPoint(x: body.midX, y: body.maxY)
                    )
                    diffusion.stroke(outline, with: light, lineWidth: 5.3)
                }
                let edge = GraphicsContext.Shading.linearGradient(
                    Gradient(colors: [accent.opacity(0.40), accent.opacity(0.83)]),
                    startPoint: CGPoint(x: body.midX, y: body.minY),
                    endPoint: CGPoint(x: body.midX, y: body.maxY)
                )
                outside.stroke(outline, with: edge, lineWidth: 1.45)
            }
            .opacity(breath)
        }
        .padding(-Self.margin)
        .opacity(strength)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.28), value: strength)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
