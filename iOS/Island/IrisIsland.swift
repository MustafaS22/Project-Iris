import SwiftUI
import WidgetKit
import ActivityKit

@main struct IrisIslandBundle: WidgetBundle {
    var body: some Widget { IrisIsland() }
}

struct IrisIsland: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: IrisActivity.self) { context in
            HStack(spacing: 14) {
                IrisFace(size: 42, color: IrisStyle.color(context.state.theme), animated: false)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Iris · \(context.state.phase)").font(.headline)
                    Text(context.state.message).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right").foregroundStyle(IrisStyle.color(context.state.theme))
            }.padding(18)
                .activityBackgroundTint(IrisStyle.background)
                .activitySystemActionForegroundColor(IrisStyle.color(context.state.theme))
                .widgetURL(URL(string: "iris://conversation"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) { IrisFace(size: 42, color: IrisStyle.color(context.state.theme), animated: false) }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.phase).font(.caption.weight(.semibold)).foregroundStyle(IrisStyle.color(context.state.theme))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.message).font(.subheadline)
                        Spacer()
                        Link(destination: URL(string: "iris://conversation")!) { Image(systemName: "arrow.up.right.circle.fill") }
                    }.padding(.top, 6)
                }
            } compactLeading: {
                IrisFace(size: 26, color: IrisStyle.color(context.state.theme), animated: false)
            } compactTrailing: {
                Image(systemName: context.state.phase == "Listening" ? "waveform" : context.state.phase == "Writing" ? "ellipsis" : "sparkle")
                    .foregroundStyle(IrisStyle.color(context.state.theme))
                    .accessibilityLabel(context.state.phase)
            } minimal: { IrisFace(size: 24, color: IrisStyle.color(context.state.theme), animated: false) }
            .widgetURL(URL(string: "iris://conversation"))
            .keylineTint(IrisStyle.color(context.state.theme))
        }
    }
}
