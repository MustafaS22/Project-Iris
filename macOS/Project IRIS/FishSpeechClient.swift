import Foundation

enum FishSpeechClient {
    static func request(text: String, pcm: Bool = false) throws -> URLRequest {
        let clean = VoiceBoxClient.speechText(text)
        guard !clean.isEmpty, clean.count <= 800 else {
            throw IrisFailure.message("Simonne accepts up to 800 characters per speech segment.")
        }
        var request = URLRequest(url: URL(string: "https://projectiris.lovelyabbey.chatgpt.site/api/voice/simonne")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 75
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["text": clean, "format": pcm ? "pcm" : "mp3"])
        return request
    }
    static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw IrisFailure.message("Simonne returned an invalid response.") }
        if http.statusCode == 429 { throw IrisFailure.message("Simonne’s shared voice limit has been reached. Please try again later.") }
        guard http.statusCode == 200, http.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("audio/") == true else {
            throw IrisFailure.message("Simonne is temporarily unavailable. Your text reply is kept.")
        }
    }
    static func audio(text: String) async throws -> Data {
        let (bytes, response) = try await URLSession.shared.data(for: request(text: text))
        try Task.checkCancellation()
        try validate(response)
        return bytes
    }
    static func stream(text: String, onAudio: @escaping @MainActor (Data) throws -> Void) async throws {
        let (bytes, response) = try await URLSession.shared.bytes(for: request(text: text, pcm: true))
        try validate(response)
        var chunk = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            chunk.append(byte)
            if chunk.count >= 8192 {
                try await onAudio(chunk)
                chunk.removeAll(keepingCapacity: true)
            }
        }
        if !chunk.isEmpty { try await onAudio(chunk) }
    }
}
