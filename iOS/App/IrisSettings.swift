import SwiftUI
import AppIntents

struct IrisSettings: View {
    @ObservedObject var session: IrisSession
    @Environment(\.dismiss) private var dismiss
    @AppStorage("IrisName") private var name = ""
    @AppStorage("IrisTheme") private var theme = "Gold"
    @AppStorage("IrisProvider") private var provider = "gemini"
    @AppStorage("IrisModel") private var geminiModel = "gemini-3.8-flash"
    @AppStorage("IrisOpenAIModel") private var openAIModel = "gpt-6-luna"
    @AppStorage("IrisVoiceProvider") private var voiceProvider = "phone"
    @AppStorage("IrisGeminiVoice") private var voice = "Sulafat"
    @AppStorage("IrisSpeakReplies") private var speak = false
    @State private var page = "AI"
    @State private var geminiKey = IrisKey.read()
    @State private var openAIKey = IrisKey.read("openai")
    @State private var status: String?
    @State private var preview: Task<Void, Never>?
    @State private var previewing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack(spacing: 16) {
                        IrisFace(size: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Make Iris yours.").font(.title2.weight(.semibold))
                            Text("iPhone 1.1 · by AriZe").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 20) {
                            ForEach(["AI", "Voice", "Appearance", "Connections", "Shortcuts"], id: \.self) { item in
                                Button { page = item; status = nil; preview?.cancel(); previewing = false } label: {
                                    VStack(spacing: 8) {
                                        Text(item).font(.subheadline.weight(page == item ? .semibold : .regular))
                                        Capsule().fill(page == item ? IrisStyle.accent : .clear).frame(height: 2)
                                    }.foregroundStyle(page == item ? .primary : .secondary)
                                }.buttonStyle(.plain).accessibilityAddTraits(page == item ? .isSelected : [])
                            }
                        }
                    }
                    switch page {
                    case "AI": ai
                    case "Voice": voiceSettings
                    case "Appearance": appearance
                    case "Connections": IrisConnectionsView()
                    default: shortcuts
                    }
                    if let status { Text(status).font(.caption).foregroundStyle(IrisStyle.accent) }
                }.padding(24)
            }.background(IrisStyle.background)
                .navigationTitle("Your Iris").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
                .onDisappear { preview?.cancel() }
        }.tint(IrisStyle.color(theme)).preferredColorScheme(.dark)
    }

    private var ai: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose your intelligence.").font(.title2.weight(.semibold))
            chips(["gemini", "openai"], selection: $provider, titles: ["Gemini", "OpenAI"])
            Text("API-key connections · questions and checked connection excerpts go directly to the selected provider. Keys stay in this iPhone’s Keychain. ChatGPT and Gemini app subscriptions do not automatically provide API credits.")
                .font(.subheadline).foregroundStyle(.secondary)
            if provider == "gemini" {
                keyField("Gemini API key", text: $geminiKey)
                field("Gemini model", text: $geminiModel)
                Button("Save Gemini connection") { save(geminiKey, provider: "gemini") }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                Link("Get a Gemini API key ↗", destination: URL(string: "https://aistudio.google.com/api-keys")!)
            } else {
                keyField("OpenAI API key", text: $openAIKey)
                field("OpenAI model", text: $openAIModel)
                Button("Save OpenAI connection") { save(openAIKey, provider: "openai") }.buttonStyle(.borderedProminent).foregroundStyle(.black)
                Link("OpenAI API keys ↗", destination: URL(string: "https://platform.openai.com/api-keys")!)
            }
            Text("Saving a key does not send a paid test request. Your first question checks the connection. Both provider keys can be saved; switching providers preserves them.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Account OAuth login is not enabled in this build. API-key connections were selected for now; your Mac’s login and conversations are not copied.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var voiceSettings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("A voice that feels right.").font(.title2.weight(.semibold))
            chips(["phone", "gemini"], selection: $voiceProvider, titles: ["iPhone", "Gemini voice"])
            Toggle("Read typed answers aloud", isOn: $speak)
            Text("Voice questions are always answered aloud. Gemini voice uses the saved Gemini API key independently of your chat provider.").font(.subheadline).foregroundStyle(.secondary)
            if voiceProvider == "gemini" {
                ForEach(IrisVoice.voices, id: \.self) { item in
                    Button { voice = item } label: {
                        HStack {
                            Image(systemName: "waveform").foregroundStyle(IrisStyle.accent)
                            Text(item).foregroundStyle(.primary)
                            Spacer()
                            if voice == item { Image(systemName: "checkmark.circle.fill").foregroundStyle(IrisStyle.accent) }
                        }.padding(16).background(IrisDesignSurface(selected: voice == item))
                    }.buttonStyle(.plain).accessibilityAddTraits(voice == item ? .isSelected : [])
                }
                Text("Economy mode uses Gemini Flash-Lite TTS, reads up to 900 characters, and makes at most two speech requests per reply. The first sentence can begin while the text is arriving. Previews are cached in memory; quota errors are not retried automatically.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(previewing ? "Stop preview" : "Preview selected voice") {
                if previewing { preview?.cancel(); previewing = false; return }
                previewing = true; status = nil
                preview = Task {
                    defer { previewing = false }
                    do { try await IrisVoice.shared.play("Hi, I’m Iris. Here when you need a hand.", preview: true) }
                    catch { if !(error is CancellationError) { status = error.localizedDescription } }
                }
            }.buttonStyle(.bordered).disabled(session.busy || session.listening || session.phase == "Speaking")
            Text("Microphone capture is visible and user-invoked. Speech recognition may send audio to Apple. Use Speak once in Iris to grant permissions before trying the Island voice shortcut.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 20) {
            field("Your name", text: $name)
            Text("A familiar face. Your colors.").font(.title2.weight(.semibold))
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(IrisStyle.themes, id: \.self) { item in
                    Button { theme = item } label: {
                        VStack(alignment: .leading, spacing: 15) {
                            HStack { Spacer(); IrisFace(size: 40, color: IrisStyle.color(item), animated: false); Spacer() }
                            Capsule().fill(IrisStyle.color(item).opacity(0.7)).frame(height: 6).padding(.trailing, 22)
                            Capsule().fill(.white.opacity(0.15)).frame(height: 4)
                            HStack { Text(item).font(.caption.weight(.semibold)); Spacer(); if theme == item { Image(systemName: "checkmark.circle.fill").foregroundStyle(IrisStyle.color(item)) } }
                        }.padding(16).background(IrisStyle.surface, in: RoundedRectangle(cornerRadius: 18))
                            .overlay(RoundedRectangle(cornerRadius: 18).stroke(IrisStyle.color(item).opacity(theme == item ? 0.9 : 0.15), lineWidth: theme == item ? 2 : 1))
                    }.buttonStyle(.plain).accessibilityLabel(item + " theme").accessibilityAddTraits(theme == item ? .isSelected : [])
                }
            }
            Text("Applies to Iris and new Island sessions. iPhone Reduce Motion is respected.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Call the Island, not the full app.").font(.title2.weight(.semibold))
            Text("An Open App shortcut always opens the full app. In Shortcuts, choose Iris’s own actions instead:").font(.subheadline).foregroundStyle(.secondary)
            Label("Ask Iris in Island", systemImage: "waveform").font(.headline)
            Text("A voice session with a visible Live Activity, without requesting the chat interface. Save a provider key and grant microphone/speech permission in Iris first. iOS may require unlock or foreground setup; if it blocks background recording, use the downloadable fallback below.").font(.subheadline).foregroundStyle(.secondary)
            Label("Show Iris in Island", systemImage: "capsule").font(.headline)
            Text("Displays Iris briefly without starting the microphone. Then tap the Island to open the conversation.").font(.subheadline).foregroundStyle(.secondary)
            ShortcutsLink()
            Link("Download Island voice shortcut ↗", destination: URL(string: "https://projectiris.lovelyabbey.chatgpt.site/shortcuts/Ask-Iris-in-Island.shortcut")!)
                .buttonStyle(.borderedProminent).foregroundStyle(.black)
            Text("The downloadable fallback briefly opens Iris’s compact summon view, waits for recording to start, then returns to your Home Screen. Import it into Shortcuts and choose it under Settings → Action Button → Shortcut. It requires initial setup and permission in Iris; it is not an invisible always-on microphone.")
                .font(.caption).foregroundStyle(.secondary)
            if let url = Bundle.main.url(forResource: "Ask-Iris-in-Island", withExtension: "shortcut") { ShareLink("Share bundled shortcut file", item: url) }
            Link("iPhone setup & troubleshooting ↗", destination: URL(string: "https://projectiris.lovelyabbey.chatgpt.site/iphone#action-button")!)
            Button("Preview Island") { session.previewIsland() }.buttonStyle(.bordered)
        }
    }

    private func save(_ key: String, provider: String) {
        do { try IrisKey.save(key, provider: provider); status = key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Key removed." : "Key saved. Send a question to verify access." }
        catch { status = error.localizedDescription }
    }
    private func field(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: text).textInputAutocapitalization(.never).autocorrectionDisabled()
                .padding(14).background(IrisStyle.surface, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private func keyField(_ title: String, text: Binding<String>) -> some View {
        SecureField(title, text: text).textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(14).background(IrisStyle.surface, in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel(title)
    }
    private func chips(_ values: [String], selection: Binding<String>, titles: [String]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(values.enumerated()), id: \.element) { index, value in
                Button { selection.wrappedValue = value } label: {
                    Text(titles[index]).font(.subheadline.weight(.semibold)).padding(.horizontal, 16).padding(.vertical, 11)
                        .foregroundStyle(selection.wrappedValue == value ? .black : .white)
                        .background(selection.wrappedValue == value ? IrisStyle.accent : IrisStyle.surface, in: Capsule())
                }.buttonStyle(.plain).accessibilityAddTraits(selection.wrappedValue == value ? .isSelected : [])
            }
        }
    }
}

private struct IrisDesignSurface: View {
    var selected: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 14).fill(IrisStyle.surface)
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(IrisStyle.accent.opacity(selected ? 0.7 : 0.1)))
    }
}
