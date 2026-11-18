import Foundation

enum StreamingPresentation {
    static func withoutReasoning(_ source: String) -> String {
        var text = source
        for tag in ["think", "analysis", "reasoning"] {
            text = text.replacingOccurrences(of: "(?is)<" + tag + "\\b[^>]*>.*?(?:</" + tag + "\\s*>|\\z)", with: "", options: .regularExpression)
        }
        return text
    }
    static func visibleText(_ source: String) -> String {
        var text = withoutReasoning(source)
        // Hold incomplete markup that could be a private-reasoning tag.
        if let start = text.lastIndex(of: "<") {
            let tail = text[start...].lowercased()
            if ["<think", "<analysis", "<reasoning"].contains(where: { $0.hasPrefix(tail) }) { text = String(text[..<start]) }
        }
        // A fenced block is released only when complete and classified by the normal filter.
        var search = text.startIndex, open: String.Index?
        while let fence = text.range(of: "```", range: search..<text.endIndex) {
            open = open == nil ? fence.lowerBound : nil; search = fence.upperBound
        }
        if let open { text = String(text[..<open]) }
        while text.hasSuffix("`") { text.removeLast() }
        // Never expose a partial JSON object before we know whether it is action transport.
        var depth = 0, quoted = false, escaped = false, start: String.Index?
        for i in text.indices {
            let c = text[i]
            if quoted { if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { quoted = false }; continue }
            if c == "\"", depth > 0 { quoted = true }
            else if c == "{" { if depth == 0 { start = i }; depth += 1 }
            else if c == "}", depth > 0 { depth -= 1; if depth == 0 { start = nil } }
        }
        if let start { text = String(text[..<start]) }
        text = text.components(separatedBy: "```iris-study")[0]
        return ResponsePresentation.visibleText(text)
    }
    static func status(for raw: String, visible: String) -> String {
        if raw.contains("```iris-actions") || raw.contains("\"actions\"") { return "Preparing an action for review" }
        if raw.contains("```iris-study") { return "Preparing study material" }
        return visible.isEmpty ? "Waiting for answer text" : "Writing the answer"
    }
}
