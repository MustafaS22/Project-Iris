import Foundation
import CoreGraphics

enum IrisState: String, Codable, CaseIterable {
    case dormant, idle, attention, thinking, listening, answering, studying, warning, celebration, sleeping, error, permission, vision, disconnected
    var label: String {
        switch self {
        case .dormant: "Quiet"; case .idle: "Here when you need me"; case .attention: "A little nudge"
        case .thinking: "Thinking"; case .listening: "Microphone on"; case .answering: "Speaking"
        case .studying: "One thing at a time"; case .warning: "Take a moment"; case .celebration: "A good place to pause"
        case .sleeping: "Quiet hours"; case .error: "Something needs attention"; case .permission: "Your permission first"
        case .vision: "Reading your selection"; case .disconnected: "Connection unavailable"
        }
    }
}

enum UserRole: String, Codable, CaseIterable { case student = "Student", developer = "Developer", everyday = "Everyday" }
enum IrisTheme: String, Codable, CaseIterable { case apricot = "Apricot", sage = "Sage", ice = "Ice", ocean = "Ocean", rose = "Rose", lilac = "Lilac", sunshine = "Sunshine", custom = "Custom" }
enum KnowledgeSource: String, Codable, CaseIterable {
    case local = "LM Studio", openAI = "OpenAI", gemini = "Gemini", googleKnowledge = "Google knowledge"
    static let modelProviders: [Self] = [.openAI, .gemini, .local]
}

struct Preferences: Codable, Equatable {
    var memoryEnabled: Bool?
    var personalityID: String?
    var personalityVoiceTone: Bool?
    var customHue: Double?
    var liveWeatherEnabled: Bool?
    var weatherPlace: WeatherPlace?
    var weatherFahrenheit: Bool?
    var geminiSpeechEconomy: Bool?
    var speakTypedReplies: Bool?
    var streamSpokenReplies: Bool?
    var geminiVoice: String?
    var geminiSpeechModel: String?
    var geminiSpeechStyle: String?
    var geminiSpeechAuth: String?
    var geminiSpeechSpeed: Double?
    var speechRecognitionProvider: String?
    var voiceProvider: String?
    var voiceBoxServer: String?
    var voiceBoxProfile: String?
    var voiceBoxSpeed: Double?
    var voiceID: String?
    var speechRate: Float?
    var listenOnSummon: Bool?
    var speakReplies: Bool?
    var name = ""
    var role: UserRole = .student
    var interests = ""
    var theme: IrisTheme = .apricot
    var onboarded = false
    var proactive = false
    var quietEnabled = true
    var quietStart = 22
    var quietEnd = 8
    var observeApps = false
    var allowedCaptureApps: [String] = []
    var displayID: UInt32? = nil
    var source: KnowledgeSource = .openAI
    var server = "http://127.0.0.1:1234/v1"
    var model = ""
    var preferredBrowser: String?
    var alwaysAllowComputerActions: Bool?
    var providerVerified = false
}

struct StudySession: Codable, Equatable, Identifiable {
    var id = UUID()
    var goal: String
    var duration: TimeInterval
    var startedAt: Date
    var deadline: Date?
    var pausedRemaining: TimeInterval
    var isBreak = false
    var isRunning: Bool { deadline != nil }
    func remaining(at date: Date) -> TimeInterval { max(0, deadline.map { $0.timeIntervalSince(date) } ?? pausedRemaining) }
    func progress(at date: Date) -> Double { min(1, max(0, 1 - remaining(at: date) / max(1, duration))) }
    mutating func pause(at date: Date) { pausedRemaining = remaining(at: date); deadline = nil }
    mutating func resume(at date: Date) { guard deadline == nil, pausedRemaining > 0 else { return }; deadline = date.addingTimeInterval(pausedRemaining) }
    static func start(goal: String, minutes: Int, at date: Date, isBreak: Bool = false) -> Self {
        let seconds = TimeInterval(min(180, max(1, minutes)) * 60)
        return Self(goal: goal, duration: seconds, startedAt: date, deadline: date.addingTimeInterval(seconds), pausedRemaining: seconds, isBreak: isBreak)
    }
}
struct SessionRecord: Codable, Identifiable {
    var id: UUID; var goal: String; var date: Date; var focusedSeconds: TimeInterval; var completed: Bool; var isBreak: Bool
    var summary: String {
        let elapsed = focusedSeconds < 60 ? "\(Int(focusedSeconds)) seconds" : "\(Int(focusedSeconds / 60)) minutes"
        return "\(elapsed) \(isBreak ? "resting" : "focused") · \(completed ? "completed" : "ended early")"
    }
}
struct QuickNote: Codable, Identifiable { var id = UUID(); var text: String; var createdAt = Date() }
struct ChatFileReference: Codable, Identifiable {
    var id = UUID()
    var name: String
    var folderID: String?
    var relativePath: String?
    var bookmark: Data?
}
struct ChatMessage: Identifiable, Codable { var id = UUID(); var role: String; var text: String; var files: [ChatFileReference]? }
struct ChatConversation: Codable, Identifiable {
    var skillID: String?
    var id = UUID()
    var updatedAt = Date()
    var messages: [ChatMessage]
    var title: String { String((messages.first(where: { $0.role == "user" })?.text ?? "Conversation").prefix(80)) }
}
struct StudyCard: Codable, Identifiable { var id = UUID(); var question: String; var answer: String }
struct PersistedState: Codable {
    var memories: [AssistantMemory]?
    var knowledgeMemories: [KnowledgeMemoryRecord]?
    var knowledgeScanAt: Date?
    var notebooks: [StudyNotebook]?
    var createdItems: [CreatedItem]?
    var conversations: [ChatConversation]?
    var activeConversationID: UUID?
    var studyCards: [StudyCard]?
    var preferences = Preferences()
    var session: StudySession?
    var history: [SessionRecord] = []
    var notes: [QuickNote] = []
}

enum ActivityKind: Int, Codable { case urgent = 0, userAction, communication, focus, reminder, thinking, media, system, passive }
struct LiveActivity: Identifiable, Equatable {
    var id: String; var kind: ActivityKind; var title: String; var symbol: String; var expiresAt: Date?
}
enum ActivityRouter {
    static func ranked(_ activities: [LiveActivity], at date: Date) -> [LiveActivity] {
        activities.filter { $0.expiresAt.map { $0 > date } ?? true }.sorted {
            $0.kind.rawValue == $1.kind.rawValue ? $0.id < $1.id : $0.kind.rawValue < $1.kind.rawValue
        }
    }
}
struct ProactivePolicy {
    static func isQuiet(at date: Date, preferences: Preferences, calendar: Calendar = .current) -> Bool {
        guard preferences.quietEnabled else { return false }
        let hour = calendar.component(.hour, from: date)
        let start = preferences.quietStart, end = preferences.quietEnd
        if start == end { return true }
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }
    static func mayNudge(at date: Date, preferences: Preferences, lastNudge: Date?, fullScreen: Bool) -> Bool {
        preferences.proactive && !fullScreen && !isQuiet(at: date, preferences: preferences) && (lastNudge.map { date.timeIntervalSince($0) >= 1800 } ?? true)
    }
}

enum ContextPolicy {
    // Browsers are denied because private/incognito windows cannot be reliably detected with public foreground-app metadata.
    static let blockedTokens = ["safari", "chrome", "firefox", "brave", "edge", "arc", "orion", "1password", "bitwarden", "keychain", "keepass", "dashlane", "wallet", "bank", "paypal", "authenticator", "protonpass", "lastpass"]
    static func permitsCapture(bundleID: String?, allowlist: [String]) -> Bool {
        guard let id = bundleID, !blockedTokens.contains(where: { id.lowercased().contains($0) }) else { return false }
        return allowlist.contains(id)
    }
}

enum IrisFailure: LocalizedError {
    case message(String)
    var errorDescription: String? { switch self { case .message(let text): text } }
}

enum ProviderEndpoint {
    static func validate(_ input: String) throws -> URL {
        guard let parts = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = parts.scheme?.lowercased(), let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              let url = parts.url else { throw IrisFailure.message("Enter a server URL without credentials, queries or fragments.") }
        let loopback = ["localhost", "127.0.0.1", "[::1]", "::1"].contains(host.lowercased())
        guard scheme == "https" || (scheme == "http" && loopback) else {
            throw IrisFailure.message("Use HTTPS for remote servers. HTTP is allowed only on this Mac's loopback address.")
        }
        return url
    }
}

enum CapabilityRisk: String { case readOnly, localWrite, externalWrite, destructive }
struct IrisCapability: Identifiable {
    let id: String; let name: String; let description: String; let permissions: [String]
    let platforms: [String]; let risk: CapabilityRisk; let confirmation: Bool
    let offline: String; let failure: String; let audit: String
    static let available: [Self] = [
        .init(id: "focus", name: "Focus sessions", description: "Start, pause and finish a local session", permissions: [], platforms: ["macOS"], risk: .localWrite, confirmation: false, offline: "Available", failure: "Preserve current session", audit: "Operation and result only"),
        .init(id: "notes", name: "Quick notes", description: "Save a note on this Mac", permissions: [], platforms: ["macOS"], risk: .localWrite, confirmation: false, offline: "Available", failure: "Keep draft, show save error", audit: "Operation and result only"),
        .init(id: "files", name: "Read selected files", description: "Extract text from a chosen PDF, text file or image", permissions: ["User-selected file"], platforms: ["macOS"], risk: .readOnly, confirmation: true, offline: "Available", failure: "Explain unsupported/empty content", audit: "No filenames or content"),
        .init(id: "screen", name: "Read this screen", description: "Explicit capture from an allowed application", permissions: ["Screen Recording", "Application allowlist"], platforms: ["macOS"], risk: .readOnly, confirmation: true, offline: "Local OCR", failure: "Deny without permission", audit: "Capture outcome only"),
        .init(id: "voice", name: "Voice input", description: "Transcribe while the microphone is visibly on", permissions: ["Microphone", "Speech Recognition"], platforms: ["macOS"], risk: .readOnly, confirmation: true, offline: "Depends on Apple language support", failure: "Stop and release microphone", audit: "Start/stop/error only"),
        .init(id: "web", name: "Web search", description: "Open an explicit search in your default browser", permissions: [], platforms: ["macOS"], risk: .externalWrite, confirmation: true, offline: "Browser may be offline", failure: "Report launch failure", audit: "No search content")
    ]
}


enum SurfaceGeometry {
    static func notchFrame(in screen: CGRect, visible: CGRect, safeTop: CGFloat, desired: CGSize) -> CGRect {
        // The notch must stay attached to the physical display edge. Never inset
        // it by the visible work area, safe area or menu-row height.
        return frame(in: screen, desired: desired)
    }
    static func frame(in screen: CGRect, desired: CGSize) -> CGRect {
        let width = min(max(1, desired.width), max(1, screen.width - 16))
        let height = min(max(1, desired.height), max(1, screen.height - 32))
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
    }
}


enum LaunchPolicy {
    static func needsOnboarding(completed: Bool, revision: Int) -> Bool { !completed || revision < 2 }
}

/// Local-time greeting independent of focus-session timers.
enum GreetingPolicy {
    static func text(at date: Date, name: String, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let greeting: String
        switch hour { case 5..<12: greeting = "Good morning"; case 12..<17: greeting = "Good afternoon"; case 17..<22: greeting = "Good evening"; default: greeting = "Good night" }
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return greeting + (clean.isEmpty ? "." : ", " + clean + ".")
    }
}


/// Same logical footprint on Retina, standard and non-notched displays.
/// Baseline measured on the owner's Mac: 156×28 housing + 116×5 Iris wings.
enum NotchSizing {
    static let referenceHousing = CGSize(width: 156, height: 28)
    static func housing(safeTop: CGFloat, physicalWidth: CGFloat?) -> CGSize {
        CGSize(width: max(referenceHousing.width, physicalWidth ?? 0), height: max(referenceHousing.height, safeTop))
    }
    static func compact(housing: CGSize) -> CGSize { CGSize(width: housing.width + 116, height: housing.height + 5) }
}
