import Foundation

enum IrisStream {
    static func text(from line: String) throws -> String {
        guard line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if object["error"] != nil { throw StreamFailure.providerError }
        let candidates = object["candidates"] as? [[String: Any]] ?? []
        // Only the first candidate belongs to the answer. Thought parts are never displayed.
        let parts = (candidates.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]] ?? []
        return parts.filter { ($0["thought"] as? Bool) != true }.compactMap { $0["text"] as? String }.joined()
    }
    enum OpenAIEvent: Equatable { case delta(String), completed, ignore }
    static func openAI(_ line: String) throws -> OpenAIEvent {
        guard line.hasPrefix("data: "), let data = line.dropFirst(6).data(using: .utf8),
              let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .ignore }
        switch event["type"] as? String {
        case "response.output_text.delta": return .delta(event["delta"] as? String ?? "")
        case "response.completed": return .completed
        case "error", "response.failed", "response.incomplete": throw StreamFailure.providerError
        default: return .ignore
        }
    }
    enum StreamFailure: Error { case providerError }
}
