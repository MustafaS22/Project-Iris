import Foundation
import AVFoundation
import CryptoKit

@MainActor final class IrisVoice {
    static let shared = IrisVoice()
    static let voices = ["Sulafat", "Kore", "Aoede", "Puck", "Charon", "Zephyr"]
    private let synthesizer = AVSpeechSynthesizer()
    private var player: AVAudioPlayer?
    private var cache: [String: Data] = [:]
    private var generation = UUID()
    private var coolingUntil = Date.distantPast

    func stop() {
        generation = UUID(); player?.stop(); synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func play(_ text: String, preview: Bool = false) async throws {
        let text = String(text.replacingOccurrences(of: #"[`*_#]"#, with: "", options: .regularExpression).prefix(preview ? 180 : 900))
        guard !text.isEmpty else { return }
        let id = UUID(); generation = id
        let audio = AVAudioSession.sharedInstance()
        try audio.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
        try audio.setActive(true)
        defer { if generation == id { player?.stop(); try? audio.setActive(false, options: .notifyOthersOnDeactivation) } }
        if UserDefaults.standard.string(forKey: "IrisVoiceProvider") == "gemini" {
            guard Date.now >= coolingUntil else { throw IrisError.message("Gemini voice is cooling down after a quota limit. Text still works.") }
            let key = IrisKey.read()
            guard !key.isEmpty else { throw IrisError.message("Save a Gemini API key to use Gemini voice, even if chat uses OpenAI.") }
            let voice = UserDefaults.standard.string(forKey: "IrisGeminiVoice") ?? "Sulafat"
            let model = "gemini-3.8-flash-lite-tts"
            let cacheKey = SHA256.hash(data: Data((model + voice + text).utf8)).map { String(format: "%02x", $0) }.joined()
            let data: Data
            if let saved = cache[cacheKey] { data = saved }
            else {
                var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!, timeoutInterval: 45)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
                request.httpBody = try JSONSerialization.data(withJSONObject: [
                    "model": model,
                    "input": [["type": "user_input", "content": [["type": "text", "text": text, "annotations": [["type": "speech_metadata", "style": "Warm, clear, natural conversational speech."]]]]]],
                    "response_format": ["type": "audio", "mime_type": "audio/wav"],
                    "generation_config": ["speech_config": [["voice": voice]]]
                ])
                let (response, raw) = try await URLSession.shared.data(for: request)
                guard let http = raw as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    if (raw as? HTTPURLResponse)?.statusCode == 429 { coolingUntil = .now.addingTimeInterval(60) }
                    throw IrisError.message("Gemini voice returned HTTP \((raw as? HTTPURLResponse)?.statusCode ?? 0). Text is kept. Check voice API access or quota; no automatic retry was sent.")
                }
                data = try IrisAudio.decode(response)
                if preview { if cache.count >= 8 { cache.removeAll() }; cache[cacheKey] = data }
            }
            try Task.checkCancellation()
            guard generation == id else { throw CancellationError() }
            let player = try AVAudioPlayer(data: data); self.player = player
            guard player.play() else { throw IrisError.message("Couldn’t play the generated voice.") }
            while player.isPlaying { guard generation == id else { throw CancellationError() }; try await Task.sleep(for: .milliseconds(80)) }
        } else {
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.language.languageCode?.identifier ?? "en")
            synthesizer.speak(utterance)
            try await Task.sleep(for: .milliseconds(100))
            while synthesizer.isSpeaking { guard generation == id else { throw CancellationError() }; try await Task.sleep(for: .milliseconds(80)) }
        }
    }
}
