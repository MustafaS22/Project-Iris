import SwiftUI

struct WhatsAppConnectionView: View {
    @ObservedObject var connection: WhatsAppConnection
    let accent: Color
    let sharingEnabled: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Set<String> = []
    @State private var query = ""
    @State private var confirmDisconnect = false
    private var shown: [WhatsAppChat] { connection.chats.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                SourceLogo(source: .whatsapp)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your WhatsApp chats").font(.system(size: 24, weight: .semibold))
                    Text("Only the conversations you choose.").font(.callout).foregroundStyle(IrisDesign.secondary)
                }
                Spacer(); Button("Done") { dismiss() }.buttonStyle(IrisActionStyle())
            }
            if !connection.connected {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Connect WhatsApp for Mac").font(.headline)
                    Text("Open WhatsApp and sign in first. Then grant its shared data folder to list your chats. This is a local, read-only connection; it does not link a new device or send messages.")
                        .font(.callout).foregroundStyle(IrisDesign.secondary)
                    Button("Choose WhatsApp folder…") { connection.grant(); selection = connection.selected }.buttonStyle(IrisActionStyle(primary: true))
                    Text("The folder is Library → Group Containers → group.net.whatsapp.WhatsApp.shared in your home folder. macOS may require Full Disk Access for Iris; this grants system-level access, while Iris's chat selection limits what this connector imports.")
                        .font(.caption).foregroundStyle(IrisDesign.secondary)
                }.padding(24).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 16))
                Spacer()
            } else {
                HStack {
                    TextField("Find a chat", text: $query).textFieldStyle(IrisTextFieldStyle())
                    Button("Reload list") { connection.reload() }.buttonStyle(IrisActionStyle())
                }
                HStack {
                    Text("\(selection.count) of 20 chats selected").font(.caption).foregroundStyle(IrisDesign.secondary)
                    Spacer(); Button("Deselect all") { selection = [] }.buttonStyle(.plain).font(.caption)
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(shown) { chat in
                            Toggle(isOn: Binding(get: { selection.contains(chat.id) }, set: { allowed in
                                if allowed { if selection.count < 20 { selection.insert(chat.id) } } else { selection.remove(chat.id) }
                            })) {
                                Label(chat.name, systemImage: "bubble.left.and.bubble.right")
                                    .font(.system(size: 14)).lineLimit(2)
                            }.toggleStyle(.checkbox).padding(.vertical, 13)
                                .disabled(!selection.contains(chat.id) && selection.count >= 20)
                            Divider()
                        }
                        if shown.isEmpty { Text(connection.chats.isEmpty ? "No available chats. Let WhatsApp sync, then reload." : "No matching chats.").font(.callout).foregroundStyle(IrisDesign.secondary).padding(.vertical, 32) }
                    }.padding(.horizontal, 4)
                }.frame(minHeight: 120, maxHeight: .infinity)
                Text("Save imports up to 400 recent text messages per selected chat, within the knowledge text limit. Media isn't imported. Deselecting a chat and saving removes its local Iris copy. Refresh is manual; new chats are never selected automatically.")
                    .font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Disconnect…") { confirmDisconnect = true }.buttonStyle(.plain)
                    Spacer()
                    Button(selection == connection.selected ? "Refresh selected chats" : "Save chat selection") { connection.save(selection) }
                        .buttonStyle(IrisActionStyle(primary: true)).disabled(connection.busy)
                }
            }
            if let error = connection.error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            if !connection.status.isEmpty { Text(connection.status).font(.caption).foregroundStyle(IrisDesign.secondary) }
            Label(sharingEnabled && connection.connected ? "AI use is on. Relevant excerpts from the chats you select may be sent to your chosen AI provider. Turn off Use in answers in Connections to keep them local." : "Imported chats stay local. Turn on Use in answers in Connections only if you want relevant excerpts sent to your selected AI provider.", systemImage: "lock.shield")
                .font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
        }.padding(28).frame(width: 660, height: 720)
            .background(IrisBackdrop(accent: accent)).foregroundStyle(IrisDesign.text).tint(accent).preferredColorScheme(.dark)
            .onAppear { if connection.connected { connection.reload() }; selection = connection.selected }
            .alert("Disconnect WhatsApp?", isPresented: $confirmDisconnect) {
                Button("Cancel", role: .cancel) {}
                Button("Disconnect", role: .destructive) { connection.disconnect(); selection = connection.selected }
            } message: { Text("Removes the folder grant, chosen chats, and imported WhatsApp text from Iris. Your WhatsApp conversations are unchanged.") }
    }
}
