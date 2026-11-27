import SwiftUI

struct LiveResponseView: View {
    @ObservedObject var iris: IrisOrchestrator
    var fontSize: CGFloat = 15

    var body: some View {
        Group {
            if let kind = iris.activeCreation {
                GenerationProgressCard(kind: kind, accent: iris.accent, phase: iris.requestPhase, stop: iris.cancelModel)
            } else {
                streamingResponse
            }
        }
        .id("live-response")
    }

    private var streamingResponse: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !iris.liveReply.isEmpty {
                FormattedResponse(text: iris.liveReply, fontSize: fontSize)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 16))
            }
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text(iris.requestPhase).font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text("\(max(0, Int(timeline.date.timeIntervalSince(iris.requestStarted))))s").font(.system(size: 11).monospacedDigit()).foregroundStyle(IrisDesign.secondary)
                }
            }
            if !iris.liveReply.isEmpty { Text("Answer in progress").font(.system(size: 10)).foregroundStyle(IrisDesign.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}


private struct GenerationProgressCard: View {
    let kind: ChatCreationKind
    let accent: Color
    let phase: String
    let stop: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var title: String {
        switch kind {
        case .image: "Generating image"
        case .document: "Creating document"
        case .website: "Building website"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 18)
        VStack(spacing: 0) {
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { frame in
                let time = reduceMotion ? 0 : frame.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 40 * .pi)
                GenerationTileField(accent: accent, time: time)
            }
            .frame(height: kind == .image ? 220 : 132)
            .background(accent.opacity(0.035))
            .accessibilityHidden(true)

            HStack(spacing: 10) {
                Image(systemName: kind.symbol)
                    .foregroundStyle(accent)
                    .accessibilityHidden(true)
                Text(phase == "Saving to Library" ? phase : title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                Button("Stop", action: stop)
                    .buttonStyle(.plain)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.07), in: Capsule())
                    .accessibilityLabel("Stop " + title.lowercased())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(IrisDesign.surface)
        }
        .frame(maxWidth: 510)
        .background(IrisDesign.canvas)
        .clipShape(shape)
        .overlay { shape.strokeBorder(accent.opacity(0.19)).allowsHitTesting(false) }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GenerationTileField: View {
    let accent: Color
    let time: Double

    var body: some View {
        Canvas { context, size in
            let spacing = 15.0
            let columns = max(1, Int((size.width - 14) / spacing))
            let rows = max(1, Int((size.height - 12) / spacing))
            let origin = CGPoint(
                x: (size.width - Double(columns - 1) * spacing) / 2,
                y: (size.height - Double(rows - 1) * spacing) / 2
            )
            let first = CGPoint(x: cos(time * 1.1) * 0.53, y: sin(time * 0.8) * 0.48)
            let second = CGPoint(x: sin(time * 0.7 + 1.4) * 0.60, y: cos(time * 1.2) * 0.54)

            for row in 0..<rows {
                let y = Double(row) / Double(max(1, rows - 1)) * 2 - 1
                for column in 0..<columns {
                    let x = Double(column) / Double(max(1, columns - 1)) * 2 - 1
                    let near = max(0, 1 - hypot(x - first.x, y - first.y) * 0.93)
                    let far = max(0, 1 - hypot(x - second.x, y - second.y) * 1.1)
                    let ripple = (sin(x * 5 + y * 4 - time * 3) + 1) / 2
                    let light = min(1, max(near, far * 0.82) * (0.42 + ripple * 0.72))
                    let edge = 1 - 0.30 * max(abs(x), abs(y))
                    let width = 2.6 + 6.4 * light
                    let center = CGPoint(
                        x: origin.x + Double(column) * spacing + sin(y * 4 + time * 2) * light * 1.7,
                        y: origin.y + Double(row) * spacing + cos(x * 4 - time * 2) * light * 1.7
                    )
                    let tile = CGRect(x: center.x - width / 2, y: center.y - width / 2, width: width, height: width)
                    context.fill(Path(roundedRect: tile, cornerRadius: 0.7), with: .color(accent.opacity((0.19 + light * 0.81) * edge)))
                }
            }
        }
    }
}
