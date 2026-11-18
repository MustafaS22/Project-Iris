import Foundation

enum IrisAudio {
    static func decode(_ data: Data) throws -> Data {
        guard data.count < 30_000_000,
              let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any], payload["status"] as? String == "completed",
              let steps = payload["steps"] as? [[String: Any]] else { throw IrisAudioFailure("Gemini returned incomplete speech.") }
        let parts = steps.filter { $0["type"] as? String == "model_output" }.flatMap { $0["content"] as? [[String: Any]] ?? [] }
        guard let part = parts.last(where: { $0["type"] as? String == "audio" }), part["mime_type"] as? String == "audio/wav",
              let encoded = part["data"] as? String, let wav = Data(base64Encoded: encoded), wav.count > 44, wav.count < 20_000_000,
              wav.starts(with: Data("RIFF".utf8)), wav.subdata(in: 8..<12) == Data("WAVE".utf8) else { throw IrisAudioFailure("Gemini returned no playable WAV audio.") }
        return wav
    }
}

struct IrisAudioFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
