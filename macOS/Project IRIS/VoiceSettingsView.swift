import SwiftUI
import AppKit
import AVFoundation

struct VoiceSettingsView: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var server = ""
    @State private var profiles: [VoiceBoxProfile] = []
    @State private var loading = false
    @State private var connectionError: String?
    private var provider: String { iris.preferences.speechProvider }
    private var natural: Bool { provider == "voicebox" }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill").irisSymbolStyle().font(.system(size: 48)).foregroundStyle(iris.accent)
                VStack(alignment: .leading, spacing: 5) { Text("A voice that feels right").font(.title2.weight(.semibold)); Text("Choose how Iris sounds, independently of your chat model.").foregroundStyle(IrisDesign.secondary) }
            }
            HStack(spacing: 12) {
                Button { changeProvider("fish") } label: { Label("Default", systemImage: provider == "fish" ? "checkmark.circle.fill" : "circle") }.buttonStyle(IrisActionStyle(primary: provider == "fish"))
                Button { changeProvider("gemini") } label: { Label("Gemini", systemImage: provider == "gemini" ? "checkmark.circle.fill" : "circle") }.buttonStyle(IrisActionStyle(primary: provider == "gemini"))
                Button { changeProvider("voicebox") } label: { Label("VoiceBox · Local AI", systemImage: natural ? "checkmark.circle.fill" : "circle") }.buttonStyle(IrisActionStyle(primary: natural))
            }
            if provider == "fish" {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Simonne · Fish Audio").font(.headline)
                    Text("A shared voice for Iris. Your reply text is sent to Fish Audio through AriZe’s voice service. An internet connection is required.").foregroundStyle(IrisDesign.secondary)
                    Text("No API key needed. Shared usage limits apply. If the free service is unavailable, Iris keeps your text reply.").font(.caption).foregroundStyle(IrisDesign.secondary)
                }
            }
            else if provider == "gemini" { GeminiVoiceSettings(iris: iris) }
            else if natural {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Text("VoiceBox connection").font(.headline); Spacer(); Button("Open VoiceBox", systemImage: "arrow.up.right") { openVoiceBox() } }
                    HStack(spacing: 12) {
                        TextField("http://127.0.0.1:17493", text: $server).textFieldStyle(IrisTextFieldStyle()).accessibilityLabel("VoiceBox local server address")
                        Button(loading ? "Connecting…" : "Refresh voices", systemImage: "arrow.clockwise") { Task { await refresh() } }.disabled(loading)
                    }
                    if loading { ProgressView("Finding local voices…").controlSize(.small) }
                    if let connectionError { Label(connectionError, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
                    if !loading, profiles.isEmpty {
                        Text("Open VoiceBox, download a speech engine and create a voice profile. Kokoro is a lightweight starting point; Qwen offers more expressive options. Then refresh voices here.").font(.system(size: 13)).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
                        Link("Get VoiceBox", destination: URL(string: "https://voicebox.sh")!)
                    }
                }
                if !profiles.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(profiles) { profile in
                            HStack(spacing: 14) {
                                Button { iris.voice.stopSpeaking(); iris.setPreference { $0.voiceBoxProfile = profile.id } } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: iris.preferences.voiceBoxProfile == profile.id ? "checkmark.circle.fill" : "circle").irisSymbolStyle().foregroundStyle(iris.accent)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(profile.name).font(.system(size: 14, weight: .medium))
                                            Text(profile.description?.isEmpty == false ? profile.description! : profile.language.uppercased()).font(.caption).foregroundStyle(IrisDesign.secondary).lineLimit(2)
                                        }
                                        Spacer()
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button { preview(profile.id) } label: { Image(systemName: "play.fill").irisSymbolStyle().frame(width: 32, height: 32) }.buttonStyle(.plain).disabled(iris.voice.preparingSpeech).help("Preview \(profile.name)").accessibilityLabel("Preview \(profile.name)")
                            }.padding(.vertical, 14)
                            if profile.id != profiles.last?.id { Divider() }
                        }
                    }
                    if let selected = iris.preferences.voiceBoxProfile, !profiles.contains(where: { $0.id == selected }) { Text("Your saved voice is no longer available. Choose a profile above.").font(.caption).foregroundStyle(.orange) }
                }
                HStack { Text("Playback speed"); Slider(value: Binding(get: { iris.preferences.voiceBoxSpeed ?? 1 }, set: { speed in iris.setPreference { $0.voiceBoxSpeed = speed } }), in: 0.75...1.4); Text(String(format: "%.2f×", iris.preferences.voiceBoxSpeed ?? 1)).monospacedDigit().frame(width: 52) }
                Text("AI-generated voice · No voice API key or per-character fee. Reply text goes to VoiceBox on this Mac. Spoken replies include up to 2,000 characters; code blocks are skipped. The first preview may take longer while VoiceBox loads its model.").font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 14) {
                Button("Preview voice", systemImage: "play.fill") { preview(iris.preferences.voiceBoxProfile) }.buttonStyle(IrisActionStyle(primary: true)).disabled(iris.voice.preparingSpeech || (natural && iris.preferences.voiceBoxProfile == nil))
                Button("Stop", systemImage: "stop.fill") { iris.voice.stopSpeaking() }.disabled(!iris.voice.preparingSpeech && !iris.voice.speaking)
                if iris.voice.preparingSpeech { ProgressView("Preparing voice…").controlSize(.small) }
            }
            if let error = iris.voice.speechError { Text(error).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            Divider()
            IrisPicker("Speech recognition",selection:Binding(get:{iris.preferences.speechRecognitionProvider ?? "apple"},set:{value in iris.voice.stop();iris.setPreference{$0.speechRecognitionProvider=value}}),options:[.init(value:"apple",title:"Apple · improved dictation",detail:"On-device when supported, technical vocabulary and longer pauses"),.init(value:"voicebox",title:"VoiceBox · local Whisper",detail:"Requires VoiceBox running and its recognition model installed")])
            if iris.preferences.speechRecognitionProvider == "voicebox" && provider != "voicebox" {
                TextField("VoiceBox server",text:$server).textFieldStyle(IrisTextFieldStyle()).onChange(of:server){_,value in if iris.preferences.voiceBoxServer != value {iris.setPreference{$0.voiceBoxServer=value}}}
            }
            Text("Local Whisper sends microphone audio only to VoiceBox on this Mac. Its first use may need a model download in VoiceBox; there are no cloud API calls. Live transcription appears after you finish speaking.").font(.caption).foregroundStyle(IrisDesign.secondary)
            Toggle("Listen when I use the keyboard shortcut", isOn: Binding(get: { iris.preferences.listenOnSummon ?? true }, set: { enabled in iris.setPreference { $0.listenOnSummon = enabled } }))
            Toggle("Speak replies after voice requests", isOn: Binding(get: { iris.preferences.speakReplies ?? true }, set: { enabled in iris.setPreference { $0.speakReplies = enabled } }))
            if provider != "gemini" {
                Toggle("Also speak typed chats", isOn: Binding(get: { iris.preferences.speakTypedReplies ?? false }, set: { enabled in iris.setPreference { $0.speakTypedReplies = enabled } }))
            }
            Text("Speak naturally and pause to send. If your default mic is Bluetooth, Iris prefers a Mac or wired mic when available to avoid switching your headphones into call mode.").font(.caption).foregroundStyle(IrisDesign.secondary)
        }.task {
            server = iris.preferences.voiceBoxServer ?? VoiceBoxClient.defaultServer
            if natural { await refresh() }
        }
    }
    private func changeProvider(_ provider: String) {
        iris.voice.stopSpeaking(); iris.voice.speechError = nil
        iris.setPreference { $0.voiceProvider = provider }
        if provider == "voicebox" { Task { await refresh() } }
    }
    @MainActor private func refresh() async {
        guard !loading else { return }; loading = true; connectionError = nil
        defer { loading = false }
        do {
            _ = try VoiceBoxClient.baseURL(server)
            let clean = server.trimmingCharacters(in: .whitespacesAndNewlines)
            let found = try await VoiceBoxClient.profiles(server: clean)
            try Task.checkCancellation()
            profiles = found
            iris.setPreference { $0.voiceBoxServer = clean }
        } catch is CancellationError { }
        catch { connectionError = error.localizedDescription; profiles = [] }
    }
    private func preview(_ profile: String?) {
        iris.voice.speak("Hi, I'm Iris. What can I help with?", identifier: iris.preferences.voiceID, rate: iris.preferences.speechRate ?? 0.49, provider: provider, server: iris.preferences.voiceBoxServer ?? VoiceBoxClient.defaultServer, profile: profile, speed: provider == "gemini" ? (iris.preferences.geminiSpeechSpeed ?? 1) : (iris.preferences.voiceBoxSpeed ?? 1), preview: true, geminiVoice: iris.preferences.geminiVoice ?? GeminiSpeechClient.defaultVoice, geminiModel: iris.preferences.geminiSpeechModel ?? GeminiSpeechClient.defaultModel, geminiStyle: iris.preferences.geminiSpeechStyle ?? "Natural", geminiAuth: iris.preferences.geminiSpeechAuth ?? "apiKey")
    }
    private func openVoiceBox() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "sh.voicebox.app") ?? ["/Applications/Voicebox.app", "/Applications/VoiceBox.app"].map({ URL(fileURLWithPath: $0) }).first(where: { FileManager.default.fileExists(atPath: $0.path) }) else {
            connectionError = "VoiceBox isn't installed here. Get it from voicebox.sh, then configure a voice profile."; return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in if let error { Task { @MainActor in connectionError = error.localizedDescription } } }
    }
}
