import SwiftUI

struct OnboardingGuideView: View {
    let guidance: OnboardingGuidance
    let accent: Color
    let state: IrisState
    let gaze: CGSize?
    var reveal: () -> Void
    var accept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            IrisAvatar(state: state, color: accent, size: 68, animated: true, desktop: true,
                       guidance: gaze, followsCursorAnywhere: guidance.target == nil)
                .onboardingAnchor("guide-face")
                .frame(maxWidth: .infinity).padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 8) {
                Text(guidance.title).font(.system(size: 18, weight: .semibold)).foregroundStyle(IrisDesign.text)
                Text(guidance.detail).font(.system(size: 12)).lineSpacing(3)
                    .foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if guidance.target != nil {
                HStack {
                    Button("Show me", systemImage: "arrow.up.right") { reveal() }
                        .buttonStyle(.plain).foregroundStyle(accent).font(.system(size: 12, weight: .medium))
                    Spacer(minLength: 0)
                }
            }
            if let label = guidance.acceptLabel {
                Button(label, action: accept).buttonStyle(.plain)
                    .font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                    .padding(.vertical, 4)
            }
        }
    }
}

struct OnboardingFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension View {
    func onboardingAnchor(_ id: String) -> some View {
        background(GeometryReader { geometry in
            Color.clear.preference(key: OnboardingFrameKey.self, value: [id: geometry.frame(in: .named("onboarding"))])
        })
    }
    func onboardingTask(_ target: OnboardingGuidance.Target, current: OnboardingGuidance.Target?, accent: Color) -> some View {
        self.onboardingAnchor(target.rawValue).id(target.rawValue)
            .overlay {
                if target == current {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(accent.opacity(0.7), lineWidth: 1)
                        .padding(-6).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
    }
}
