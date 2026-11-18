import SwiftUI

/// One composer for desktop and notch. Mentions are explicit, per-message choices.
struct ChatMentionComposer: View {
    @ObservedObject var iris: IrisOrchestrator
    var compact = false
    @State private var selected = 0
    @State private var dismissed: String?
    @State private var focused = false
    private var query: String? { dismissed == iris.draft ? nil : ChatMentions.query(in: iris.draft) }
    private var options: [ChatMentionOption] {
        guard let query else { return [] }
        let connected = ChatMentions.sources.filter { option in
            guard let source = option.connector else { return false }
            return !query.isEmpty || iris.knowledge.enabled.contains(source.rawValue) && iris.knowledge.documents.contains { $0.source == source }
        }
        return Array((Array(ChatMentions.tools.prefix(4)) + connected + Array(ChatMentions.tools.dropFirst(4))).filter { query.isEmpty || $0.token.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query) }.prefix(compact ? 4 : 7))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if query != nil {
                VStack(alignment: .leading, spacing: 3) {
                    HStack { Text("Sources & tools").font(.system(size: 11, weight: .semibold)); Spacer(); Text("↑ ↓ to choose · Return to add").font(.system(size: 10)).foregroundStyle(IrisDesign.secondary) }.padding(.horizontal, 10).padding(.vertical, 7)
                    if options.isEmpty { Text("No match. Try @agent, @website, @document, or a source name.").font(.caption).foregroundStyle(IrisDesign.secondary).padding(10) }
                    ScrollViewReader { proxy in
                        ScrollView { VStack(spacing: 3) {
                    ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                        Button { apply(option) } label: {
                            HStack(spacing: 10) {
                                if let source = option.connector { SourceLogo(source: source, size: 23, showsBackground: false) }
                                else { Image(systemName: option.symbol).irisSymbolStyle().font(.system(size: 19, weight: .semibold)).foregroundStyle(iris.accent).frame(width: 23) }
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack { Text(option.title).font(.system(size: 12, weight: .medium)); Text("@" + option.token).font(.system(size: 10)).foregroundStyle(IrisDesign.secondary) }
                                    Text(detail(option)).font(.system(size: 10)).foregroundStyle(IrisDesign.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "return").font(.system(size: 10)).foregroundStyle(IrisDesign.secondary).opacity(selected == index ? 1 : 0)
                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(selected == index ? iris.accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 9)).contentShape(Rectangle())
                        }.buttonStyle(.plain).onHover { if $0 { selected = index } }.id(index)
                    }
                        } }.frame(height: CGFloat(min(options.count, compact ? 3 : 4)) * 52)
                            .onChange(of: selected) { _, index in proxy.scrollTo(index, anchor: .center) }
                    }

                }.padding(6).background(IrisDesign.canvas, in: RoundedRectangle(cornerRadius: 13)).overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(iris.accent.opacity(0.2)))
            }
            AttachmentTray(iris: iris)
            MentionTextEditor(text: $iris.draft, focused: $focused, accent: iris.accent, compact: compact, onCommand: { command in
                switch command {
                case .submit:
                    if query != nil, options.indices.contains(selected) { apply(options[selected]) } else { iris.ask() }
                    return true
                case .down:
                    guard query != nil, !options.isEmpty else { return false }
                    selected = (selected + 1) % options.count; return true
                case .up:
                    guard query != nil, !options.isEmpty else { return false }
                    selected = (selected - 1 + options.count) % options.count; return true
                case .escape:
                    guard query != nil else { return false }
                    dismissed = iris.draft; return true
                }
            }, onFiles: {urls in
                guard !iris.busy,!iris.contextBusy else{iris.error="Finish the current task before attaching files.";return false}
                iris.attachFiles(urls);return true
            }, onData: {data,ext in iris.attachClipboardData(data,extension:ext)},onAttachmentError:{iris.error=$0}).onChange(of: query) { _, _ in selected = 0 }
            HStack(spacing: 12) {
                Button { iris.chooseFile() } label: { Image(systemName: "paperclip").irisSymbolStyle().frame(width: 28, height: 28) }.help("Attach files").disabled(iris.contextBusy || iris.busy)
                Button { if !iris.draft.isEmpty && iris.draft.last?.isWhitespace != true { iris.draft += " " }; iris.draft += "@"; dismissed = nil; focused = true } label: { Image(systemName: "at").font(.system(size: 16, weight: .medium)).frame(width: 28, height: 28) }.help("Choose a source or tool").accessibilityLabel("Choose a source or tool")
                Button { iris.toggleVoice() } label: { Image(systemName: iris.voice.listening ? "stop.fill" : "waveform").irisSymbolStyle().frame(width: 28, height: 28) }.help(iris.voice.listening ? "Stop microphone" : "Speak to Iris")
                if iris.voice.speaking || iris.voice.preparingSpeech { Button { iris.voice.stopSpeaking() } label: { Image(systemName: "speaker.slash").frame(width: 28, height: 28) }.help("Stop voice") }
                Spacer(minLength: 0)
                if !compact { Text(iris.preferences.source.rawValue).font(.system(size: 10)).foregroundStyle(IrisDesign.secondary) }
                Button { iris.busy ? iris.cancelModel() : iris.ask() } label: {
                    Image(systemName: iris.busy ? "stop.fill" : "arrow.up").font(.system(size: 14, weight: .semibold)).frame(width: 32, height: 32).foregroundStyle(iris.canSend || iris.busy ? Color.black : IrisDesign.secondary).background(iris.canSend || iris.busy ? iris.accent : IrisDesign.control, in: Circle())
                }.disabled(!iris.busy && !iris.canSend).help(iris.busy ? "Stop" : "Send").accessibilityLabel(iris.busy ? "Stop response" : "Send message")
            }.buttonStyle(.plain)
        }.padding(compact ? 13 : 16).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(focused ? iris.accent.opacity(0.45) : .white.opacity(0.12)))
            .contextMenu { Button("Paste image or files") { iris.pasteAttachment() }.disabled(iris.contextBusy || iris.busy) }
    }
    private func detail(_ option: ChatMentionOption) -> String {
        guard let source = option.connector else { return option.detail }
        guard iris.knowledge.enabled.contains(source.rawValue), iris.knowledge.documents.contains(where: { $0.source == source }) else { return "Set up in Knowledge → Connections" }
        return "\(iris.knowledge.documents.filter { $0.source == source }.count) imported items · this message only"
    }
    private func apply(_ option: ChatMentionOption) {
        if let source = option.connector, !iris.knowledge.enabled.contains(source.rawValue) || !iris.knowledge.documents.contains(where: { $0.source == source }) { iris.showWorkspace(.connections); return }
        iris.draft = ChatMentions.completing(option.token, in: iris.draft); focused = true
    }
}
