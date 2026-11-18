import SwiftUI

extension ChatConversation {
    /// Display-only cleanup. The original request, mentions and saved messages remain intact.
    var sidebarTitle: String {
        let original = messages.first(where: { $0.role == "user" })?.text ?? ""
        let text = (try? ChatMentions.parse(original))?.text ?? original
        let compact = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return compact.isEmpty ? "Untitled conversation" : String(compact.prefix(100))
    }
}

struct RecentChatRow: View {
    let title: String
    let selected: Bool
    let accent: Color
    var action: () -> Void
    @State private var hovered = false
    @Environment(\.irisReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: selected ? "bubble.left.fill" : "bubble.left")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(selected ? accent : IrisDesign.secondary.opacity(0.65))
                    .frame(width: 16)
                Text(title).font(.system(size: 12, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected || hovered ? IrisDesign.text : IrisDesign.secondary)
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(.horizontal, 12).frame(height: 34)
                .background(selected ? accent.opacity(0.10) : hovered ? Color.white.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain).onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            .help(title).accessibilityLabel(title).accessibilityAddTraits(selected ? .isSelected : [])
    }
}
