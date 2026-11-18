import Foundation

/// Small, attributed facts only. Other people's messages and assistant guesses are not a profile.
enum InlinePersonalContext {
    static func context(preferences: Preferences, notes: [String], statements: [String], query: String) -> String {
        var lines: [String] = []
        let name = preferences.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let interests = preferences.interests.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { lines.append("Saved user name: " + String(name.prefix(100))) }
        if preferences.onboarded, preferences.role != .everyday { lines.append("User-selected role: " + preferences.role.rawValue) }
        if !interests.isEmpty { lines.append("User-entered interests: " + String(interests.prefix(400))) }
        let q = query.lowercased()
        let personalQuestion = ["yourself", "about you", "hobbies", "hobby", "interests", "passion", "outside work", "free time", "do for fun", "occupation", "profession", "your work", "your studies", "your education"].contains(where: q.contains)
        let stopWords: Set<String> = ["what", "which", "when", "where", "would", "could", "your", "this", "that", "have", "with", "from", "window", "visible", "nearby", "text", "message", "answer"]
        let terms = Set(q.split { !$0.isLetter }.filter { $0.count > 3 }.map(String.init)).subtracting(stopWords)
        var seen = Set<String>()
        let facts = (notes.prefix(100).map { ($0, "User's saved note") } + statements.prefix(80).map { ($0, "Earlier statement by the user") }).compactMap { raw, source -> (String, Int)? in
            let text = String((raw.components(separatedBy: .newlines).first ?? "").prefix(300)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPersonalFact(text), seen.insert(text.lowercased()).inserted else { return nil }
            let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
            let relevance = terms.intersection(words).count
            guard relevance > 0 || personalQuestion else { return nil }
            return (source + ": " + text, relevance)
        }.sorted { $0.1 > $1.1 }
        lines += facts.prefix(4).map(\.0)
        return String(lines.joined(separator: "\n").prefix(1800))
    }
    static func isPersonalFact(_ input: String) -> Bool {
        let s = input.lowercased()
        guard !s.contains("`"), !s.contains("\""),
              !["pretend", "imagine", "example", "ignore", "instructions", "write", "draft", "password", "api key", "token", "bank", "credit card", "diagnos", "medical", "religio", "politic", "address", "phone", "passport", "social security", "street", "apartment", "i am asking", "i am trying", "i'm trying", "i am looking"].contains(where: s.contains) else { return false }
        return s.range(of: #"^(i (am|study|work|enjoy|like|prefer|speak|learn|play)\b|i['’]m\b|my (name|hobbies|interests|favorite|favourite|job|work|course|school|major|language)\b)"#, options: .regularExpression) != nil
    }
    static func needsVisualText(_ text: String) -> Bool {
        guard let marker = text.range(of: "Visible nearby text:\n") else { return true }
        return text[marker.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines).count < 35
    }
    static let emptyFieldInstruction = """
    EMPTY FIELD: infer whether this is a conversation reply, a survey answer, or a profile field from the focused field label and the nearby visible question/thread. Write the actual answer directly. Do not polish an empty string, offer examples, or ask 'What would you like to say?' when the visible context already identifies the task. For a message such as someone sending notes, a natural thank-you needs no clarification. For a survey, use explicit known user facts to answer in the first person; do not discuss the user in the third person. Use only facts relevant to THIS field and preserve any caveats or contradictions. Past facts may be outdated. Do not invent availability, consent, commitments, opinions, personal details, experiences or yes/no decisions. If a specific essential fact is absent, ask just that question. A new email with no stated purpose still needs direction. Do not send or submit anything.
    """
}
