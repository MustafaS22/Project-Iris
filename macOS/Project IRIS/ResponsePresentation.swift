import Foundation

/// Presentation filtering never authorizes execution; only the tagged action protocol can do that.
enum ResponsePresentation {
    static func visibleText(_ source: String) -> String {
        var text = StreamingPresentation.withoutReasoning(source)
        var removed = false
        let fenced = try! NSRegularExpression(pattern: "(?ms)```([^\\n`]*)\\n?(.*?)(?:```|\\z)")
        for match in fenced.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: text), let label = Range(match.range(at: 1), in: text), let body = Range(match.range(at: 2), in: text) else { continue }
            if text[label].trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("iris-actions") || isCommandJSON(String(text[body])) {
                text.removeSubrange(whole); removed = true
            }
        }
        // Catch bare JSON objects, respecting braces inside quoted file contents.
        var start: String.Index?, depth = 0, quoted = false, escaped = false
        var ranges: [Range<String.Index>] = []
        for i in text.indices {
            let c = text[i]
            if quoted { if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false }; continue }
            if c == "\"", depth > 0 { quoted = true }
            else if c == "{" { if depth == 0 { start = i }; depth += 1 }
            else if c == "}", depth > 0 {
                depth -= 1
                if depth == 0, let start { let range = start..<text.index(after: i); if isCommandJSON(String(text[range])) { ranges.append(range) } }
            }
        }
        for range in ranges.reversed() { text.removeSubrange(range); removed = true }
        if removed {
            text = text.replacingOccurrences(of: "(?im)^.*(?:example of creating a new action|here(?:'s| is) an example action|following (?:internal|backend) commands?).*(?:\\n|$)", with: "", options: .regularExpression)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private static func isCommandJSON(_ text: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], let actions = object["actions"] as? [[String: Any]] else { return false }
        return actions.isEmpty || actions.contains { action in (action["type"] as? String).map { ActionPolicy.types.contains($0) } ?? false }
    }
}
