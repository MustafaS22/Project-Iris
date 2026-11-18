import Foundation

struct ProviderStream {
    enum Kind { case openAI, gemini, local }
    var kind: Kind
    private(set) var text = ""
    private(set) var completed = false
    mutating func consume(_ line: String) throws {
        guard line.hasPrefix("data:") else { return }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { if kind == .local { completed = true }; return }
        guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { return }
        if object["error"] != nil { throw IrisFailure.message("The provider interrupted the response.") }
        switch kind {
        case .openAI:
            let type = object["type"] as? String ?? ""
            if type == "response.output_text.delta" { text += object["delta"] as? String ?? "" }
            if type == "response.completed" { completed = true }
            if ["response.failed", "response.incomplete", "error"].contains(type) { throw IrisFailure.message("The provider couldn't finish the response.") }
        case .local:
            guard let choices = object["choices"] as? [[String: Any]], let choice = choices.first else { return }
            let delta = choice["delta"] as? [String: Any] ?? [:]
            // reasoning_content and reasoning fields intentionally never become answer text.
            text += delta["content"] as? String ?? ""
            if let finish = choice["finish_reason"] as? String {
                guard finish == "stop" else { throw IrisFailure.message("The local model stopped before finishing (\(finish)).") }
                completed = true
            }
        case .gemini:
            guard let candidate = (object["candidates"] as? [[String: Any]])?.first else { return }
            let content = candidate["content"] as? [String: Any] ?? [:]
            for part in content["parts"] as? [[String: Any]] ?? [] where part["thought"] as? Bool != true { text += part["text"] as? String ?? "" }
            if let finish = candidate["finishReason"] as? String {
                guard finish == "STOP" else { throw IrisFailure.message("Gemini stopped before finishing (\(finish)).") }
                completed = true
            }
        }
        guard text.utf8.count < 500000 else { throw IrisFailure.message("The response exceeded the size limit.") }
    }
}
