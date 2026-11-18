import SwiftUI
import ActivityKit
import AVFoundation
import Speech

@MainActor final class IrisSession: NSObject, ObservableObject {
    static let shared = IrisSession()
    @Published var islandMode = false
    @Published var messages: [IrisMessage] = []
    @Published var input = ""
    @Published var phase = "Ready"
    @Published var error: String?
    @Published var busy = false
    @Published var listening = false
    @Published var showSettings = false
    private var work: Task<Void, Never>?
    private var activity: Activity<IrisActivity>?
    private var islandDismiss: Task<Void, Never>?
    private let engine = AVAudioEngine()
    private var recognition: SFSpeechRecognitionTask?
    private var audioRequest: SFSpeechAudioBufferRecognitionRequest?
    private var silence: Task<Void, Never>?
    private var listeningLimit: Task<Void, Never>?
    private var tapInstalled = false
    private var speechTask: Task<Void, Never>?
    private var speechQueue: [String] = []
    private var queuedCharacters = 0
    private var wantsSpeech = false
    private var spokenSession = false
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    private var voiceGeneration = UUID()
    private var requestGeneration = UUID()
    private var transcriptURL: URL { URL.documentsDirectory.appending(path: "conversation.json") }

    override init() {
        super.init()
        if let data = try? Data(contentsOf: transcriptURL), let saved = try? JSONDecoder().decode([IrisMessage].self, from: data) {
            messages = Array(saved.suffix(100))
        }
    }

    func summon(islandOnly: Bool = false) {
        islandMode = islandOnly
        guard !busy, !listening else { return }
        if IrisKey.read(UserDefaults.standard.string(forKey: "IrisProvider") ?? "gemini").isEmpty { error = "Save your selected provider’s API key, then summon Iris again."; showSettings = true; return }
        Task { await startListening() }
    }

    func send(spoken: Bool = false) {
        let prompt = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !busy else { return }
        guard !IrisKey.read(UserDefaults.standard.string(forKey: "IrisProvider") ?? "gemini").isEmpty else { error = "Save your selected provider’s API key in Settings."; showSettings = true; return }
        stopListening()
        speechTask?.cancel(); speechTask = nil; speechQueue = []; IrisVoice.shared.stop()
        input = ""; error = nil; busy = true; spokenSession = spoken
        queuedCharacters = 0; wantsSpeech = spoken || UserDefaults.standard.bool(forKey: "IrisSpeakReplies")
        messages.append(IrisMessage(role: "user", text: prompt))
        let history = messages
        let responseID = UUID()
        messages.append(IrisMessage(id: responseID, role: "assistant", text: ""))
        let generation = UUID(); requestGeneration = generation
        phase = "Writing"
        if islandMode { leaveForeground() }
        let provider = UserDefaults.standard.string(forKey: "IrisProvider") ?? "gemini"
        let key = IrisKey.read(provider)
        let model = UserDefaults.standard.string(forKey: provider == "openai" ? "IrisOpenAIModel" : "IrisModel") ?? (provider == "openai" ? "gpt-6-luna" : "gemini-3.8-flash")
        let name = UserDefaults.standard.string(forKey: "IrisName") ?? ""
        work = Task { [weak self] in
            guard let self else { return }
            await self.island("Writing", message: "Working on your answer")
            do {
                try Task.checkCancellation()
                let context = await IrisConnections.shared.context()
                try Task.checkCancellation()
                let answer = try await IrisNetwork.stream(messages: history, key: key, model: model, name: name, provider: provider, context: context) { [weak self] text in
                    guard let self, self.requestGeneration == generation,
                          let index = self.messages.firstIndex(where: { $0.id == responseID }) else { return }
                    self.messages[index].text = text
                    if self.wantsSpeech, self.queuedCharacters == 0, text.count >= 100 {
                        let head = String(text.prefix(180))
                        if let boundary = head.range(of: #"[.!?]\s"#, options: .regularExpression), head.distance(from: head.startIndex, to: boundary.upperBound) >= 50 {
                            self.enqueueSpeech(String(head[..<boundary.upperBound]))
                        }
                    }
                }
                try Task.checkCancellation()
                guard self.requestGeneration == generation else { return }
                self.busy = false; self.phase = "Ready"; self.persist()
                await self.island("Ready", message: "Your answer is ready")
                if self.wantsSpeech {
                    let rest = String(answer.dropFirst(self.queuedCharacters).prefix(max(0, 900 - self.queuedCharacters)))
                    if !rest.isEmpty { self.enqueueSpeech(rest) } else if self.speechTask == nil { self.endIslandSoon() }
                } else { self.endIslandSoon() }
                if self.speechTask == nil { self.finishBackgroundTask() }
            } catch {
                guard self.requestGeneration == generation else { return }
                if let index = self.messages.firstIndex(where: { $0.id == responseID }), self.messages[index].text.isEmpty { self.messages.remove(at: index) }
                self.busy = false; self.phase = "Ready"
                if !(error is CancellationError) { self.error = error.localizedDescription }
                self.persist(); await self.endIsland(); self.finishBackgroundTask()
            }
        }
    }

    func stop() {
        requestGeneration = UUID()
        work?.cancel(); work = nil
        stopListening(); speechTask?.cancel(); speechTask = nil; speechQueue = []; IrisVoice.shared.stop()
        busy = false; phase = "Ready"
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        messages.removeAll { $0.role == "assistant" && $0.text.isEmpty }
        persist(); Task { await endIsland() }; finishBackgroundTask()
    }

    func newConversation() { stop(); messages = []; persist() }

    func startIslandRecording() async throws {
        guard !IrisKey.read(UserDefaults.standard.string(forKey: "IrisProvider") ?? "gemini").isEmpty else { throw IrisError.message("Open Iris and save a provider API key first.") }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized, AVAudioApplication.shared.recordPermission == .granted else {
            throw IrisError.message("Open Iris once and use Speak to grant Microphone and Speech Recognition, then run Ask Iris in Island again.")
        }
        islandMode = true
        await startListening()
        guard listening else { throw IrisError.message(error ?? "iOS couldn’t start this Island session. Open Iris and try again.") }
    }

    func showIsland() async throws {
        guard await island("Ready", message: "Tap to open Iris", allowBackground: true) else { throw IrisError.message(error ?? "Enable Live Activities for Iris in iPhone Settings.") }
        endIslandSoon(delay: 25)
    }

    func startListening() async {
        guard !busy, !listening else { return }
        error = nil
        let generation = UUID(); voiceGeneration = generation
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard voiceGeneration == generation else { return }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard voiceGeneration == generation else { return }
        guard speechStatus == .authorized, microphone else {
            error = "Allow Microphone and Speech Recognition for Iris in iPhone Settings. You can still type."; return
        }
        guard (UIApplication.shared.applicationState == .active || islandMode),
              let recognizer = SFSpeechRecognizer(locale: .current), recognizer.isAvailable else {
            error = "Speech recognition is unavailable right now. Try typing your question."; return
        }
        speechTask?.cancel(); speechTask = nil; speechQueue = []; IrisVoice.shared.stop()
        do {
            if islandMode {
                guard await island("Listening", message: "Speak your question", allowBackground: true) else { throw IrisError.message(error ?? "A visible Live Activity is required for Island voice input.") }
            }
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            try audio.setActive(true)
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            audioRequest = request
            let node = engine.inputNode
            let format = node.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else { throw IrisError.message("No microphone is available.") }
            node.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in request.append(buffer) }
            tapInstalled = true
            listening = true; phase = "Listening"; input = ""
            recognition = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                Task { @MainActor in
                    guard let self, self.listening, self.voiceGeneration == generation else { return }
                    if let result {
                        self.input = result.bestTranscription.formattedString
                        self.silence?.cancel()
                        if result.isFinal { self.finishVoice(); return }
                        self.silence = Task { [weak self] in
                            try? await Task.sleep(for: .milliseconds(1600))
                            guard !Task.isCancelled, let self, self.voiceGeneration == generation else { return }
                            self.finishVoice()
                        }
                    }
                    if failure != nil { self.stopListening(); self.error = "Speech input stopped. Please retry or type."; await self.endIsland() }
                }
            }
            engine.prepare(); try engine.start()
            await island("Listening", message: "Speak your question")
            listeningLimit = Task { [weak self] in
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled, let self, self.voiceGeneration == generation else { return }
                self.finishVoice()
            }
        } catch {
            stopListening(); self.error = error.localizedDescription; await endIsland()
        }
    }

    func finishVoice() {
        guard listening else { return }
        stopListening()
        if islandMode && UIApplication.shared.applicationState != .active { leaveForeground() }
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "I didn’t catch that. Try again or type a question."; Task { await endIsland() }
        } else { send(spoken: true) }
    }

    private func stopListening() {
        voiceGeneration = UUID(); listening = false
        silence?.cancel(); listeningLimit?.cancel()
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        audioRequest?.endAudio(); recognition?.cancel(); recognition = nil; audioRequest = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if !busy { phase = "Ready" }
    }

    private func enqueueSpeech(_ text: String) {
        queuedCharacters += text.count
        speechQueue.append(text)
        guard speechTask == nil else { return }
        let generation = requestGeneration
        speechTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.requestGeneration == generation {
                    self.speechTask = nil
                    if !self.busy { self.phase = "Ready"; self.endIslandSoon(); self.finishBackgroundTask() }
                }
            }
            do {
                while !self.speechQueue.isEmpty {
                    try Task.checkCancellation()
                    let chunk = self.speechQueue.removeFirst()
                    self.phase = "Speaking"
                    await self.island("Speaking", message: "Iris is reading your answer")
                    try await IrisVoice.shared.play(chunk)
                }
            } catch {
                if !(error is CancellationError) { self.error = error.localizedDescription }
                self.speechQueue = []
            }
        }
    }

    func leaveForeground() {
        if listening && !islandMode { stopListening(); Task { await endIsland() } }
        if busy, backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish Iris answer") { [weak self] in
                Task { @MainActor in self?.stop() }
            }
        }
    }

    private func finishBackgroundTask() {
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask); backgroundTask = .invalid }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(messages.suffix(100))) {
            try? data.write(to: transcriptURL, options: [.atomic, .completeFileProtection])
        }
    }

    func previewIsland() {
        guard !busy, !listening, phase != "Speaking" else { return }
        Task {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { error = "Enable Live Activities for Iris in iPhone Settings."; return }
            await island("Ready", message: "Here when you need me")
            endIslandSoon()
        }
    }

    func cleanOldActivities() async {
        guard !busy, !listening, activity == nil else { return }
        for activity in Activity<IrisActivity>.activities { await activity.end(nil, dismissalPolicy: .immediate) }
    }

    @discardableResult private func island(_ phase: String, message: String, allowBackground: Bool = false) async -> Bool {
        islandDismiss?.cancel()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        let content = ActivityContent(state: IrisActivity.ContentState(phase: phase, message: message, theme: UserDefaults.standard.string(forKey: "IrisTheme")), staleDate: .now.addingTimeInterval(90))
        if let activity, activity.activityState == .active { await activity.update(content) }
        else if UIApplication.shared.applicationState == .active || allowBackground {
            do { activity = try Activity.request(attributes: IrisActivity(session: UUID().uuidString), content: content) }
            catch { self.error = "iOS couldn’t start the Live Activity: " + error.localizedDescription; return false }
        } else { return false }
        return true
    }

    private func endIslandSoon(delay: Double = 5) {
        islandDismiss?.cancel()
        islandDismiss = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }; await self?.endIsland()
        }
    }
    private func endIsland() async {
        islandDismiss?.cancel()
        let previous = activity
        activity = nil
        if let previous { await previous.end(nil, dismissalPolicy: .immediate) }
    }
}
