import SwiftUI

struct GeminiVoiceSettings: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var key = ""
    @State private var keySaved = false
    @State private var setupError: String?
    @State private var showAll = false
    private var voice: String { iris.preferences.geminiVoice ?? GeminiSpeechClient.defaultVoice }
    private var auth: String { iris.preferences.geminiSpeechAuth ?? "apiKey" }
    private var displayedVoices: [GeminiVoice] { showAll ? GeminiSpeechClient.voices : Array(GeminiSpeechClient.voices.prefix(6)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Connect Gemini speech").font(.headline)
                IrisPicker("Access", selection: Binding(get: { auth }, set: { value in iris.voice.stopSpeaking(); iris.setPreference { $0.geminiSpeechAuth = value } }), display: auth == "apiKey" ? "Google AI Studio API key" : "Connected Gemini account", options: [.init(value: "apiKey", title: "Google AI Studio API key", symbol: "key"), .init(value: "account", title: "Connected Gemini account", symbol: "person.crop.circle")])
                if auth == "apiKey" {
                    HStack(spacing: 12) {
                        SecureField(keySaved ? "Replace saved Gemini API key" : "Gemini API key", text: $key).textFieldStyle(IrisTextFieldStyle())
                        Button("Save key") {
                            do { try GeminiSpeechVault.save(key); key = ""; keySaved = true; setupError = nil; iris.voice.stopSpeaking() }
                            catch { setupError = error.localizedDescription }
                        }.disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    HStack {
                        if keySaved { Label("Key saved in Keychain", systemImage: "checkmark.shield").foregroundStyle(iris.accent); Spacer(); Button("Remove key") { do { try GeminiSpeechVault.delete(); keySaved = false; iris.voice.stopSpeaking() } catch { setupError = error.localizedDescription } } }
                        else { Link("Get a Gemini API key", destination: URL(string: "https://aistudio.google.com/api-keys")!) }
                    }.font(.caption)
                } else {
                    Text("Uses your Gemini API authorization and its Google Cloud project. A Gmail sign-in or Gemini app subscription alone does not grant speech API access.").font(.caption).foregroundStyle(IrisDesign.secondary)
                    Button(iris.accounts.authorizing ? "Waiting for browser…" : "Connect Gemini account", systemImage: "person.crop.circle") {
                        Task {
                            do {
                                guard let configuration = try GoogleAppConfiguration.read() else { throw IrisFailure.message("Configure Iris's Google registration in Settings → AI first, or use a Google AI Studio API key.") }
                                try await iris.accounts.signIn(source: .gemini, googleClientID: configuration.clientID)
                                setupError = nil
                            } catch { setupError = error.localizedDescription }
                        }
                    }.disabled(iris.accounts.authorizing)
                }
                if let setupError { Text(setupError).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            }
            HStack(spacing: 20) {
                IrisPicker("Speech model", selection: preference(\.geminiSpeechModel, default: GeminiSpeechClient.defaultModel), display: (iris.preferences.geminiSpeechModel ?? GeminiSpeechClient.defaultModel) == GeminiSpeechClient.models[0] ? "Flash · Expressive" : "Flash-Lite · Fast", options: [.init(value: GeminiSpeechClient.models[0], title: "Flash", detail: "Expressive", symbol: "waveform"), .init(value: GeminiSpeechClient.models[1], title: "Flash-Lite", detail: "Fast", symbol: "bolt")])
                IrisPicker("Delivery", selection: preference(\.geminiSpeechStyle, default: "Natural"), options: GeminiSpeechClient.styles.map { .init(value: $0, title: $0) })
            }
            HStack { Text("Choose Iris's voice").font(.headline); Spacer(); Button(showAll ? "Show fewer" : "All 30 voices") { showAll.toggle() }.font(.caption) }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(displayedVoices) { item in
                        HStack(spacing: 16) {
                            Button { iris.voice.stopSpeaking(); iris.setPreference { $0.geminiVoice = item.name } } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: voice == item.name ? "checkmark.circle.fill" : "circle").irisSymbolStyle().foregroundStyle(iris.accent)
                                    VStack(alignment: .leading, spacing: 4) { Text(item.name).font(.system(size: 14, weight: .medium)); Text(item.tone).font(.caption).foregroundStyle(IrisDesign.secondary) }
                                    Spacer()
                                }.contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { preview(item.name) } label: { Image(systemName: "play.fill").irisSymbolStyle().frame(width: 32, height: 32) }.buttonStyle(.plain).disabled(iris.voice.preparingSpeech).help("Preview \(item.name)").accessibilityLabel("Preview \(item.name)")
                        }.padding(.vertical, 12)
                        if item.id != displayedVoices.last?.id { Divider() }
                    }
                }
            }.frame(height: 260)
            Toggle("Economy speech", isOn: Binding(get: { iris.preferences.geminiSpeechEconomy ?? true }, set: { enabled in iris.voice.stopSpeaking(); iris.setPreference { $0.geminiSpeechEconomy = enabled } }))
            Text("Recommended: one speech request per reply, reading a short opening excerpt (up to 360 characters). Full answers stay in chat. Turn off to read longer answers in multiple requests.").font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            Toggle("Also speak typed chats", isOn: Binding(get: { iris.preferences.speakTypedReplies ?? false }, set: { enabled in iris.voice.stopSpeaking(); iris.setPreference { $0.speakTypedReplies = enabled } }))
            Toggle("Read answers as they arrive", isOn: Binding(get: { iris.preferences.streamSpokenReplies ?? true }, set: { enabled in iris.voice.stopSpeaking(); iris.setPreference { $0.streamSpokenReplies = enabled } }))
            Text("Speech starts once a stable excerpt is ready while Iris writes. Audio streams as generated. Economy mode speaks only the opening excerpt.").font(.caption).foregroundStyle(IrisDesign.secondary)
            HStack {
                Text("Playback speed")
                Slider(value: Binding(get: { iris.preferences.geminiSpeechSpeed ?? 1 }, set: { value in iris.setPreference { $0.geminiSpeechSpeed = value } }), in: 0.75...1.4)
                Text(String(format: "%.2f×", iris.preferences.geminiSpeechSpeed ?? 1)).monospacedDigit().frame(width: 52)
            }
            Text("AI-generated voice · Reply text is sent to Google for speech. API quota and charges may apply, including previews. Changing voices does not generate audio until you press Preview. Repeated previews are cached in memory. Economy replies use one request and up to 360 characters; full speech uses up to 2,000 characters. Code blocks are skipped. Repeated reply audio is cached in memory. Google limits requests and audio usage per project, not per key.").font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            Link("Gemini speech pricing", destination: URL(string: "https://ai.google.dev/gemini-api/docs/pricing")!).font(.caption)
        }.task {
            guard !ProcessInfo.processInfo.arguments.contains("--iris-validation") else { return }
            keySaved = ((try? await GeminiSpeechVault.readAsync()) ?? nil) != nil
        }
    }
    private func preference(_ path: WritableKeyPath<Preferences, String?>, default fallback: String) -> Binding<String> {
        Binding(get: { iris.preferences[keyPath: path] ?? fallback }, set: { value in iris.voice.stopSpeaking(); iris.setPreference { $0[keyPath: path] = value } })
    }
    private func preview(_ name: String) {
        iris.voice.speak("Hi, I'm Iris. What can I help with?", provider: "gemini", speed: iris.preferences.geminiSpeechSpeed ?? 1, preview: true, geminiVoice: name, geminiModel: iris.preferences.geminiSpeechModel ?? GeminiSpeechClient.defaultModel, geminiStyle: iris.preferences.geminiSpeechStyle ?? "Natural", geminiAuth: auth)
    }
}
