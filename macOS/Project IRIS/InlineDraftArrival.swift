import SwiftUI

/// Brief cursor greeting. Model work and local insertion never wait for this animation.
struct InlineDraftArrival: View {
    let color: Color
    @Environment(\.irisReduceMotion) private var reduceMotion
    @State private var began = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { timeline in
            let t = min(1, max(0, timeline.date.timeIntervalSince(began) / 0.30))
            let raw = min(1, t / 0.75)
            let orbit = raw * raw * (3 - 2 * raw)
            let settle = max(0, (t - 0.50) / 0.50)
            ZStack {
                ForEach(0..<2) { eye in
                    let angle = orbit * .pi * 2 + Double(eye) * .pi
                    let x = cos(angle) * 19 * (1 - settle) + (eye == 0 ? -5.0 : 5.0) * settle
                    let y = sin(angle) * 19 * (1 - settle)
                    Capsule().fill(color).frame(width: 6, height: 12)
                        .shadow(color: color.opacity(0.25), radius: 4)
                        .offset(x: reduceMotion ? (eye == 0 ? -5 : 5) : x, y: reduceMotion ? 0 : y)
                }
            }.frame(width: 84, height: 84)
                .opacity(reduceMotion ? 1 : t < 0.8 ? 1 : max(0, (1 - t) / 0.2))
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
