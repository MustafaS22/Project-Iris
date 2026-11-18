import Foundation

/// Readiness uses model discovery, never an extra paid inference request.
enum ProviderReadiness {
    static func model(requested: String, available: [String]) throws -> String {
        let requested = requested.trimmingCharacters(in: .whitespacesAndNewlines)
        if !requested.isEmpty { return requested } // A valid configured model need not appear in every provider's catalogue.
        guard let first = available.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.lowercased().contains("embedding") && !$0.lowercased().contains("rerank") }) else {
            throw IrisFailure.message("No chat model is available. Load a model in your server, or connect an AI account in Settings → AI.")
        }
        return first
    }
}
