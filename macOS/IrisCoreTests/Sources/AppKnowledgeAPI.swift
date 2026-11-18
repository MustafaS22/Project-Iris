import Foundation

/// Fixed-host, read-only integrations. The GraphQL POST route is a read query, never a mutation.
enum AppKnowledgeAPI {
    static let tokenSources: Set<KnowledgeConnector> = [.github, .notion, .slack, .todoist, .linear]
    static func request(source: KnowledgeConnector, target: String, token: String) throws -> URLRequest {
        let value = target.trimmingCharacters(in: .whitespacesAndNewlines)
        func matches(_ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
        let address: String
        switch source {
        case .github:
            guard matches("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$"), !value.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { throw Failure.target("Use a GitHub repository as owner/name.") }
            address = "https://api.github.com/repos/\(value)/issues?state=open&sort=updated&per_page=30"
        case .notion:
            guard matches("^[A-Fa-f0-9-]{32,36}$"), value.replacingOccurrences(of: "-", with: "").count == 32 else { throw Failure.target("Enter the 32-character Notion page ID, with or without hyphens.") }
            address = "https://api.notion.com/v1/blocks/\(value)/children?page_size=100"
        case .slack:
            guard matches("^[CGD][A-Z0-9]{5,30}$") else { throw Failure.target("Enter a Slack channel ID such as C0123456789, not a channel name.") }
            address = "https://slack.com/api/conversations.history?channel=\(value)&limit=15"
        case .todoist:
            guard value.isEmpty || matches("^[A-Za-z0-9_-]{1,80}$") else { throw Failure.target("Enter a Todoist project ID, or leave it blank for your active tasks.") }
            address = "https://api.todoist.com/api/v1/tasks?limit=50" + (value.isEmpty ? "" : "&project_id=\(value)")
        case .linear: address = "https://api.linear.app/graphql"
        case .googleChat:
            guard matches("^(spaces/)?[A-Za-z0-9_-]{1,100}$") else { throw Failure.target("Enter a Google Chat space ID, optionally prefixed with spaces/.") }
            let id = value.hasPrefix("spaces/") ? value : "spaces/" + value
            address = "https://chat.googleapis.com/v1/\(id)/messages?pageSize=100&orderBy=createTime%20desc"
        case .googleTasks: address = "https://tasks.googleapis.com/tasks/v1/lists/@default/tasks?maxResults=100&showCompleted=false&showHidden=false"
        default: throw Failure.target("This connection is not supported by this reader.")
        }
        guard !token.isEmpty, !token.contains(where: \.isWhitespace) else { throw Failure.target("Add a valid API token without spaces or line breaks.") }
        var request = URLRequest(url: URL(string: address)!); request.timeoutInterval = 40
        request.setValue(source == .linear ? token : "Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if source == .github { request.setValue("Iris-macOS", forHTTPHeaderField: "User-Agent"); request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version") }
        if source == .notion { request.setValue("2025-09-03", forHTTPHeaderField: "Notion-Version") }
        if source == .linear {
            request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: ["query": "query { viewer { assignedIssues(first: 30) { nodes { id identifier title description url updatedAt } } } }"])
        }
        return request
    }
    static func fetch(source: KnowledgeConnector, target: String, token: String) async throws -> [KnowledgeDocument] {
        let request = try request(source: source, target: target, token: token)
        let session = URLSession(configuration: .ephemeral, delegate: NoAppRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw Failure.target("\(source.name) rejected the import (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Check credentials, resource access, API enablement and rate limits. Existing knowledge was kept.")
        }
        var data = Data()
        for try await byte in bytes { guard data.count < 5_000_000 else { throw Failure.target("The provider response exceeded the 5 MB import limit.") }; data.append(byte) }
        return try documents(data, source: source, target: target)
    }
    static func documents(_ data: Data, source: KnowledgeConnector, target: String) throws -> [KnowledgeDocument] {
        guard data.count <= 5_000_000 else { throw Failure.target("Response too large.") }
        let object = try JSONSerialization.jsonObject(with: data)
        let root = object as? [String: Any] ?? [:]
        if source == .googleChat || source == .googleTasks {
            guard object is [String: Any], root["error"] == nil else { throw Failure.target("Google returned an unsupported response. Existing knowledge was kept.") }
            let key = source == .googleChat ? "messages" : "items"
            if let value = root[key], !(value is [[String: Any]]) { throw Failure.target("Google returned invalid items. Existing knowledge was kept.") }
        }
        if source == .slack, root["ok"] as? Bool != true { throw Failure.target("Slack did not grant history access. Check channel membership, token scopes and rate limits. Existing knowledge was kept.") }
        if source == .linear, root["errors"] != nil { throw Failure.target("Linear could not return assigned issues. Check the key's read permission and workspace access.") }
        func text(_ value: Any?) -> String { value as? String ?? "" }
        func document(_ id: String, _ title: String, _ body: String, _ date: String = "") -> KnowledgeDocument {
            .init(externalID: id, source: source, title: String(title.prefix(500)), body: String(body.prefix(30000)), updatedAt: ISO8601DateFormatter().date(from: date) ?? Date())
        }
        func rows(_ key: String) throws -> [[String: Any]] {
            guard let values = root[key] as? [[String: Any]] else { throw Failure.target("\(source.name) returned an unsupported response. Existing knowledge was kept.") }; return values
        }
        switch source {
        case .github:
            guard let issues = object as? [[String: Any]] else { throw Failure.target("GitHub returned an unsupported response.") }
            return issues.prefix(30).compactMap { item in
                guard let id = item["id"] as? NSNumber else { return nil }
                return document(target + ":" + id.stringValue, text(item["title"]), text(item["html_url"]) + "\n" + text(item["body"]), text(item["updated_at"]))
            }
        case .notion:
            let blocks = try rows("results")
            let body = blocks.prefix(100).map { block -> String in
                let type = text(block["type"]), value = block[text(block["type"])] as? [String: Any] ?? [:]
                let rich = (value["rich_text"] as? [[String: Any]] ?? []).map { text($0["plain_text"]) }.joined()
                return type == "child_page" ? "Child page: " + text(value["title"]) : rich
            }.filter { !$0.isEmpty }.joined(separator: "\n")
            return [document(target, "Notion page · " + String(target.prefix(8)), "Top-level page text only; nested blocks and media are not imported.\n" + body)]
        case .slack:
            return try rows("messages").prefix(15).compactMap { item in
                let body = text(item["text"]); guard !body.isEmpty else { return nil }
                return document(target + ":" + text(item["ts"]), "Slack · " + target, "Sender: " + text(item["user"]) + "\n" + body)
            }
        case .todoist:
            return try rows("results").prefix(50).compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                let due = item["due"] as? [String: Any] ?? [:]
                return document(id, text(item["content"]), text(item["description"]) + "\nDue: " + text(due["date"]))
            }
        case .linear:
            guard let data = root["data"] as? [String: Any], let viewer = data["viewer"] as? [String: Any], let assigned = viewer["assignedIssues"] as? [String: Any], let issues = assigned["nodes"] as? [[String: Any]] else { throw Failure.target("Linear returned an unsupported response.") }
            return issues.prefix(30).compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                return document(id, text(item["identifier"]) + " · " + text(item["title"]), text(item["url"]) + "\n" + text(item["description"]), text(item["updatedAt"]))
            }
        case .googleChat:
            let messages = root["messages"] as? [[String: Any]] ?? []
            return messages.prefix(100).compactMap { item in
                let body = text(item["text"]); guard !body.isEmpty else { return nil }
                return document(text(item["name"]), "Google Chat · " + target, body, text(item["createTime"]))
            }
        case .googleTasks:
            return (root["items"] as? [[String: Any]] ?? []).prefix(100).compactMap { item in
                guard let id = item["id"] as? String else { return nil }
                return document(id, text(item["title"]), text(item["notes"]) + "\nDue: " + text(item["due"]), text(item["updated"]))
            }
        default: throw Failure.target("Unsupported source.")
        }
    }
    enum Failure: LocalizedError { case target(String); var errorDescription: String? { if case let .target(message) = self { return message }; return nil } }
}
private final class NoAppRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}
