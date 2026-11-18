import SwiftUI

struct ChatHistoryView: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var query = ""
    @State private var deleting: ChatConversation?
    private var conversations: [ChatConversation] {
        (iris.data.conversations ?? []).filter {
            query.isEmpty || $0.messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
        }.sorted { $0.updatedAt > $1.updatedAt }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Chat history").font(.system(size: 30, weight: .semibold))
                    Text("Saved on this Mac. Open a conversation to continue it.").foregroundStyle(IrisDesign.secondary)
                }
                Spacer()
                Button("New chat", systemImage: "square.and.pencil") { iris.newConversation() }.buttonStyle(IrisActionStyle(primary: true))
            }
            TextField("Search conversations", text: $query).textFieldStyle(IrisTextFieldStyle())
            if conversations.isEmpty {
                ContentUnavailableView(query.isEmpty ? "Your conversations belong here" : "No matching chats", systemImage: "bubble.left.and.bubble.right", description: Text(query.isEmpty ? "Your next conversation will save automatically." : "Try another word from a conversation."))
            }
            ForEach(conversations) { conversation in
                HStack(spacing: 16) {
                    Button { iris.openConversation(conversation) } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "bubble.left").irisSymbolStyle().font(.system(size: 22)).foregroundStyle(iris.accent)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(conversation.sidebarTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                                Text(ResponsePresentation.visibleText(conversation.messages.last?.text ?? "").components(separatedBy: "```iris-study")[0]).font(.system(size: 12)).foregroundStyle(IrisDesign.secondary).lineLimit(2)
                                Text(conversation.updatedAt, format: .dateTime.month().day().hour().minute()).font(.caption).foregroundStyle(IrisDesign.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").irisSymbolStyle().foregroundStyle(IrisDesign.secondary)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain)
                    Button { deleting = conversation } label: { Image(systemName: "trash").irisSymbolStyle().frame(width: 32, height: 32) }.buttonStyle(.plain).help("Delete conversation").accessibilityLabel("Delete \(conversation.title)")
                }.padding(20).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .alert("Delete this conversation?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) { if let deleting { iris.deleteConversation(deleting.id) }; deleting = nil }
        } message: { Text("This removes the saved messages from this Mac.") }
    }
}
