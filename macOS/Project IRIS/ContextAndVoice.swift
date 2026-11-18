import AppKit
import Combine
import AVFoundation
import Speech
import Vision
import PDFKit
import ScreenCaptureKit
import UniformTypeIdentifiers
import OSLog

enum ContextReader {
    static func read(url: URL) async throws -> AttachedContext {
        try await Task.detached(priority: .userInitiated) { try AttachmentReader.read(url: url) }.value
    }
    static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    static func capture(bundleID: String, displayID: CGDirectDisplayID) async throws -> AttachedContext {
        try await ScreenRecordingAccess.shared.requireAccess()
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == displayID }),
              let app = content.applications.first(where: { $0.bundleIdentifier == bundleID }) else {
            throw IrisFailure.message("The selected application is no longer visible on this display.")
        }
        // Include only the explicitly allowed app; other apps are never part of the captured filter.
        let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
        let config = SCStreamConfiguration(); config.width = min(display.width, 2400); config.height = Int(Double(display.height) * Double(config.width) / Double(display.width)); config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        let text = try await Task.detached(priority: .userInitiated) { try recognize(image) }.value
        guard !text.isEmpty else { throw IrisFailure.message("No readable text was found in the allowed application.") }
        return AttachedContext(name: "Screen · \(app.applicationName)", text: String(text.prefix(18000)))
    }
}

@MainActor
final class VoiceService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    @Published var listening = false
    @Published var requesting = false
    private var generation = UUID()
    @Published var speaking = false
    @Published var preparingSpeech = false
    @Published var speechError: String?
    private static weak var playbackOwner: VoiceService?
    private var speechObserver: NSObjectProtocol?
    private var currentSpokenText: String?
    private var localRecognitionTask: Task<Void,Never>?
    private var lastVoiceActivity = 0.0
    private var heardVoice = false
    private var finalizingRecognition = false
    private var speechTask: Task<Void, Never>?
    private var playbackID = UUID()
    private var naturalPlayer: AVAudioPlayer?
    private var currentUtterance: AVSpeechUtterance?
    private var previewCache: [String: Data] = [:]
    private var replyAudioCache: [String: Data] = [:]
    private var speechQuotaUntil = Date.distantPast
    private var replyChunker: ReplySpeechChunker?
    private var replyContinuation: AsyncStream<String>.Continuation?
    private var streamPlayer: StreamingSpeechPlayer?
    private var capture: VoiceCaptureSession?
    private var recognition: SFSpeechRecognitionTask?
    private let synthesizer = AVSpeechSynthesizer()
    private var timeout: Task<Void, Never>?
    private var silence: Task<Void, Never>?
    private var lastTranscript = ""
    private static let log = Logger(subsystem: "com.projectiris.Project-IRIS", category: "voice")
    override init() {
        super.init();synthesizer.delegate=self
        speechObserver=DistributedNotificationCenter.default().addObserver(forName:NSNotification.Name("com.arize.iris.voice-owner"),object:nil,queue:.main){[weak self] note in
            guard note.object as? String != String(ProcessInfo.processInfo.processIdentifier) else{return}
            Task{@MainActor in self?.stopSpeaking()}
        }
    }
    private func claimPlayback() {
        if Self.playbackOwner !== self {Self.playbackOwner?.stopSpeaking()};Self.playbackOwner=self
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.arize.iris.voice-owner"),object:String(ProcessInfo.processInfo.processIdentifier),userInfo:nil,deliverImmediately:true)
    }
    func start(recognizerProvider: String = "apple", server: String = VoiceBoxClient.defaultServer, onText: @escaping (String) -> Void, onError: @escaping (String) -> Void, onFinal: ((String) -> Void)? = nil) async {
        guard !requesting, !listening else { return }
        stop(); stopSpeaking()
        lastTranscript = ""
        let attempt = generation
        requesting = true
        defer { if generation == attempt { requesting = false } }
        let mic = await AVCaptureDevice.requestAccess(for: .audio)
        guard generation == attempt else { return }
        guard mic else { onError("Microphone access is off. Enable it in System Settings → Privacy & Security → Microphone."); return }
        if recognizerProvider == "voicebox" {
            do {
                let request=SFSpeechAudioBufferRecognitionRequest(),capture=VoiceCaptureSession();self.capture=capture
                heardVoice=false;lastVoiceActivity=ProcessInfo.processInfo.systemUptime
                try await capture.start(request:request,record:true,onActivity:{[weak self] in Task{@MainActor in self?.heardVoice=true;self?.lastVoiceActivity=ProcessInfo.processInfo.systemUptime}})
                guard generation==attempt else{capture.stop();return};listening=true
                localRecognitionTask=Task{[weak self] in
                    guard let self else{return}
                    do {
                        let started=ProcessInfo.processInfo.systemUptime
                        while !Task.isCancelled,self.generation==attempt {
                            try await Task.sleep(for:.milliseconds(150))
                            let now=ProcessInfo.processInfo.systemUptime
                            if self.heardVoice && now-self.lastVoiceActivity>1.9 || now-started>45 {break}
                            if !self.heardVoice,now-started>12 {throw IrisFailure.message("No speech detected. Check your microphone or choose Apple recognition in Settings → Voice.")}
                        }
                        try Task.checkCancellation();guard self.generation==attempt else{return}
                        self.listening=false;self.requesting=true
                        let audio=try await capture.finishRecording();try Task.checkCancellation()
                        let text=try await VoiceBoxClient.transcribe(server:server,audio:audio)
                        guard self.generation==attempt else{return};self.stop();onText(text);onFinal?(text)
                    } catch {guard !Task.isCancelled,self.generation==attempt else{return};self.stop();onError("Local speech recognition: "+error.localizedDescription)}
                }
            } catch {stop();onError(error.localizedDescription)}
            return
        }
        let auth = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard generation == attempt else { return }
        guard auth == .authorized else { onError("Speech Recognition access is off. You can still type to Iris."); return }
        guard let recognizer = SFSpeechRecognizer(locale: AssistantLanguage.speechLocale), recognizer.isAvailable else { onError("Apple speech recognition is unavailable for this language or connection."); return }
        do {
            let bufferRequest = SFSpeechAudioBufferRecognitionRequest(); bufferRequest.shouldReportPartialResults = true
            bufferRequest.taskHint = .dictation;bufferRequest.addsPunctuation=true
            bufferRequest.contextualStrings=RecognitionPacing.hints
            bufferRequest.requiresOnDeviceRecognition=recognizer.supportsOnDeviceRecognition
            heardVoice=false;lastVoiceActivity=ProcessInfo.processInfo.systemUptime;finalizingRecognition=false
            let capture = VoiceCaptureSession()
            self.capture = capture
            try await capture.start(request:bufferRequest,onActivity:{[weak self] in Task{@MainActor in self?.heardVoice=true;self?.lastVoiceActivity=ProcessInfo.processInfo.systemUptime}})
            guard generation == attempt else { capture.stop(); return }
            listening = true
            recognition = recognizer.recognitionTask(with: bufferRequest) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.generation == attempt, self.listening else { return }
                    if let result {
                        let transcript = result.bestTranscription.formattedString
                        onText(transcript)
                        if result.isFinal { self.stop(); if !transcript.isEmpty { onFinal?(transcript) }; return }
                        if transcript != self.lastTranscript {
                            self.lastTranscript = transcript; self.silence?.cancel()
                            self.silence = Task { [weak self] in
                                guard let self else{return}
                                do {
                                    try await Task.sleep(for:.seconds(RecognitionPacing.pause(after:transcript)))
                                    while self.listening,ProcessInfo.processInfo.systemUptime-self.lastVoiceActivity<1.8 {try await Task.sleep(for:.milliseconds(150))}
                                    try Task.checkCancellation();guard self.generation==attempt,self.listening else{return}
                                    self.finalizingRecognition=true;self.capture?.stop()
                                    // Give the recognizer a chance to revise its last words before cancelling.
                                    try await Task.sleep(for:.milliseconds(800))
                                    guard self.generation==attempt,self.listening else{return}
                                    let final=self.lastTranscript;self.stop();if !final.isEmpty{onFinal?(final)}
                                } catch {}

                            }
                        }
                    }
                    if let error {
                        let final=self.lastTranscript,finishing=self.finalizingRecognition;self.stop()
                        if finishing,!final.isEmpty{onFinal?(final)}else{onError("Voice input stopped: \(error.localizedDescription)")}
                    }
                }
            }
            timeout = Task { [weak self] in try? await Task.sleep(for: .seconds(60)); guard !Task.isCancelled else { return }; self?.stop() }
            Self.log.info("Microphone started by user")
        } catch { if generation == attempt { stop(); onError(error.localizedDescription) } }
    }
    func stop() {
        generation = UUID(); requesting = false; finalizingRecognition=false;localRecognitionTask?.cancel();localRecognitionTask=nil
        listening = false; timeout?.cancel(); timeout = nil; silence?.cancel(); silence = nil
        capture?.stop(); capture = nil
        recognition?.cancel(); recognition = nil
    }
    func beginStreamingReply(voice: String, model: String, style: String, auth: String, speed: Double, economy: Bool = true) {
        stopSpeaking(); claimPlayback(); speechError = nil
        let token = UUID(); playbackID = token
        replyChunker = ReplySpeechChunker(economy: economy)
        let queue = AsyncStream<String>.makeStream()
        replyContinuation = queue.continuation
        let player = StreamingSpeechPlayer(); streamPlayer = player
        player.onPlaying = { [weak self] playing in
            guard let self, self.playbackID == token else { return }
            self.speaking = playing
            if playing { self.preparingSpeech = false }
        }
        speechTask = Task { [weak self] in
            guard let self else { return }
            do {
                var credential: GeminiSpeechCredential?
                for await chunk in queue.stream {
                    try Task.checkCancellation()
                    guard self.playbackID == token else { return }
                    self.preparingSpeech = !self.speaking
                    let cacheKey = "\(voice)|\(model)|\(style)|\(auth)|\(chunk)"
                    if let cached = self.replyAudioCache[cacheKey] {
                        try player.enqueue(cached, rate: speed)
                    } else {
                        guard Date() >= self.speechQuotaUntil else { throw IrisFailure.message("Gemini speech is temporarily paused after a quota error. Text replies still work; try speech later.") }
                        if credential == nil { credential = try await GeminiSpeechService.credential(auth: auth) }
                        var audio = Data()
                        try await GeminiSpeechClient.stream(text: chunk, voice: voice, model: model, style: style, credential: credential!) { [weak self] bytes in
                            guard let self, self.playbackID == token, !Task.isCancelled else { throw CancellationError() }
                            audio.append(bytes)
                            try player.enqueue(bytes, rate: speed)
                        }
                        if audio.count <= 8_000_000 {
                            if self.replyAudioCache.values.reduce(0, { $0 + $1.count }) + audio.count > 8_000_000 { self.replyAudioCache.removeAll() }
                            self.replyAudioCache[cacheKey] = audio
                        }
                    }
                    try player.flush(rate: speed)
                }
                guard self.playbackID == token else { return }
                self.speechTask = nil; self.preparingSpeech = false; player.finish()
            } catch {
                guard self.playbackID == token, !Task.isCancelled else { return }
                self.replyContinuation?.finish(); self.replyContinuation = nil; self.replyChunker = nil
                self.speechTask = nil; self.preparingSpeech = false; player.stop(); self.speaking = false
                if let quota = error as? GeminiSpeechQuotaError { self.speechQuotaUntil = Date().addingTimeInterval(quota.retryAfter) }
                self.speechError = error.localizedDescription
            }
        }
    }
    func updateStreamingReply(_ text: String, final: Bool = false) {
        guard replyChunker != nil else { return }
        let chunks = replyChunker!.update(text, final: final)
        for chunk in chunks { replyContinuation?.yield(chunk) }
        if !chunks.isEmpty, !speaking { preparingSpeech = true }
        if final { replyContinuation?.finish(); replyContinuation = nil; replyChunker = nil }
    }
    func speak(_ text: String, identifier: String? = nil, rate: Float = 0.49, provider: String = "system", server: String = VoiceBoxClient.defaultServer, profile: String? = nil, speed: Double = 1, preview: Bool = false, geminiVoice: String = GeminiSpeechClient.defaultVoice, geminiModel: String = GeminiSpeechClient.defaultModel, geminiStyle: String = "Natural", geminiAuth: String = "apiKey", economy: Bool = true) {
        let spoken=VoiceBoxClient.speechText(text)
        guard !spoken.isEmpty else{return}
        let speechKey=[provider,identifier ?? "",server,profile ?? "",geminiVoice,geminiModel,geminiStyle,String(speed),spoken].joined(separator:"|")
        if currentSpokenText==speechKey,(speaking || preparingSpeech){return}
        stop(); stopSpeaking(); claimPlayback(); currentSpokenText=speechKey; speechError = nil
        if provider == "gemini", !preview {
            beginStreamingReply(voice: geminiVoice, model: geminiModel, style: geminiStyle, auth: geminiAuth, speed: speed, economy: economy)
            currentSpokenText=speechKey
            updateStreamingReply(text, final: true)
            return
        }
        if provider == "voicebox" || provider == "gemini" {
            let token = UUID(); playbackID = token; preparingSpeech = true
            let cacheKey = "\(provider)|\(server)|\(profile ?? "")|\(speed)|\(geminiVoice)|\(geminiModel)|\(geminiStyle)|\(geminiAuth)|\(text)"
            speechTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let bytes: Data
                    if preview, let cached = self.previewCache[cacheKey] { bytes = cached }
                    else if provider == "gemini" {
                        guard Date() >= self.speechQuotaUntil else { throw IrisFailure.message("Gemini speech is temporarily paused after a quota error. Text replies still work; try speech later.") }
                        bytes = try await GeminiSpeechService.audio(text: text, voice: geminiVoice, model: geminiModel, style: geminiStyle, auth: geminiAuth) }
                    else { bytes = try await VoiceBoxClient.audio(server: server, profile: profile ?? "", text: text, speed: 1) }
                    try Task.checkCancellation()
                    guard self.playbackID == token else { return }
                    if preview {
                        if self.previewCache.count >= 6 { self.previewCache.removeAll() }
                        self.previewCache[cacheKey] = bytes
                    }
                    let player = try AVAudioPlayer(data: bytes)
                    if provider == "gemini" || provider == "voicebox" { player.enableRate = true; player.rate = Float(min(1.4, max(0.75, speed))) }
                    player.delegate = self; self.naturalPlayer = player
                    guard player.prepareToPlay(), player.play() else { throw IrisFailure.message("The generated voice couldn't be played. Check your audio output.") }
                    self.preparingSpeech = false; self.speaking = true; self.speechTask = nil
                } catch {
                    guard self.playbackID == token, !Task.isCancelled else { return }
                    self.preparingSpeech = false; self.speaking = false; self.naturalPlayer = nil; self.speechTask = nil
                    if let quota = error as? GeminiSpeechQuotaError { self.speechQuotaUntil = Date().addingTimeInterval(quota.retryAfter) }
                    self.speechError = error.localizedDescription
                }
            }
            return
        }
        let utterance = AVSpeechUtterance(string: VoiceBoxClient.speechText(text)); utterance.rate = min(0.6, max(0.35, rate))
        utterance.preUtteranceDelay=0.08;utterance.postUtteranceDelay=0.16
        let language = AssistantLanguage.spokenLanguage(text)
        let chosen = identifier.flatMap { AVSpeechSynthesisVoice(identifier: $0) }
        utterance.voice = chosen.flatMap { $0.language.hasPrefix(language) ? $0 : nil } ?? AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }.sorted { $0.quality.rawValue > $1.quality.rawValue }.first
        currentUtterance = utterance; speaking = true; synthesizer.speak(utterance)
    }
    func stopSpeaking() {
        playbackID = UUID(); replyContinuation?.finish(); replyContinuation = nil; replyChunker = nil
        speechTask?.cancel(); speechTask = nil
        streamPlayer?.stop(); streamPlayer = nil
        naturalPlayer?.delegate=nil;naturalPlayer?.stop(); naturalPlayer = nil; currentUtterance = nil;currentSpokenText=nil
        synthesizer.stopSpeaking(at: .immediate); preparingSpeech = false; speaking = false
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            guard player === self.naturalPlayer else { return }
            self.naturalPlayer = nil; self.speaking = false
            if !flag { self.speechError = "Voice playback was interrupted. Check your audio output." }
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor in guard let current = self.currentUtterance, ObjectIdentifier(current) == identity else { return }; self.currentUtterance = nil; self.speaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let identity = ObjectIdentifier(utterance)
        Task { @MainActor in guard let current = self.currentUtterance, ObjectIdentifier(current) == identity else { return }; self.currentUtterance = nil; self.speaking = false }
    }
}
