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
