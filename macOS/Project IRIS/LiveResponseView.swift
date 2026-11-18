import SwiftUI

struct LiveResponseView: View {
    @ObservedObject var iris: IrisOrchestrator
    var fontSize: CGFloat = 15
    var body: some View {
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
        }.frame(maxWidth: .infinity, alignment: .leading).id("live-response")
    }
}
