import Foundation

/// Parses known export structures as data; JavaScript archives are never executed.
enum SocialExportReader {
    static let sources: Set<KnowledgeConnector> = [.instagram, .x, .telegram]
    static func read(_ data: Data, source: KnowledgeConnector, title: String) throws -> [KnowledgeDocument] {
        guard data.count <= 10_000_000 else { throw Failure.invalid("Choose export files no larger than 10 MB.") }
        var bytes = data
        if source == .x, var string = String(data: data, encoding: .utf8), !string.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("[") {
            let pattern = "^\\s*window\\.YTD\\.tweets?\\.part[0-9]+\\s*=\\s*"
            guard let prefix = string.range(of: pattern, options: .regularExpression) else { throw Failure.invalid("Choose tweets.js or a JSON post array from your X archive.") }
            string.removeSubrange(prefix); string = string.trimmingCharacters(in: .whitespacesAndNewlines)
            if string.hasSuffix(";") { string.removeLast() }; bytes = Data(string.utf8)
        }
        let object = try JSONSerialization.jsonObject(with: bytes)
        func text(_ value: Any?) -> String { value as? String ?? "" }
        func doc(_ id: String, _ name: String, _ body: String) -> KnowledgeDocument { .init(externalID: id, source: source, title: name, body: String(body.prefix(30000)), updatedAt: Date()) }
        switch source {
        case .x:
            guard let posts = object as? [[String: Any]] else { throw Failure.invalid("Choose a post array from your X archive.") }
            let documents = posts.prefix(100).compactMap { value -> KnowledgeDocument? in
                let post = value["tweet"] as? [String: Any] ?? value
                guard let body = post["full_text"] as? String, let id = post["id_str"] as? String else { return nil }
                return doc(id, "X post · " + String(body.prefix(70)), text(post["created_at"]) + "\n" + body)
            }
            guard !documents.isEmpty else { throw Failure.invalid("No supported posts were found. Choose tweets.js; DMs and other archive files are not supported.") }; return documents
        case .instagram, .telegram:
            guard let chat = object as? [String: Any], let messages = chat["messages"] as? [[String: Any]] else { throw Failure.invalid("Choose one exported chat JSON file. Full-account archives and ZIP files are not imported.") }
            let recent = source == .instagram ? Array(messages.prefix(400).reversed()) : Array(messages.suffix(400))
            let lines = recent.compactMap { message -> String? in
                if message["is_unsent"] as? Bool == true { return nil }
                let body: String
                if source == .instagram { body = text(message["content"]) }
                else if let value = message["text"] as? String { body = value }
                else { body = (message["text"] as? [Any] ?? []).map { ($0 as? String) ?? text(($0 as? [String: Any])?["text"]) }.joined() }
                guard !body.isEmpty else { return nil }
                return text(message[source == .instagram ? "sender_name" : "from"]) + ": " + body
            }
            guard !lines.isEmpty else { throw Failure.invalid("No exported text messages were found in this file.") }
            let name = text(chat[source == .instagram ? "title" : "name"])
            return [doc(title, name.isEmpty ? title : name, String(lines.joined(separator: "\n").suffix(30000)))]
        default: throw Failure.invalid("Unsupported export source.")
        }
    }
    enum Failure: LocalizedError { case invalid(String); var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil } }
}
