import SwiftUI

/// A small, static composition showing the actual accent roles, without running avatar timers.
struct IrisOnboardingThemeTile: View {
    let theme: IrisTheme
    let hue: Double
    let selected: Bool
    var select: () -> Void
    @State private var hovered = false
    private var accent: Color { theme.color(customHue: hue) }

    var body: some View {
        Button(action: select) {
            VStack(spacing: 0) {
                preview
                    .frame(height: 108)
                    .clipped()
                    .accessibilityHidden(true)
                HStack(spacing: 8) {
                    Text(theme.rawValue).font(.system(size: 13, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").irisSymbolStyle()
                        .foregroundStyle(selected ? accent : IrisDesign.secondary.opacity(0.6))
                }.foregroundStyle(IrisDesign.text).padding(12)
            }
            .background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? accent : .white.opacity(hovered ? 0.3 : 0.1), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .accessibilityLabel("\(theme.rawValue) theme")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help("Use \(theme.rawValue)")
    }

    private var preview: some View {
        VStack(spacing: 9) {
            HStack(spacing: 4) {
                IrisAvatar(state: .idle, color: accent, size: 14)
                Spacer()
                Image(systemName: "bubble.left").irisSymbolStyle().font(.system(size: 8)).foregroundStyle(IrisDesign.secondary)
            }
            .padding(.horizontal, 10).frame(width: 104, height: 22)
            .background(.black, in: UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9))
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    IrisBrandMark(color: accent).scaleEffect(0.6).frame(width: 16, height: 16)
                    Capsule().fill(accent.opacity(0.3)).frame(width: 26, height: 4)
                    Capsule().fill(.white.opacity(0.12)).frame(width: 21, height: 3)
                    Spacer(minLength: 0)
                }.padding(8).frame(width: 44).background(IrisDesign.sidebar)
                VStack(spacing: 6) {
                    IrisAvatar(state: .idle, color: accent, size: 21)
                    HStack { Spacer(); Capsule().fill(accent.opacity(0.25)).frame(width: 40, height: 7) }
                    HStack(spacing: 4) {
                        Capsule().fill(.white.opacity(0.13)).frame(height: 3)
                        Image(systemName: "arrow.up.circle.fill").irisSymbolStyle().font(.system(size: 10)).foregroundStyle(accent)
                    }.padding(5).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 5))
                }.padding(8).frame(maxWidth: .infinity)
            }
            .frame(height: 72)
            .background(IrisDesign.canvas)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 5)
        .background(LinearGradient(colors: [accent.opacity(0.12), IrisDesign.canvas], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
    }
}
