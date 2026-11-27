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
    @State private var sweep = false

    private var title: String {
        switch kind {
        case .image: "Generating image"
        case .document: "Creating document"
        case .website: "Building website"
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 16)
        HStack(spacing: 12) {
            Image(systemName: kind.symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(accent)
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(phase == "Saving to Library" ? phase : "In progress")
                    .font(.caption).foregroundStyle(IrisDesign.secondary)
            }
            Spacer(minLength: 8)
            Button("Stop", action: stop)
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .accessibilityLabel("Stop " + title.lowercased())
        }
        .padding(14)
        .background {
            shape.fill(IrisDesign.surface)
            if !reduceMotion {
                GeometryReader { geometry in
                    LinearGradient(colors: [.clear, accent.opacity(0.15), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: geometry.size.width * 0.55)
                        .offset(x: geometry.size.width * (sweep ? 1 : -0.55))
                }
                .clipShape(shape)
                .allowsHitTesting(false)
            }
        }
        .overlay { shape.strokeBorder(accent.opacity(0.24)).allowsHitTesting(false) }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.65).repeatForever(autoreverses: false)) { sweep = true }
        }
    }
}
