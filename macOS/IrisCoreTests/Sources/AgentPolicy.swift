import Foundation

/// Routing is local: a greeting or a short question never incurs a planning request.
enum AgentSpecialty: String, Codable, CaseIterable {
    case builder, researcher, writer, analyst, generalist
    var name: String { switch self { case .builder: "Forge"; case .researcher: "Scout"; case .writer: "Quill"; case .analyst: "Prism"; case .generalist: "Atlas" } }
    var title: String { switch self { case .builder: "Development"; case .researcher: "Research"; case .writer: "Writing"; case .analyst: "Analysis & study"; case .generalist: "Custom specialist" } }
    var symbol: String { switch self { case .builder: "hammer.fill"; case .researcher: "binoculars.fill"; case .writer: "pencil.tip.crop.circle.fill"; case .analyst: "chart.bar.xaxis"; case .generalist: "sparkles" } }
    var instruction: String {
        switch self {
        case .builder: "Build complete, usable projects. Inspect supplied code, implement the requested behavior and explain how to run it. Never claim a build or test passed without actual tool evidence."
        case .researcher: "Compare evidence, cite supplied sources and distinguish facts from inference. Use computerTask to read and verify web information through configured MCP/browser tools when necessary. Opening a browser alone is not research evidence. Request sources if the executor cannot establish current facts."
        case .writer: "Produce polished deliverables for the intended audience. Preserve the user's facts and voice. Make a complete draft rather than a list of writing suggestions."
        case .analyst: "Work carefully from supplied material. Check calculations, units and assumptions, structure findings and make useful study material. Flag missing evidence."
        case .generalist: "Choose a narrow working specialty from the user's task, apply it consistently and finish a useful deliverable."
        }
    }
}

enum AgentStatus: String, Codable {
    case queued, running, waiting, completed, failed, stopped, interrupted
    var title: String { switch self { case .queued: "Queued"; case .running: "Working"; case .waiting: "Needs you"; case .completed: "Ready"; case .failed: "Couldn't finish"; case .stopped: "Stopped"; case .interrupted: "Paused after restart" } }
    var active: Bool { self == .queued || self == .running || self == .waiting }
}

struct AgentEvent: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var text: String
}
struct AgentImage: Codable { var data: Data; var mimeType: String }
struct AgentRun: Codable, Identifiable {
    var id = UUID()
    var name: String
    var specialty: AgentSpecialty
    var hue: Double
    var task: String
    var context: String
    var images: [AgentImage] = []
    var preferences: Preferences
    var creation: String?
    var skillID: String?
    var createdAt = Date()
    var updatedAt = Date()
    var status: AgentStatus = .queued
    var phase = "Waiting for a work slot"
    var transcript: [ChatMessage] = []
    var events: [AgentEvent] = []
    var partial = ""
    var result = ""
    var files: [ChatFileReference] = []
    var pending: [AssistantAction] = []
    var approved = false
    var modelTurns = 0
    var actionCount = 0
    var error: String?
    var originConversation: UUID?
}

enum AgentPolicy {
    static let maximumConcurrent = 2
    static let maximumSaved = 30
    static let maximumQueued = 6
    static let maximumTurns = 4
    static let maximumActions = 12
    static let maximumSeconds: TimeInterval = 420
    // No live screen drawing, screen inspection, paid generation or recursive delegation.
    static let supportedActions: Set<String> = ["openApplication", "openURL", "searchWeb", "writeFile", "createFolder", "createDocument", "revealFile", "runProject"]
    static func shouldDeploy(_ text: String, explicit: Bool = false, contextual: Bool = false) -> Bool {
        let s = text.lowercased().replacingOccurrences(of: #"(?s)```.*?```|`[^`]*`"#, with: "", options: .regularExpression)
        if explicit { return true }
        if s.range(of: #"\b(do not|don't|never)\s+(create|deploy|start|spawn|make|use|assign|send)\s+(an?\s+)?(agent|specialist)\b"#, options: .regularExpression) != nil { return false }
        if ["what ", "what's ", "how do ", "how does ", "how to ", "explain ", "tell me about "].contains(where: s.hasPrefix) { return false }
        if ["no agents", "without an agent", "don't use an agent", "do not use an agent", "no agent", "don't deploy", "do not deploy"].contains(where: s.contains) { return false }
        if s.range(of: #"\b(create|deploy|start|spawn|make|use|assign|ask|have|send)\b.{0,35}\b(an? |the )?(agent|specialist)\b"#, options: .regularExpression) != nil { return true }
        if s.range(of: #"\bagent\b.{0,25}\b(to|for|that|who)\b"#, options: .regularExpression) != nil && !["what is", "what's", "explain", "how do", "how does"].contains(where: s.hasPrefix) { return true }
        // Automatic handoff is deliberately conservative, and requires an actual deliverable.
        guard !ScreenQuestionPolicy.wantsSnapshot(text),
              !["what ", "why ", "how ", "explain ", "tell me ", "can agents"].contains(where: s.hasPrefix) else { return false }
        if s.range(of: #"\b(build|develop|create|prepare)\b.{0,30}\b(complete|full|end-to-end)\b.{0,35}\b(app|website|project|report)\b"#, options: .regularExpression) != nil { return true }
        guard s.count >= 110 else { return false }
        let deliverable = ["build", "develop", "implement", "create", "prepare", "write", "research", "analyse", "analyze", "review", "plan"].contains { word in
            s.range(of: "\\b" + word + "\\b", options: .regularExpression) != nil
        }
        let depth = ["complete", "comprehensive", "detailed", "full project", "end-to-end", "multiple files", "test", "compare", "report", "sources", "then", "step-by-step", "step by step"].filter(s.contains).count
        return deliverable && (depth >= 3 || contextual && depth >= 2)
    }
    static func specialty(for text: String, creation: String? = nil) -> AgentSpecialty {
        let s = text.lowercased()
        if creation == "website" || ["website", "code", " app", "program", "debug", "repository", "software"].contains(where: s.contains) { return .builder }
        if ["research", "sources", "investigate", "competitor"].contains(where: s.contains) { return .researcher }
        if ["analy", "analyse", "study", "exam", "flashcard", "calculat", "dataset", "compare"].contains(where: s.contains) { return .analyst }
        if creation == "document" || ["write", "draft", "essay", "letter", "report", "email"].contains(where: s.contains) { return .writer }
        return .generalist
    }
    static func hue(existing: [Double], theme: Double) -> Double {
        let palette = (0..<64).map { Double($0) / 64.0 }
        func distance(_ a: Double, _ b: Double) -> Double { let d = abs(a-b); return min(d, 1-d) }
        return palette.max { a, b in
            let aa = ([theme] + existing).map { distance(a, $0) }.min() ?? 1
            let bb = ([theme] + existing).map { distance(b, $0) }.min() ?? 1
            return aa < bb
        } ?? 0.55
    }
    static func restored(_ run: AgentRun) -> AgentRun {
        var run = run
        if run.status == .running || run.status == .queued {
            run.status = .interrupted; run.phase = "Continue when you're ready"; run.approved = false
            run.partial = ""; run.pending = []
            run.transcript.append(.init(role: "user", text: "App notice: Iris restarted during this task. Actions without a recorded receipt may or may not have completed. Do not repeat an uncertain side effect; ask the user to check before retrying it."))
        }
        // Approval is never restored across a restart.
        run.approved = false
        return run
    }
    static func title(for task: String) -> String {
        let clean = task.replacingOccurrences(of: #"(?i)\b(create|deploy|start|spawn|make|use)\s+(an?\s+)?agent\s*(to|for)?\s*"#, with: "", options: .regularExpression)
        return String(clean.split(whereSeparator: \.isWhitespace).prefix(11).joined(separator: " ").prefix(96))
    }
}

/// Polls cursor positions only, without installing an event tap or requesting permission.
struct AgentCornerGesture {
    private var samples: [(Double, Double)] = []
    mutating func sample(x: Double, time: Double, inCorner: Bool) -> Bool {
        guard inCorner else { samples = []; return false }
        samples.append((x,time)); samples.removeAll { time-$0.1 > 0.65 }
        if samples.count > 10 { samples.removeFirst(samples.count-10) }
        guard samples.count >= 5, (samples.map(\.0).max() ?? x) - (samples.map(\.0).min() ?? x) >= 32 else { return false }
        var previous = 0, reversals = 0
        for i in 1..<samples.count {
            let delta = samples[i].0-samples[i-1].0
            guard abs(delta) > 5 else { continue }
            let sign = delta > 0 ? 1 : -1
            if previous != 0 && previous != sign { reversals += 1 }
            previous = sign
        }
        if reversals >= 3 { samples = []; return true }; return false
    }
}
