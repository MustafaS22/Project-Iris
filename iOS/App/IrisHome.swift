import SwiftUI

struct IrisHome: View {
    @ObservedObject var session: IrisSession
    @FocusState private var typing: Bool
    @AppStorage("IrisTheme") private var theme = "Gold"
    @AppStorage("IrisName") private var name = ""
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            if session.messages.isEmpty { welcome }
                            ForEach(session.messages) { message in
                                HStack(alignment: .top, spacing: 12) {
                                    if message.role == "assistant" { IrisFace(size: 25, active: session.busy, animated: false) }
                                    if message.role == "user" { Spacer(minLength: 36) }
                                    if message.text.isEmpty {
                                        HStack(spacing: 10) { ProgressView(); Text("Preparing your answer…").font(.subheadline).foregroundStyle(.secondary) }
                                    } else {
                                        Text(.init(message.text)).textSelection(.enabled)
                                            .font(.system(size: 17)).lineSpacing(4)
                                            .padding(message.role == "user" ? 16 : 0)
                                            .background(message.role == "user" ? IrisStyle.surface : .clear, in: RoundedRectangle(cornerRadius: 20))
                                    }
                                    if message.role == "assistant" { Spacer(minLength: 0) }
                                }.id(message.id)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }.padding(24)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: session.messages.last?.text) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
                    .onChange(of: session.messages.count) { _, _ in withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) } }
                }
                if let error = session.error {
                    HStack(alignment: .top) {
                        Image(systemName: "exclamationmark.circle.fill").foregroundStyle(IrisStyle.accent)
                        Text(error).font(.caption)
                        Spacer()
                        Button { session.error = nil } label: { Image(systemName: "xmark").padding(6) }.accessibilityLabel("Dismiss message")
                    }.padding(.horizontal, 24).padding(.vertical, 12)
                }
                composer
            }
            .background(LinearGradient(colors: [IrisStyle.background, Color(red: 0.10, green: 0.095, blue: 0.075)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
            .navigationTitle("Iris")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { session.newConversation() } label: { Image(systemName: "square.and.pencil") }.accessibilityLabel("New conversation")
                        .disabled(session.busy || session.listening)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { session.showSettings = true } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("Iris settings")
                }
            }
            .sheet(isPresented: $session.showSettings) { IrisSettings(session: session) }
            .onAppear { if IrisKey.read(UserDefaults.standard.string(forKey: "IrisProvider") ?? "gemini").isEmpty { session.showSettings = true } }
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { Spacer(); IrisFace(size: 104); Spacer() }.padding(.top, 36).padding(.bottom, 8)
            Text(name.isEmpty ? "Here when\nyou need me." : "Hey, \(name).\nWhat’s on your mind?")
                .font(.system(size: 36, weight: .semibold)).tracking(-1.3)
            Text("A thought, a plan, a little help.\nYour companion, now on iPhone.")
                .font(.system(size: 17)).foregroundStyle(.secondary).lineSpacing(4)
            VStack(spacing: 0) {
                suggestion("Find the right words", symbol: "text.bubble.fill", prompt: "Help me write a message. Ask me who it is for and what I want to say.")
                Divider().padding(.leading, 48)
                suggestion("Untangle an idea", symbol: "sparkles", prompt: "Help me work through an idea. Ask me what I’m thinking about.")
                Divider().padding(.leading, 48)
                suggestion("Make a plan", symbol: "sun.max.fill", prompt: "Help me plan my day. Ask about my priorities and available time.")
            }.padding(.horizontal, 16).background(IrisStyle.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 22))
            Label("Quiet in the Island until you call.", systemImage: "moon.fill")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func suggestion(_ title: String, symbol: String, prompt: String) -> some View {
        Button { session.input = prompt; typing = true } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).foregroundStyle(IrisStyle.accent).frame(width: 24)
                Text(title).foregroundStyle(.primary)
                Spacer(); Image(systemName: "arrow.up.left").font(.caption).foregroundStyle(.secondary)
            }.padding(.vertical, 18)
        }.buttonStyle(.plain)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            if session.listening { Label("Listening · pause to send", systemImage: "waveform").font(.caption).foregroundStyle(IrisStyle.accent) }
            HStack(alignment: .bottom, spacing: 12) {
                Button {
                    typing = false
                    if session.listening { session.finishVoice() } else { session.summon() }
                } label: {
                    Image(systemName: session.listening ? "stop.circle.fill" : "mic.fill")
                        .font(.system(size: 20, weight: .semibold)).frame(width: 44, height: 44)
                }.accessibilityLabel(session.listening ? "Finish voice question" : "Speak to Iris").disabled(session.busy)
                TextField("Ask Iris…", text: $session.input, axis: .vertical)
                    .lineLimit(1...5).focused($typing).padding(.vertical, 11)
                    .disabled(session.busy || session.listening)
                Button {
                    typing = false
                    if session.busy || session.phase == "Speaking" { session.stop() } else { session.send() }
                } label: {
                    Image(systemName: session.busy || session.phase == "Speaking" ? "stop.fill" : "arrow.up")
                        .font(.system(size: 17, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 44, height: 44).background(IrisStyle.accent, in: Circle())
                }.accessibilityLabel(session.busy || session.phase == "Speaking" ? "Stop Iris" : "Send question")
                    .disabled(!session.busy && session.phase != "Speaking" && session.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(8).background(IrisStyle.surface, in: RoundedRectangle(cornerRadius: 26))
            HStack {
                Text(session.phase == "Ready" ? "IRIS · BY ARIZE" : session.phase.uppercased())
                Spacer()
                Text("iPhone preview 1.1")
            }.font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1).foregroundStyle(.secondary)
        }.padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 8)
    }
}

