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
    static let margin: CGFloat = 10
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
        case .executing: 0.82
        case .waiting: 0.43
        case .paused: 0.22
        default: 0
        }
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || phase != .executing)) { clock in
            let cycle = clock.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 5.8)
            let breath = reduceMotion || phase != .executing ? 0.93 : 0.87 + 0.13 * cos(cycle * 2 * .pi / 5.8)
            Canvas { context, size in
                let canvas = CGRect(origin: .zero, size: size)
                let outline = shape.path(in: canvas.insetBy(dx: Self.margin, dy: Self.margin))
                var exterior = Path(canvas)
                exterior.addPath(outline)
                var outside = context
                outside.clip(to: exterior, style: .init(eoFill: true))
                outside.drawLayer { diffusion in
                    diffusion.addFilter(.blur(radius: 3.3))
                    diffusion.stroke(outline, with: .color(accent.opacity(0.68)), lineWidth: 3.1)
                }
                outside.stroke(outline, with: .color(accent), lineWidth: 1.9)
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
