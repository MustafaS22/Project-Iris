import Foundation
import CoreGraphics

enum WelcomeStage: String, Codable, CaseIterable { case interview, notch, floating, drafting, explore, review, complete }
struct WelcomeProgress: Codable, Equatable {
    var stage: WelcomeStage = .interview
    var questionIndex = 0
    var answers: [String: String] = [:]
    var completed: Set<String> = []
    var skipped: Set<String> = []
    var notchOpened = false
    var floatingOpened = false
    var floatingDragged = false
    var starterPlan: String? = nil
    var demoTarget: String? = nil
    static let prompts: [(id: String, question: String)] = [
        ("name", "Hi, I’m Iris. What should I call you?"),
        ("work", "What’s your world like right now—studying, working, building something, or a mix?"),
        ("project", "What’s one thing you’re working on that you’d like a hand with?"),
        ("help", "And how do you like help: quick answers, a plan, or someone to walk through things with you?")
    ]
    mutating func normalize() {
        questionIndex = min(Self.prompts.count - 1, max(0, questionIndex))
        answers = answers.filter { entry in Self.prompts.contains { $0.id == entry.key } }.mapValues { String($0.prefix(480)) }
        starterPlan = starterPlan.map { String($0.prefix(4000)) }
        if !["sun", "earth", "moon"].contains(demoTarget ?? "") { demoTarget = nil }
    }
    mutating func recordAnswer(_ raw: String) {
        guard stage == .interview, Self.prompts.indices.contains(questionIndex) else { return }
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(480))
        guard !text.isEmpty else { return }; answers[Self.prompts[questionIndex].id] = text
        questionIndex += 1
        if questionIndex == Self.prompts.count { completed.insert("interview"); stage = .notch }
    }
    mutating func advance(skipping: Bool = false) {
        if stage == .interview {
            if skipping { questionIndex += 1; if questionIndex >= Self.prompts.count { skipped.insert("interview"); stage = .notch } }
            return
        }
        guard let index = WelcomeStage.allCases.firstIndex(of: stage), index + 1 < WelcomeStage.allCases.count else { return }
        if skipping { skipped.insert(stage.rawValue) } else if stage != .review && stage != .explore && !completed.contains(stage.rawValue) { return }
        stage = WelcomeStage.allCases[index + 1]
    }
    mutating func noteReply() {
        if stage == .notch, notchOpened { completed.insert("notch") }
        if stage == .floating, floatingOpened, floatingDragged { completed.insert("floating") }
    }
    var canAdvance: Bool { stage == .explore || stage == .review || completed.contains(stage.rawValue) }
    var savedDetails: [(String, String)] { Self.prompts.compactMap { prompt in answers[prompt.id].map { (prompt.id, $0) } } }
    var firstName: String { let name = answers["name"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""; return name.count <= 32 && name.split(separator: " ").count <= 4 ? name : "" }
    var starterPrompt: String {
        let project = (answers["project"] ?? "a small goal for today").replacingOccurrences(of: "@", with: " at ")
        return "Help me take the first useful step with this: \(project). Give me a practical three-step starting plan. Only write a plan; do not perform actions or create an agent. Ask one question if you need an essential detail; don’t invent deadlines or facts."
    }
    var practiceDraft: String {
        let name = firstName.isEmpty ? "me" : firstName
        return "thanks sam got your notes. \(name) will take a look and get back to you with some thoughts"
    }
    var cue: String {
        switch stage {
        case .interview: return "Just a conversation. Say ‘skip’ whenever you like."
        case .notch: return !notchOpened ? "Try your summon shortcut." : !canAdvance ? "Let’s make something useful from what you told me." : "Your first result. Take a moment with it."
        case .floating: return !floatingOpened ? "Bring me out onto your desktop." : !floatingDragged ? "Grab my face and move me somewhere comfortable." : canAdvance ? "Same assistant. A little closer to your work." : demoTarget == nil ? "Try pointing at something on the practice canvas." : "Now ask me a question, by voice or typing."
        case .drafting: return canAdvance ? "It’s in the field. You keep the final say." : "Click in the practice draft, then double-tap your drafting key."
        case .explore: return "One more trick: type @ in a real chat."
        case .review: return "You choose what stays with me."
        case .complete: return "Ready when you are."
        }
    }
}
/// Placement uses AppKit coordinates, including secondary displays with negative origins.
enum WelcomeCoachPlacement {
    static func frame(near target: CGRect, size: CGSize, bounds: CGRect) -> CGRect {
        let width = min(size.width, max(0, bounds.width - 24)), height = min(size.height, max(0, bounds.height - 24))
        let candidates = [
            CGRect(x: target.midX - width / 2, y: target.minY - height - 18, width: width, height: height),
            CGRect(x: target.maxX + 18, y: target.midY - height / 2, width: width, height: height),
            CGRect(x: target.minX - width - 18, y: target.midY - height / 2, width: width, height: height),
            CGRect(x: target.midX - width / 2, y: target.maxY + 18, width: width, height: height)
        ]
        let fitted = candidates.map { base in CGRect(x: min(max(base.minX, bounds.minX + 12), bounds.maxX - width - 12), y: min(max(base.minY, bounds.minY + 12), bounds.maxY - height - 12), width: width, height: height) }
        return fitted.first(where: { !$0.intersects(target) }) ?? fitted[0]
    }
}
