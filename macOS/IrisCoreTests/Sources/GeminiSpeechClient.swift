import Foundation

struct GeminiVoice: Identifiable, Equatable {
    var name: String
    var tone: String
    var id: String { name }
}
struct GeminiSpeechQuotaError: LocalizedError {
    var retryAfter: TimeInterval
    var errorDescription: String? { "Gemini speech hit a rate or quota limit. Speech is paused briefly; text replies still work. No automatic retry was sent. Check your project's limits in Google AI Studio." }
}

enum GeminiSpeechCredential { case apiKey(String), bearer(String, project: String?) }

/// Stateless, text-only speech generation, separate from Iris's chat model and tools.
enum GeminiSpeechClient {
    static let defaultModel = "gemini-3.8-flash-lite-tts"
    static let models = ["gemini-3.8-flash-tts", "gemini-3.8-flash-lite-tts"]
    static let defaultVoice = "Sulafat"
    static let voices: [GeminiVoice] = [
        .init(name: "Sulafat", tone: "Warm"), .init(name: "Algieba", tone: "Smooth"), .init(name: "Charon", tone: "Informative"), .init(name: "Kore", tone: "Firm"), .init(name: "Aoede", tone: "Breezy"), .init(name: "Puck", tone: "Upbeat"),
        .init(name: "Zephyr", tone: "Bright"), .init(name: "Fenrir", tone: "Excitable"), .init(name: "Leda", tone: "Youthful"), .init(name: "Orus", tone: "Firm"), .init(name: "Callirrhoe", tone: "Easy-going"), .init(name: "Autonoe", tone: "Bright"), .init(name: "Enceladus", tone: "Breathy"), .init(name: "Iapetus", tone: "Clear"), .init(name: "Umbriel", tone: "Easy-going"), .init(name: "Despina", tone: "Smooth"), .init(name: "Erinome", tone: "Clear"), .init(name: "Algenib", tone: "Gravelly"), .init(name: "Rasalgethi", tone: "Informative"), .init(name: "Laomedeia", tone: "Upbeat"), .init(name: "Achernar", tone: "Soft"), .init(name: "Alnilam", tone: "Firm"), .init(name: "Schedar", tone: "Even"), .init(name: "Gacrux", tone: "Mature"), .init(name: "Pulcherrima", tone: "Forward"), .init(name: "Achird", tone: "Friendly"), .init(name: "Zubenelgenubi", tone: "Casual"), .init(name: "Vindemiatrix", tone: "Gentle"), .init(name: "Sadachbia", tone: "Lively"), .init(name: "Sadaltager", tone: "Knowledgeable")
    ]
    static let styles = ["Natural", "Warm", "Calm", "Focused"]
    static func request(text: String, voice: String, model: String, style: String, credential: GeminiSpeechCredential) throws -> URLRequest {
        guard models.contains(model), voices.contains(where: { $0.name == voice }), styles.contains(style) else { throw IrisFailure.message("Choose a supported Gemini speech model, voice and delivery style in Settings → Voice.") }
        let transcript = VoiceBoxClient.speechText(text)
        guard !transcript.isEmpty else { throw IrisFailure.message("This response has no text to read aloud.") }
        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/interactions")!)
        request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch credential {
        case .apiKey(let key):
            guard !key.isEmpty else { throw IrisFailure.message("Add a Gemini API key in Settings → Voice.") }
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        case .bearer(let token, let project):
            guard !token.isEmpty else { throw IrisFailure.message("Reconnect your Gemini account in Settings → AI.") }
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
            if let project, !project.isEmpty { request.setValue(project, forHTTPHeaderField: "x-goog-user-project") }
        }
        let delivery: String
        switch style {
        case "Warm": delivery = "Warm, friendly and reassuring. Conversational, with natural pauses."
        case "Calm": delivery = "Calm, composed and relaxed. Clear articulation, with gentle natural pauses."
        case "Focused": delivery = "Confident, clear and concise. A composed personal assistant, with natural conversational delivery."
        default: delivery = "Natural, friendly conversational speech. Clear articulation and comfortable pacing, without an exaggerated announcer voice."
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "store": false,
            "input": [["type": "user_input", "content": [["type": "text", "text": transcript, "annotations": [["type": "speech_metadata", "style": delivery + " " + SpeechRendering.delivery]]]]]],
            "response_format": ["type": "audio", "mime_type": "audio/wav"],
            "generation_config": ["speech_config": [["voice": voice]]]
        ])
        return request
    }
    static func audio(text: String, voice: String, model: String, style: String, credential: GeminiSpeechCredential, session: URLSession = .shared) async throws -> Data {
        try Task.checkCancellation()
        let request = try request(text: text, voice: voice, model: model, style: style, credential: credential)
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
                case 401, 403: throw IrisFailure.message("Google denied Gemini speech access. Check the API key or reconnect Gemini; enable Generative Language API and verify project/model access. Your text reply is kept.")
                case 429: throw GeminiSpeechQuotaError(retryAfter: max(60, Double((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60))
                case 400, 404: throw IrisFailure.message("The selected Gemini speech model or voice isn't available to this project. Try the other speech model in Settings → Voice.")
                default: throw IrisFailure.message("Gemini couldn't generate speech. Your text reply is kept; try Preview again later.")
                }
            }
            return try decode(data)
        } catch let error as URLError where error.code != .cancelled {
            throw IrisFailure.message("Gemini speech couldn't finish. Check your internet connection, then try Preview again. No automatic retry was sent.")
        }
    }
    static func streamRequest(text: String, voice: String, model: String, style: String, credential: GeminiSpeechCredential) throws -> URLRequest {
        var request = try request(text: text, voice: voice, model: model, style: style, credential: credential)
        var body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
        body["stream"] = true
        body["response_format"] = ["type": "audio", "mime_type": "audio/l16", "sample_rate": 24000]
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }
    static func stream(text: String, voice: String, model: String, style: String, credential: GeminiSpeechCredential, session: URLSession = .shared, onAudio: @escaping @MainActor (Data) throws -> Void) async throws {
        try Task.checkCancellation()
        let request = try streamRequest(text: text, voice: voice, model: model, style: style, credential: credential)
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 429 { throw GeminiSpeechQuotaError(retryAfter: max(60, Double((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 60)) }
            throw IrisFailure.message("Gemini speech was rejected (HTTP \(code)). Check speech API access and the selected model. Your text answer is kept.")
        }
        var stream = GeminiAudioStream()
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if let data = try stream.consume(line) { try await onAudio(data) }
            if stream.completed { break }
        }
        guard stream.completed else { throw IrisFailure.message("Gemini's audio stream ended early. Your text answer is kept.") }
    }
    static func decode(_ data: Data) throws -> Data {
        guard data.count <= 36_000_000, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], object["status"] as? String == "completed",
              let steps = object["steps"] as? [[String: Any]] else { throw IrisFailure.message("Gemini returned an incomplete speech response. No audio was played.") }
        let parts = steps.filter { $0["type"] as? String == "model_output" }.flatMap { $0["content"] as? [[String: Any]] ?? [] }.filter { $0["type"] as? String == "audio" }
        guard let part = parts.last, (part["mime_type"] as? String)?.lowercased() == "audio/wav",
              let encoded = part["data"] as? String, let audio = Data(base64Encoded: encoded), audio.count > 44, audio.count <= 25_000_000,
              audio.starts(with: Data("RIFF".utf8)), audio.subdata(in: 8..<12) == Data("WAVE".utf8) else { throw IrisFailure.message("Gemini returned no valid WAV speech. No audio was played.") }
        return audio
    }
}
