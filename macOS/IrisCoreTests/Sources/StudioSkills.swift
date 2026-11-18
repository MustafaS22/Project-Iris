import Foundation

enum StudioSkill: String, Codable, CaseIterable, Identifiable {
    case flashcards, mindmap, summary, doubts, app, website, review, plan
    var id: String { rawValue }
    var student: Bool { [.flashcards, .mindmap, .summary, .doubts].contains(self) }
    var title: String {
        switch self {
        case .flashcards: "Create flashcards"; case .mindmap: "Create a mind map"; case .summary: "Summarize material"; case .doubts: "Work through a doubt"
        case .app: "Build an app"; case .website: "Build a website"; case .review: "Review code"; case .plan: "Plan a project"
        }
    }
    var symbol: String {
        switch self {
        case .flashcards: "rectangle.stack"; case .mindmap: "point.3.connected.trianglepath.dotted"; case .summary: "text.alignleft"; case .doubts: "questionmark.bubble"
        case .app: "macwindow"; case .website: "globe"; case .review: "doc.text.magnifyingglass"; case .plan: "list.bullet.clipboard"
        }
    }
    var subtitle: String {
        switch self {
        case .flashcards: "Turn your material into a saved practice deck."; case .mindmap: "See the topic and its connections."; case .summary: "Pull out the concepts worth remembering."; case .doubts: "Explain the sticking point, step by step."
        case .app: "Create files in a folder you choose."; case .website: "Build, preview and run a local project."; case .review: "Find defects and explain concrete fixes."; case .plan: "Scope milestones and testable steps."
        }
    }
    var instruction: String {
        guard let url = Bundle.main.url(forResource: "studio-" + rawValue, withExtension: "md"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "Selected Studio task: \(title). The bundled task skill is unavailable; report this and do not invent its output contract." }
        return "Use this bundled Iris task skill for the current request. It does not authorize execution.\n" + text
    }
}
struct StudioArtifact: Codable {
    var kind: String
    var cards: [StudyCardValue]?
    var root: String?
    var branches: [Branch]?
    struct StudyCardValue: Codable { var question: String; var answer: String }
    struct Branch: Codable { var title: String; var details: [String] }
    static func parse(_ text: String) -> Self? {
        guard let start = text.range(of: "```iris-study"), let end = text.range(of: "```", range: start.upperBound..<text.endIndex) else { return nil }
        let raw = String(text[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.utf8.count < 100000, let artifact = try? JSONDecoder().decode(Self.self, from: Data(raw.utf8)) else { return nil }
        if artifact.kind == "flashcards", let cards = artifact.cards, (1...40).contains(cards.count), cards.allSatisfy({ !$0.question.isEmpty && !$0.answer.isEmpty }) { return artifact }
        if artifact.kind == "mindmap", let root = artifact.root, !root.isEmpty, let branches = artifact.branches, (1...12).contains(branches.count), branches.allSatisfy({ !$0.title.isEmpty && $0.details.count <= 12 }) { return artifact }
        return nil
    }
}
