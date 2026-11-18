import SwiftUI

/// One face stays mounted as the input capsule folds into the full floating avatar.
struct FloatingTypingBar: View {
    @Binding var text: String
    let expanded: Bool
    let width: CGFloat
    let state: IrisState
    let accent: Color
    let shortcuts: IrisShortcutStore
    let enabled: Bool
    var submit: () -> Void
    var dismiss: () -> Void
    @FocusState private var focused: Bool
    @Environment(\.irisReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            IrisAvatar(state: state == .sleeping ? .idle : state, color: accent,
                       size: 64, animated: true, desktop: true,
                       isWriting: !expanded)
                .scaleEffect(expanded ? 30.0 / 64.0 : 1)
                .modifier(FloatingAvatarShadow(accent: accent, enabled: !expanded))
                .frame(width: expanded ? 54 : 148, height: expanded ? 60 : 108)
            if expanded {
                TextField(enabled ? "Ask Iris…" : "Iris is working…", text: $text)
                    .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(IrisDesign.text)
                    .focused($focused).disabled(!enabled).onSubmit(submit)
                    .accessibilityLabel("Question for floating Iris")
                    .transition(.opacity)
                Button(action: submit) {
                    Image(systemName: "arrow.up").irisSymbolStyle().font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(Color.black).background(accent, in: Circle())
                }.buttonStyle(.plain).padding(.leading, 10).padding(.trailing, 12)
                    .disabled(!enabled || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(enabled && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 1 : 0.35)
                    .accessibilityLabel("Send question").transition(.opacity)
            }
        }
        .frame(width: expanded ? width : 148, height: expanded ? 60 : 108)
        .background {
            Capsule().fill(IrisDesign.surface.opacity(expanded ? 0.98 : 0))
                .overlay(Capsule().strokeBorder(accent.opacity(expanded ? 0.28 : 0), lineWidth: 1))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .preferredColorScheme(.dark).allowsHitTesting(expanded)
        .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.88), value: expanded)
        .onChange(of: expanded) { _, value in focused = value }
        .onAppear { focused = expanded }
        .background(IrisDismissShortcut(shortcuts: shortcuts, action: dismiss).frame(width: 0, height: 0))
    }
}
