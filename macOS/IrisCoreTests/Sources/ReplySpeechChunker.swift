import Foundation

enum SpeechReplyPolicy {
    static func shouldSpeak(floating: Bool, spoken: Bool, speakVoice: Bool, speakTyped: Bool) -> Bool {
        floating || (spoken ? speakVoice : speakTyped)
    }
}

/// Release stable sentence-sized text once. Never speak unfinished transport or code blocks.
struct ReplySpeechChunker {
    private(set) var committed = ""
    private(set) var invalidated = false
    private var chunks = 0
    let economy: Bool
    init(economy: Bool = false) { self.economy = economy }
    mutating func update(_ raw: String, final: Bool = false) -> [String] {
        guard !invalidated else { return [] }
        let clean = String(VoiceBoxClient.speechText(StreamingPresentation.visibleText(raw)).prefix(economy ? 360 : 2000))
        if economy, chunks >= 1 { return [] }
        guard clean.hasPrefix(committed) else { invalidated = true; return [] }
        var remaining = String(clean.dropFirst(committed.count)), output: [String] = []
        while !remaining.isEmpty {
            let limit = economy ? 360 : (chunks == 0 ? 180 : 360)
            let minimum = economy ? 120 : (chunks == 0 ? 20 : 160)
            var cut: String.Index?
            for i in remaining.indices {
                let next = remaining.index(after: i)
                let c = remaining[i]
                if ".!?。？！".contains(c), (next < remaining.endIndex && remaining[next].isWhitespace || final && next == remaining.endIndex), remaining.distance(from: remaining.startIndex, to: next) >= minimum {
                    let prefix = String(remaining[..<next]).lowercased()
                    if c == ".", ["mr.", "mrs.", "ms.", "dr.", "e.g.", "i.e.", "vs."].contains(where: { prefix.hasSuffix($0) }) { continue }
                    cut = next; break
                }
                if remaining.distance(from: remaining.startIndex, to: next) >= limit { break }
            }
            // Bound requests per reply. Keep the final request for any remaining text.
            if chunks >= 7 {
                guard final else { break }
                cut = remaining.endIndex
            }
            if cut == nil, remaining.count > limit {
                let end = remaining.index(remaining.startIndex, offsetBy: limit)
                let space = remaining[..<end].lastIndex(where: \.isWhitespace)
                cut = space.map { $0 > remaining.startIndex ? $0 : end } ?? end
            }
            if cut == nil, final || economy && clean.count >= 360 {
                if economy, !final, let space = remaining.lastIndex(where: \.isWhitespace) { cut = space }
                else { cut = remaining.endIndex }
            }
            guard let end = cut, end > remaining.startIndex else { break }
            let segment = String(remaining[..<end])
            committed += segment
            let spoken = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            if !spoken.isEmpty { output.append(spoken); chunks += 1 }
            remaining = String(remaining[end...])
            if economy { break }
        }
        return output
    }
}

/// Strictly parse Gemini's audio deltas and completion events. No transcript or reasoning is played.
struct GeminiAudioStream {
    private(set) var completed = false
    private(set) var receivedBytes = 0
    mutating func consume(_ line: String) throws -> Data? {
        guard line.hasPrefix("data:"), !completed else { return nil }
        let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]" else { return nil }
        guard payload.utf8.count < 2_000_000, let bytes = payload.data(using: .utf8), let event = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw IrisFailure.message("Gemini sent an invalid audio stream.") }
        let type = event["event_type"] as? String ?? ""
        if type == "error" || type == "interaction.failed" || type == "interaction.cancelled" || type == "interaction.incomplete" { throw IrisFailure.message("Gemini speech was interrupted. Your text answer is kept.") }
        if type == "interaction.completed" {
            if let status = (event["interaction"] as? [String: Any])?["status"] as? String, status != "completed" { throw IrisFailure.message("Gemini returned incomplete speech.") }
            guard receivedBytes > 0, receivedBytes % 2 == 0 else { throw IrisFailure.message("Gemini returned no complete audio samples.") }
            completed = true; return nil
        }
        guard type == "step.delta", let delta = event["delta"] as? [String: Any], delta["type"] as? String == "audio" else { return nil }
        if let mime = delta["mime_type"] as? String, mime.components(separatedBy: ";")[0].lowercased() != "audio/l16" { throw IrisFailure.message("Gemini returned an unsupported streaming audio format.") }
        guard let encoded = delta["data"] as? String, let data = Data(base64Encoded: encoded), !data.isEmpty, receivedBytes + data.count <= 25_000_000 else { throw IrisFailure.message("Gemini returned invalid streaming audio.") }
        receivedBytes += data.count; return data
    }
}

struct PCM16Stream {
    private var pending: UInt8?
    mutating func append(_ data: Data) -> [Float] {
        var bytes = Array(data)
        if let pending { bytes.insert(pending, at: 0); self.pending = nil }
        if bytes.count % 2 != 0 { pending = bytes.removeLast() }
        return stride(from: 0, to: bytes.count, by: 2).map { i in Float(Int16(bitPattern: UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8)) / 32768 }
    }
}
