import SwiftUI
import AppKit
import Combine
import Network
import IOKit.ps
import UniformTypeIdentifiers
import OSLog

@MainActor
final class IrisOrchestrator: ObservableObject {
    @Published var data = PersistedState()
    @Published var expanded = false
    @Published var floatingActive = false
    @Published var floatingReply = ""
    var openFloating: (() -> Void)?
    var openFloatingPreview: (() -> Void)?
    var openFloatingTyping: (() -> Void)?
    var prepareFloatingContext: ((String) async throws -> AttachedContext?)?
    @Published var tab: NotchTab = .focus
    @Published var draft = ""
    @Published var goal = ""
    @Published var minutes = 25
    @Published var noteDraft = ""
    @Published var messages: [ChatMessage] = [] { didSet { persistConversation() } }
    private var restoringConversation = true
    private var conversationID = UUID()
    @Published var activeStudioSkill: StudioSkill?
    @Published var studioReferences: [AttachedContext] = []
    @Published var liveReply = ""
    @Published var requestPhase = ""
    @Published var requestStarted = Date()
    private var requestID: UUID?
    @Published var busy = false
    @Published var error: String?
    private struct Notice {
        let text: String
        let celebrates: Bool
    }
    @Published private var currentNotice: Notice?
    var notice: String? {
        get { currentNotice?.text }
        set { currentNotice = newValue.map { Notice(text: $0, celebrates: false) } }
    }
    @Published var attachments: [AttachedContext] = []
    var canSend: Bool { !busy && !contextBusy && (!draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty) }
    @Published var now = Date()
    @Published var foregroundName = "No context shared"
    @Published var foregroundID: String?
    @Published var online = true
    @Published var battery: Int?
    @Published var charging = false
    @Published var testing = false
    @Published var knowledgeScanning = false
    @Published var knowledgeScanProgress = 0.0
    @Published var knowledgeScanStatus = ""
    @Published var knowledgeScanIssue: String?
    var knowledgeScanTask: Task<Void, Never>?
    // Injectable only for deterministic local validation; production uses the selected AI.
    var knowledgeScanResponder: ((String) async throws -> String)?
    @Published var contextBusy = false
    @Published var connectionResult = "Connecting automatically…"
    @Published var availableModels: [String] = []
    @Published var workspaceSection: WorkspaceSection = .today
    let notebookSession = NotebookSession()
    let agents = IrisAgentStore(url: (ProcessInfo.processInfo.arguments.contains("--iris-validation") ? FileManager.default.temporaryDirectory.appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--iris-agent-validation") ? "IrisAgentValidation-\(ProcessInfo.processInfo.processIdentifier)" : "IrisValidation") : IrisLocalStorage.supportDirectory).appendingPathComponent("agents.json"))
    @Published var selectedNotebookID: UUID?
    let shortcuts = IrisShortcutStore(storageKey: ProcessInfo.processInfo.arguments.contains("--iris-validation") ? "IrisCustomShortcuts.validation.v1" : "IrisCustomShortcuts.v1")
    let liveData = LiveDataService()
    let updates = IrisUpdates()
    let voice = VoiceService()
    let actions = AssistantActions()
    let computer = ComputerUseSession()
    private var spokenRequest = false
    let accounts: AccountService
    let knowledge: KnowledgeStore
    let connections: KnowledgeConnections
    @Published var onboardingPresented = false
    @Published var notchPinned = false
    lazy var welcome = WelcomeJourney(iris: self)
    var beginWelcomeJourney: ((Bool) -> Void)?
    var endWelcomeJourney: (() -> Void)?
    var welcomePointAt: ((CGRect) -> Void)?
    var showDraftPractice: (() -> Void)?
    var restartOnboarding: (() -> Void)?
    var restartOnboardingAt: ((Int) -> Void)?
    private var onboardingKey: String { ProcessInfo.processInfo.arguments.contains("--iris-validation") ? "IrisOnboardingRevision.validation" : "IrisOnboardingRevision" }
    var needsOnboarding: Bool { LaunchPolicy.needsOnboarding(completed: preferences.onboarded, revision: UserDefaults.standard.integer(forKey: onboardingKey)) }
    func completeOnboarding() { setPreference { $0.onboarded = true }; UserDefaults.standard.set(2, forKey: onboardingKey); onboardingPresented = false }
    func togglePresence() { notchPinned = !expanded; expanded.toggle() }
    func collapsePresence() { notchPinned = false; expanded = false }
    var openWorkspace: (() -> Void)?
    var returnToNotch: (() -> Void)?
    var reposition: (() -> Void)?
    var isFullScreen: () -> Bool = { false }
    private var sessionTimer: Timer?
    private var completionTask: Task<Void, Never>?
    private var modelTask: Task<Void, Never>?
    private var actionTask: Task<Void, Never>?
    private var connectionTask: Task<Void, Never>?
    private var connectionTimeout: Task<Void, Never>?
    private var connectionCheckID = UUID()
    private var contextTask: Task<Void, Never>?
    private var lastNudge: Date?
    private var observers: [NSObjectProtocol] = []
    private var network = NWPathMonitor()
    private var batterySource: CFRunLoopSource?
    private var subscriptions = Set<AnyCancellable>()
    private let storageURL: URL
    private var maySave = true
    private static let log = Logger(subsystem: "com.projectiris.Project-IRIS", category: "orchestrator")

    enum NotchTab: String, CaseIterable { case focus = "Focus", ask = "Ask", agents = "Agents", capture = "Capture", settings = "Settings", welcome = "Welcome" }
    enum WorkspaceSection: String, CaseIterable { case today = "Chat", agents = "Agents", tools = "Study spaces", create = "Create", library = "Library", chats = "Chat history", knowledge = "Knowledge", connections = "Connections", sessions = "Sessions", settings = "Settings", testing = "App testing" }

    init() {
        let validation = ProcessInfo.processInfo.arguments.contains("--iris-validation")
        let validationFolder = ProcessInfo.processInfo.arguments.contains("--iris-knowledge-memory-validation") ? "IrisKnowledgeScanValidation-\(UUID().uuidString)" : "IrisValidation"
        storageURL = validation ? FileManager.default.temporaryDirectory.appendingPathComponent(validationFolder + "/state.json") : IrisLocalStorage.supportDirectory.appendingPathComponent("state.json")
        let accountService = AccountService()
        accounts = accountService
        let database = KnowledgeStore(directory: storageURL.deletingLastPathComponent())
        knowledge = database
        connections = KnowledgeConnections(store: database, accounts: accountService)
        load()
        updates.beforeInstalling = { [weak self] in self?.save() }
        actions.preferredBrowser = preferences.preferredBrowser
        if let id = data.activeConversationID, let conversation = data.conversations?.first(where: { $0.id == id }) {
            conversationID = id; messages = conversation.messages; activeStudioSkill = conversation.skillID.flatMap(StudioSkill.init(rawValue:))
        }
        restoringConversation = false
        if !ProcessInfo.processInfo.arguments.contains("--iris-validation") { connections.startAutomaticRefresh() }
        configureAgents()
        welcome.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        agents.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        agents.$computerBusy.dropFirst().filter { !$0 }.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.runAutomaticActions() }
        }.store(in: &subscriptions)
        shortcuts.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        knowledge.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        connections.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        accounts.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        computer.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        actions.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        voice.$speechError.compactMap { $0 }.sink { [weak self] in self?.error = $0 }.store(in: &subscriptions)
        voice.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
        network.pathUpdateHandler = { [weak self] path in Task { @MainActor [weak self] in self?.online = path.status == .satisfied } }
        network.start(queue: DispatchQueue(label: "iris.network"))
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor [weak self] in self?.updateForeground(app) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.voice.stop(); self?.voice.stopSpeaking(); self?.save() } })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.tick(); self?.updateBattery() } })
        updateBattery()
        if let opaque = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let store = Unmanaged<IrisOrchestrator>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in store.updateBattery() }
        }, Unmanaged.passUnretained(self).toOpaque()) {
            batterySource = opaque.takeRetainedValue(); CFRunLoopAddSource(CFRunLoopGetMain(), batterySource, .defaultMode)
        }
        if let app = NSWorkspace.shared.frontmostApplication { updateForeground(app) }
        if !ProcessInfo.processInfo.arguments.contains("--iris-validation") { refreshConnection() }
    }
    var preferences: Preferences { data.preferences }
    var state: IrisState {
        if computer.needsAttention { return .permission }
        if error != nil { return .error }
        if computer.running { return computer.paused ? .idle : .thinking }
        if welcome.active, welcome.celebrating { return .celebration }
        if voice.listening { return .listening }; if voice.speaking { return .answering }
        if voice.requesting { return .permission }; if contextBusy { return .vision }
        if busy || welcome.busy { return .thinking }
        if let currentNotice { return currentNotice.celebrates ? .celebration : .attention }; if data.session != nil { return .studying }
        if ProactivePolicy.isQuiet(at: now, preferences: preferences) { return .sleeping }; return .idle
    }
    var accent: Color { preferences.theme.color(customHue: preferences.customHue ?? 0.5) }
    var activities: [LiveActivity] {
        var items: [LiveActivity] = []
        if error != nil { items.append(.init(id: "error", kind: .urgent, title: "Needs attention", symbol: "exclamationmark.circle", expiresAt: nil)) }
        if voice.listening { items.append(.init(id: "mic", kind: .userAction, title: "Microphone on", symbol: "mic.fill", expiresAt: nil)) }
        if let session = data.session { items.append(.init(id: "focus", kind: .focus, title: timeString(session.remaining(at: now)), symbol: session.isRunning ? "timer" : "pause.fill", expiresAt: nil)) }
        if contextBusy { items.append(.init(id: "context", kind: .userAction, title: "Reading locally", symbol: "viewfinder", expiresAt: nil)) }
        if busy { items.append(.init(id: "ai", kind: .thinking, title: "Thinking", symbol: "ellipsis", expiresAt: nil)) }
        if notice != nil { items.append(.init(id: "complete", kind: .reminder, title: "Session saved", symbol: "checkmark", expiresAt: nil)) }
        return ActivityRouter.ranked(items, at: now)
    }
    func setPreference(_ change: (inout Preferences) -> Void) { let previousAccent = accent; change(&data.preferences); if previousAccent != accent { computer.approvalAccent = accent }; actions.preferredBrowser = preferences.preferredBrowser; save() }
    func providerChanged() {
        data.preferences.providerVerified = false; connectionResult = "Connecting automatically…"; availableModels = []; save(); refreshConnection()
    }
    @discardableResult func save() -> Bool {
        guard maySave else { return false }
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(data).write(to: storageURL, options: .atomic)
            return true
        } catch { self.error = "I couldn't save your changes: \(error.localizedDescription)"; Self.log.error("Local save failed"); return false }
    }
    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            data = try JSONDecoder().decode(PersistedState.self, from: Data(contentsOf: storageURL))
            // Never silently restart an interrupted session or trust an old network test.
            if var session = data.session { let wasRunning = session.isRunning; session.pause(at: Date()); data.session = session; notice = wasRunning ? "Your session was interrupted. Resume when you're ready." : "Your paused session is ready when you are." }
            data.preferences.providerVerified = false
        } catch {
            maySave = false
            self.error = "Saved Iris data could not be read. The original file is preserved. Export or repair it at \(storageURL.path), then relaunch. Changes won't be saved until repaired."
        }
    }
    func startSession(isBreak: Bool = false) {
        guard data.session == nil else { return }
        let title = isBreak ? "A little breathing room" : goal.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { error = "Give this session one small, concrete goal."; return }
        error = nil; notice = nil
        data.session = .start(goal: title, minutes: isBreak ? 5 : minutes, at: Date(), isBreak: isBreak)
        now = Date(); save(); startTimer(); Self.log.info("Session started")
    }
    func toggleSession() {
        guard var session = data.session else { return }
        if session.remaining(at: Date()) <= 0 { endSession(completed: true); return }
        if session.isRunning { session.pause(at: Date()); sessionTimer?.invalidate(); sessionTimer = nil }
        else { session.resume(at: Date()); startTimer() }
        data.session = session; now = Date(); save()
    }
    private func startTimer() {
        sessionTimer?.invalidate()
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.tick() } }
        sessionTimer?.tolerance = 0.15
    }
    func tick() {
        now = Date()
        if let session = data.session, session.isRunning, session.remaining(at: now) <= 0 { endSession(completed: true) }
    }
    func endSession(completed: Bool = false) {
        guard let session = data.session else { return }
        let used = max(0, session.duration - session.remaining(at: Date()))
        data.history.insert(.init(id: session.id, goal: session.goal, date: Date(), focusedSeconds: used, completed: completed, isBreak: session.isBreak), at: 0)
        data.history = Array(data.history.prefix(500)); data.session = nil
        sessionTimer?.invalidate(); sessionTimer = nil
        let elapsedLabel = used < 60 ? "\(Int(used)) seconds" : "\(Int(used / 60)) minutes"
        let summary = completed ? "\(Int(session.duration / 60)) minutes, done. \(session.isBreak ? "Ready for the next small step?" : "Your goal: \(session.goal). A short break could help.")" : "Session saved · \(elapsedLabel) focused on \(session.goal)."
        currentNotice = Notice(text: summary, celebrates: completed)
        save(); Self.log.info("Session saved")
        if completed, ProactivePolicy.mayNudge(at: Date(), preferences: preferences, lastNudge: lastNudge, fullScreen: isFullScreen()) { lastNudge = Date(); expanded = true }
    }
    func saveNote() {
        let text = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard text.count <= 12000, data.notes.count < 1000 else { error = "Notes support up to 12,000 characters each and 1,000 saved notes. Shorten this note or remove an older one."; return }
        data.notes.insert(.init(text: String(text.prefix(12000))), at: 0); noteDraft = ""; save()
    }
    func removeNote(_ id: UUID) { data.notes.removeAll { $0.id == id }; save() }
    func remember(_ raw: String) {
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !text.isEmpty else { return }
        var items = data.memories ?? []
        guard !items.contains(where: { $0.text.localizedCaseInsensitiveCompare(text) == .orderedSame }) else { notice = "I already remember that."; return }
        guard items.count < 100 else { error = "Memory is full. Forget a detail in Settings → Memory before adding another."; return }
        items.append(.init(text: text)); data.memories = items; save()
    }
    func forget(_ id: UUID) { data.memories?.removeAll { $0.id == id }; save() }
    func editMemory(_ id: UUID, text: String) {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !trimmed.isEmpty, let index = data.memories?.firstIndex(where: { $0.id == id }) else { return }
        data.memories?[index].text = trimmed; save()
    }
    private var bypassWelcome = false
    func askForWelcome() { bypassWelcome = true; defer { bypassWelcome = false }; ask() }
    func ask() {
        if !bypassWelcome, welcome.active, [.interview, .notch, .floating].contains(welcome.progress.stage) {
            let text = draft; draft = ""; welcome.submit(text); return
        }
        guard canSend else { return }
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let mention: ChatMentionRequest
        do { mention = try ChatMentions.parse(typed) } catch { self.error = error.localizedDescription; return }
        // A typed mention never silently enables a source or broadens the selected context.
        guard mention.connectors.count <= 6 else { error = "Use up to six @sources per message."; return }
        let unavailable = mention.connectors.filter { source in !knowledge.enabled.contains(source.rawValue) || !knowledge.documents.contains(where: { $0.source == source }) }
        guard unavailable.isEmpty else { error = "Enable and import " + unavailable.map(\.name).sorted().joined(separator: ", ") + " in Knowledge → Sources, then send again."; return }
        if mention.creation != nil && mention.text.isEmpty && attachments.isEmpty { error = "Describe what you’d like to create after the @tool."; return }
        let text = mention.text.isEmpty ? (mention.connectors.isEmpty ? "Please describe or summarize the attached files." : "Summarize the selected source material.") : mention.text
        if let skill = mention.skill { activeStudioSkill = skill }
        let shared = attachments + (mention.skill == nil ? [] : studioReferences)
        let images = shared.compactMap(\.image)
        guard images.count <= AttachmentReader.maximumCount else { error = "Use up to six images across chat attachments and Studio references."; return }
        voice.stop(); voice.stopSpeaking(); error = nil
        if mention.computer && !mention.agent {
            guard !computer.running, !agents.computerBusy else { error = "A computer task is already active. Stop it before starting another."; return }
            messages.append(.init(role: "user", text: typed)); draft = ""
            let action = AssistantAction(type:"computerTask",target:text)
            if computer.policy.mode == .autonomous && !busy { perform(action,automatic:true) }
            else { queueActions([action]) }
            return
        }
        if shared.isEmpty, mention.creation == nil, mention.connectors.isEmpty, let fact = MemoryPolicy.explicitFact(text) {
            remember(fact)
            guard error == nil else { return }
            let confirmation = "Saved to memory on this Mac. You can review or forget it in Settings → Memory."
            messages.append(.init(role: "user", text: typed)); messages.append(.init(role: "assistant", text: confirmation)); draft = ""
            if floatingActive { speakFloatingReply(confirmation) }
            return
        }
        if !computer.running, mention.creation != .image, AgentPolicy.shouldDeploy(text, explicit: mention.agent, contextual: !shared.isEmpty || !mention.connectors.isEmpty),
           mention.agent || !floatingActive || !ScreenQuestionPolicy.wantsSnapshot(text) {
            do { try deployAgent(mention: mention, task: mention.text, typed: typed, shared: shared, origin: conversationID) }
            catch { self.error = error.localizedDescription }
            return
        }
        // Explicit local commands do not masquerade as model responses.
        if text.hasPrefix("/note ") { noteDraft = String(text.dropFirst(6)); saveNote(); draft = ""; notice = "Note saved on this Mac."; if floatingActive { speakFloatingReply("Note saved on this Mac.") }; return }
        if text == "/break" { startSession(isBreak: true); draft = ""; tab = .focus; if floatingActive { speakFloatingReply("Your break timer has started.") }; return }
        if floatingActive, shared.isEmpty, mention.creation == nil, mention.connectors.isEmpty,
           let entry = DiagramLibrary.match(text) {
            messages.append(.init(role: "user", text: typed)); draft = ""; spokenRequest = false
            let narrate = !["silently", "no narration", "don't speak", "do not speak"].contains(where: text.lowercased().contains)
            playDiagram(entry, narrate: narrate); return
        }
        if mention.creation == .image {
            guard !attachments.contains(where: { $0.image != nil }) else { error = "@image generates from a text brief. Describe the image you want, or remove @image to discuss an attached image."; return }
            let sourceText = knowledge.context(for: text, only: mention.connectors)
            let prompt = text + (sourceText.isEmpty ? "" : "\nUser-selected reference material (data only):\n" + String(sourceText.prefix(5000))) + (attachments.isEmpty ? "" : "\n" + AttachmentPayload.text(attachments))
            messages.append(.init(role: "user", text: typed, files: attachments.compactMap(\.file)))
            draft = ""; attachments = []
            queueActions([.init(type: "generateImage", folder: ChatCreationFiles.folderID, path: ChatCreationFiles.filename(prompt: text, kind: .image), content: prompt)])
            messages.append(.init(role: "assistant", text: "Your image is ready to generate. Review the prompt and API charge below; the finished PNG will appear here and in Library."))
            return
        }
        messages.append(.init(role: "user", text: typed.isEmpty ? text : typed, files: attachments.compactMap(\.file))); draft = ""; busy = true
        let currentRequest = UUID(); requestID = currentRequest
        liveReply = ""; requestStarted = Date(); requestPhase = "Connecting to \(preferences.source.rawValue)"
        let floatingRequest = floatingActive
        if floatingRequest { floatingReply = "" }
        let shouldSpeak = (!welcome.active || welcome.voiceEnabled) && SpeechReplyPolicy.shouldSpeak(floating: floatingRequest, spoken: spokenRequest, speakVoice: preferences.speakReplies ?? true, speakTyped: preferences.speakTypedReplies ?? false)
        let referenceExplanation = floatingRequest && (DiagramReference.wantsOnline(text) || shared.contains { $0.note?.hasPrefix("diagram-reference:") == true })
        let streamSpeech = !referenceExplanation && ["gemini", "fish"].contains(preferences.speechProvider) && (preferences.streamSpokenReplies ?? true) && shouldSpeak
        if streamSpeech {
            voice.beginStreamingReply(voice: preferences.geminiVoice ?? GeminiSpeechClient.defaultVoice, model: preferences.geminiSpeechModel ?? GeminiSpeechClient.defaultModel, style: preferences.replySpeechStyle, auth: preferences.geminiSpeechAuth ?? "apiKey", speed: preferences.geminiSpeechSpeed ?? 1, economy: preferences.geminiSpeechEconomy ?? true, provider: preferences.speechProvider, fishVoice: preferences.selectedFishVoice)
        }
        var sharedScreen = false
        var lastUpdate = Date.distantPast
        let onPartial: @MainActor (String) -> Void = { [weak self] raw in
            guard let self, self.requestID == currentRequest, self.busy else { return }
            if raw.isEmpty { self.requestPhase = "Waiting for the response"; return }
            guard Date().timeIntervalSince(lastUpdate) >= 0.12 else { return }
            lastUpdate = Date()
            let publicText = mention.creation == .website ? "Building your website…" : StreamingPresentation.visibleText(raw)
            self.liveReply = publicText
            if streamSpeech && !sharedScreen && mention.creation == nil { self.voice.updateStreamingReply(raw) }
            self.requestPhase = StreamingPresentation.status(for: raw, visible: publicText)
        }
        let snapshot = preferences, skill = (floatingRequest && mention.creation == nil && ScreenQuestionPolicy.wantsSolution(text)) ? ScreenSolution.instruction : (mention.creation?.instruction ?? mention.skill?.instruction ?? ""), liveConversation = conversationID
        var history = messages
        if !mention.tokens.isEmpty, !history.isEmpty { history[history.count - 1].text = text }
        let profile = "User preferences: role=\(preferences.role.rawValue); name=\(preferences.name); interests=\(preferences.interests)."
        let attachedText = String(AttachmentPayload.text(shared).prefix(mention.connectors.isEmpty ? 12000 : 9000))
        // Put the user's files first so background knowledge cannot truncate them away.
        let floatingContext = floatingActive ? "\nFloating desktop mode is active. You may draw explanations with drawOnScreen. When a screenshot is supplied, drawing coordinates are normalized 0–1 from that image top-left; Iris maps them to the display. Without a screenshot, conceptual drawings use the full display top-left. You have all normal assistant abilities here, not only drawing. Use conceptual diagrams when helpful. For a new drawing or a topic explanation, create a mode=conceptual drawing with narrated nodes and edges; never require a pre-existing diagram. App guidance may supply a current screenshot and real target IDs: prefer guideControl or focusControl for tutorials. Without a supplied snapshot, never invent positions of real UI controls. Keep spoken guidance concise.\n" : "\nFloating mode is inactive; do not request drawOnScreen.\n"
        let memory = memoryContext(for: text)
        let context = memory + "\n" + floatingContext + attachedText + "\n" + profile + "\n" + (String(actions.context.prefix(2000)) + "\nComputer action mode: " + ((preferences.alwaysAllowComputerActions ?? false) ? "Always allow supported computer actions in granted folders; app executes automatically. Paid image generation still requires review." : "Review each computer action before execution.")) + "\n" + String(knowledge.context(for: text, only: mention.connectors).prefix(5000))
        modelTask = Task { [weak self] in
            do {
                var requestContext = context
                if floatingRequest, let note=shared.first(where: { $0.note?.hasPrefix("diagram-reference:") == true })?.note {
                    let id=String(note.dropFirst("diagram-reference:".count))
                    if DiagramReference.validID(id) { requestContext = DiagramReference.presentationInstruction(id) + "\n" + requestContext }
                }
                var requestImages = images
                var screenCapture: AttachedContext?
                if floatingRequest, !shared.contains(where: { $0.note?.hasPrefix("diagram-reference") == true }) {
                    self?.requestPhase = "Preparing screen context if needed"
                    screenCapture = try await self?.prepareFloatingContext?(text)
                } else if images.isEmpty, ScreenQuestionPolicy.wantsSnapshot(text) {
                    self?.requestPhase = "Reading the visible app"
                    guard let app = ScreenGuidance.currentApp else { throw IrisFailure.message("Open the app containing your diagram, then return to Iris and ask again.") }
                    let captured = try await ScreenGuidance.capture(app: app)
                    guard ScreenGuidance.foregroundPID == captured.pid else { throw IrisFailure.message("The app changed while capturing. Ask again with the diagram visible.") }
                    screenCapture = captured.attachment
                }
                if floatingRequest, images.isEmpty, mention.creation == nil, DiagramReference.wantsOnline(text) {
                    self?.requestPhase = "Finding a sourced diagram"
                    let reference = try await DiagramReferenceStore.search(text)
                    try Task.checkCancellation()
                    guard let self, self.requestID == currentRequest else {return}
                    let diagram=try JSONEncoder().encode(reference.drawing)
                    try self.actions.drawOnScreen?(String(decoding:diagram,as:UTF8.self))
                    requestImages.append(try DiagramReferenceStore.modelImage(reference.id))
                    requestContext = DiagramReference.presentationInstruction(reference.id) + "\nSource: \(reference.sourceURL). Credit: \(reference.credit).\n" + requestContext
                    self.requestPhase = "Explaining the reference diagram"
                }
                if let capture = screenCapture {
                    sharedScreen = capture.image != nil
                    guard requestImages.count < AttachmentReader.maximumCount else { throw IrisFailure.message("Remove an image attachment to make room for the app-guidance screenshot.") }
                    requestContext = capture.text + "\n" + requestContext
                    if let image = capture.image { requestImages.append(image) }
                    self?.requestPhase = "Interpreting the shared screen"
                } else if ScreenQuestionPolicy.wantsSnapshot(text), requestImages.isEmpty {
                    requestContext = "No screen image was shared for this request. Explain the missing screen-sharing setup; do not pretend to inspect the screen.\n" + requestContext
                }
                try Task.checkCancellation()
                var ready = snapshot
                if ready.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let models = ready.source == .local ? try await ModelService.models(server: ready.server) : try await CloudModelService.models(source: ready.source)
                    ready.model = try ProviderReadiness.model(requested: ready.model, available: models)
                    guard let self, self.requestID == currentRequest else { return }
                    if self.preferences.source == snapshot.source, self.preferences.server == snapshot.server, self.preferences.model.isEmpty {
                        self.data.preferences.model = ready.model; self.availableModels = models; self.save()
                    }
                }
                if LiveDataIntent.wantsWeather(text) { self?.requestPhase = "Checking live weather" }
                guard let liveService = self?.liveData else { return }
                let live = try await liveService.prepare(prompt: text, preferences: snapshot, conversation: liveConversation)
                try Task.checkCancellation()
                let reply: String
                if ready.source == .local { reply = try await ModelService.answer(server: ready.server, model: ready.model, messages: history, context: requestContext, role: snapshot.role, skill: skill, personality: snapshot.personality, images: requestImages, liveData: live.context, onPartial: onPartial) }
                else { reply = try await CloudModelService.answer(source: ready.source, model: ready.model, messages: history, context: requestContext, skill: skill, personality: snapshot.personality, images: requestImages, liveData: live.context, onPartial: onPartial) }
                guard !Task.isCancelled, let self else { return }
                if self.preferences.source == ready.source, self.preferences.server == ready.server, self.preferences.model == ready.model {
                    self.data.preferences.providerVerified = true; self.connectionResult = "Connected · response received"; self.save()
                }
                let plan = mention.creation == nil ? ActionPolicy.parse(StreamingPresentation.withoutReasoning(reply)) : nil
                if let plan { self.queueActions(plan) }
                var visible = ResponsePresentation.visibleText(reply)
                var createdFiles: [ChatFileReference] = []
                if let kind = mention.creation {
                    self.requestPhase = "Saving to Library"
                    do {
                        let file = try ChatCreationFiles.save(reply: reply, prompt: text, kind: kind)
                        createdFiles = [file]
                        self.recordCreation(title: file.name, kind: kind.rawValue, file: file)
                        visible = "Created your " + kind.title.lowercased() + ". Open it below, or find it again in Library."
                    } catch {
                        self.recordCreation(title: "Unsaved " + kind.title, kind: "draft", text: CreationPolicy.editableText(reply))
                        throw error
                    }
                }
                if visible.isEmpty { visible = plan == nil ? "I couldn't prepare that action. Please try again." : ((self.preferences.alwaysAllowComputerActions ?? false) ? "I’m preparing the requested action." : "I’ve prepared an action for you to review.") }
                if live.hasWeather, !visible.contains("open-meteo.com") { visible += "\n\n[Weather source: Open-Meteo](https://open-meteo.com/)" }
                if self.floatingActive { self.floatingReply = visible }
                self.messages.append(.init(role: "assistant", text: visible, files: createdFiles.isEmpty ? nil : createdFiles))
                self.attachments = []
                self.liveReply = ""; self.requestPhase = ""; self.requestID = nil; self.busy = false
                let visualPlan = floatingRequest && (plan?.contains { ["drawOnScreen", "guideControl", "focusControl"].contains($0.type) } ?? false)
                if visualPlan { self.voice.stopSpeaking() }
                else if streamSpeech { self.voice.updateStreamingReply(visible, final: true); if floatingRequest && self.floatingActive && self.voice.speechError != nil { self.reportFloatingSpeechFailure() } }
                else if shouldSpeak && (!floatingRequest || self.floatingActive) {
                    self.voice.speak((floatingRequest || plan == nil) ? visible : ((self.preferences.alwaysAllowComputerActions ?? false) ? "I’m preparing the requested action." : "I’ve prepared an action for you to review."), identifier: self.preferences.voiceID, rate: self.preferences.speechRate ?? 0.49, provider: self.preferences.speechProvider, server: self.preferences.voiceBoxServer ?? VoiceBoxClient.defaultServer, profile: self.preferences.voiceBoxProfile, speed: (self.preferences.speechProvider) == "gemini" ? (self.preferences.geminiSpeechSpeed ?? 1) : (self.preferences.voiceBoxSpeed ?? 1), geminiVoice: self.preferences.geminiVoice ?? GeminiSpeechClient.defaultVoice, geminiModel: self.preferences.geminiSpeechModel ?? GeminiSpeechClient.defaultModel, geminiStyle: self.preferences.replySpeechStyle, geminiAuth: self.preferences.geminiSpeechAuth ?? "apiKey", economy: self.preferences.geminiSpeechEconomy ?? true, fishVoice: self.preferences.selectedFishVoice)
                }
                self.spokenRequest = false
                self.welcome.receiveActualReply(visible)
                self.runAutomaticActions()
            } catch {
                guard !Task.isCancelled, let self else { return }
                if !self.liveReply.isEmpty { self.messages.append(.init(role: "assistant", text: self.liveReply + "\n\n_Response interrupted._")) }
                self.liveReply = ""; self.requestPhase = ""; self.requestID = nil
                if self.draft.isEmpty { self.draft = typed }
                self.voice.stopSpeaking()
                self.error = "The response was interrupted. \(error.localizedDescription)"; self.busy = false; self.spokenRequest = false; self.welcome.receiveActualFailure(error.localizedDescription)
                if floatingRequest && self.floatingActive { self.speakFloatingReply("I couldn’t finish that. " + error.localizedDescription) }
            }
        }
    }
    var currentAgentConversation: UUID { conversationID }
    func receiveAgentCompletion(_ run: AgentRun, files: [ChatFileReference]) {
        notice = "\(run.name) finished. Its result is in Agents and Library."
        if conversationID == run.originConversation {
            messages.append(.init(role: "assistant", text: "**\(run.name)** finished: \(AgentPolicy.title(for: run.task)). Open the result below or review its work in Agents.", files: files))
        }
    }
    private func persistConversation() {
        guard !restoringConversation else { return }
        var conversations = data.conversations ?? []
        if !messages.isEmpty {
            let conversation = ChatConversation(skillID: activeStudioSkill?.rawValue, id: conversationID, updatedAt: Date(), messages: messages)
            if let index = conversations.firstIndex(where: { $0.id == conversationID }) { conversations[index] = conversation }
            else { conversations.append(conversation) }
        }
        for message in messages where message.role == "assistant" { for file in message.files ?? [] {
            if !(data.createdItems ?? []).contains(where: { $0.file?.id == file.id }) { data.createdItems = (data.createdItems ?? []) + [.init(title: file.name, kind: "file", file: file)] }
        } }
        data.conversations = conversations; data.activeConversationID = conversationID; save()
    }
    func newConversation() {
        cancelModel(); voice.stop(); voice.stopSpeaking(); spokenRequest = false
        contextTask?.cancel(); contextTask = nil; contextBusy = false
        actions.pending = []; actions.result = ""; attachments = []; draft = ""; error = nil; activeStudioSkill = nil; studioReferences = []
        conversationID = UUID(); messages = []; notice = nil; workspaceSection = .today
    }
    func openConversation(_ conversation: ChatConversation) {
        newConversation(); restoringConversation = true
        conversationID = conversation.id; messages = conversation.messages; activeStudioSkill = conversation.skillID.flatMap(StudioSkill.init(rawValue:))
        if let skill = activeStudioSkill { UserDefaults.standard.set(skill.student ? "Student" : "Developer", forKey: "IrisStudioModeV2") }
        restoringConversation = false; data.activeConversationID = conversation.id; workspaceSection = .today; save()
    }
    func deleteConversation(_ id: UUID) {
        if id == conversationID { newConversation() }
        data.conversations?.removeAll { $0.id == id }; save()
    }
    func cancelModel() {
        voice.stopSpeaking()
        requestID = nil; modelTask?.cancel(); modelTask = nil; actionTask?.cancel(); actionTask = nil
        if !liveReply.isEmpty { messages.append(.init(role: "assistant", text: liveReply + "\n\n_Response stopped._")) }
        liveReply = ""; requestPhase = ""; busy = false; spokenRequest = false
        notice = "Request stopped. You can edit and send again."
    }
    func testConnection() { refreshConnection(immediate: true) }
    func refreshConnection(immediate: Bool = false) {
        connectionTask?.cancel(); connectionTimeout?.cancel()
        let id = UUID(); connectionCheckID = id
        let snapshot = preferences
        testing = true; connectionResult = "Checking connection…"
        connectionTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(15)) } catch { return }
            guard let self, self.connectionCheckID == id, self.testing else { return }
            self.connectionCheckID = UUID(); self.connectionTask?.cancel(); self.connectionTask = nil; self.testing = false
            self.connectionResult = "Connection check paused. Reconnect your provider, or retry when the server is ready. No test message was sent."
        }
        connectionTask = Task { [weak self] in
            defer {
                if let self, self.connectionCheckID == id { self.testing = false; self.connectionTask = nil; self.connectionTimeout?.cancel() }
            }
            do {
                if !immediate { try await Task.sleep(nanoseconds: 600_000_000) }
                let models = snapshot.source == .local ? try await ModelService.models(server: snapshot.server) : try await CloudModelService.models(source: snapshot.source)
                try Task.checkCancellation()
                guard let self, self.connectionCheckID == id,
                      self.preferences.source == snapshot.source, self.preferences.server == snapshot.server,
                      self.preferences.model == snapshot.model else { return }
                self.availableModels = models
                self.data.preferences.model = try ProviderReadiness.model(requested: snapshot.model, available: models)
                self.connectionResult = "Connected · ready to chat"
                self.data.preferences.providerVerified = true; self.save()
            } catch {
                guard !Task.isCancelled, let self, self.connectionCheckID == id else { return }
                self.connectionResult = error.localizedDescription
                self.data.preferences.providerVerified = false
            }
        }
    }
    func startStudio(_ skill: StudioSkill) {
        newConversation(); activeStudioSkill = skill; workspaceSection = .tools
    }
    func chooseStudioReference() {
        guard !contextBusy, !busy else { return }
        guard studioReferences.count < 3 else { error = "Use up to three references per task."; return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false
        panel.allowedContentTypes = AttachmentReader.contentTypes
        panel.message = "Read locally. Generate sends extracted text and attached images to your selected AI provider."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        contextBusy = true
        contextTask = Task {
            defer { contextBusy = false }
            do { let item = try await ContextReader.read(url: url); try Task.checkCancellation(); studioReferences.append(item) }
            catch { self.error = error.localizedDescription }
        }
    }
    func chooseFile() {
        guard !contextBusy, !busy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.message = "Attach up to six files (20 MB each). Images and extracted document text are sent only when you press Send."
        panel.allowedContentTypes = AttachmentReader.contentTypes
        // Permit text/code extensions macOS may not classify correctly; the reader validates their contents.
        panel.allowsOtherFileTypes = true
        guard panel.runModal() == .OK else { return }
        attachFiles(panel.urls)
    }
    @discardableResult func attachClipboardData(_ data:Data,extension ext:String)->Bool {
        guard !busy,!contextBusy else{error="Finish the current task before attaching files.";return false}
        guard attachments.count<AttachmentReader.maximumCount else{error="Attach up to six files per message.";return false}
        do {let url=try ComposerPasteboard.save(data,extension:ext);attachFiles([url]);return true}
        catch{self.error=error.localizedDescription;return false}
    }
    func pasteAttachment() {
        guard let payload=ComposerPasteboard.read(.general) else{error="Copy an image or local files first. Paste ordinary text into your message.";return}
        switch payload {case .files(let urls):attachFiles(urls);case .data(let data,let ext):_ = attachClipboardData(data,extension:ext)}
    }
    func attachFiles(_ urls: [URL]) {
        guard !busy, !contextBusy, !urls.isEmpty else { return }
        guard attachments.count + urls.count <= AttachmentReader.maximumCount else { error = "Attach up to six files per message. Remove a file before adding more."; return }
        contextBusy = true; error = nil
        contextTask = Task {
            defer { if !Task.isCancelled { contextBusy = false } }
            var failures: [String] = []
            for url in urls {
                do {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                    let bookmark = try url.bookmarkData(options: IrisLocalStorage.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
                    var item = try await ContextReader.read(url: url)
                    try Task.checkCancellation()
                    item.file = .init(name: url.lastPathComponent, bookmark: bookmark)
                    attachments.append(item)
                } catch is CancellationError { return }
                catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            guard !Task.isCancelled else { return }
            if !failures.isEmpty { error = failures.joined(separator: "\n") }
            tab = .ask; expanded = true
        }
    }
    func captureScreen() {
        guard ContextPolicy.permitsCapture(bundleID: foregroundID, allowlist: preferences.allowedCaptureApps), let id = foregroundID else {
            error = "Screen reading is off for this app. Allow a specific non-sensitive app in Privacy settings. Browsers and sensitive apps stay excluded."; return
        }
        let display = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == preferences.displayID } ?? NSScreen.main
        guard let displayID = display?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return }
        contextBusy = true
        contextTask = Task {
            defer { contextBusy = false }
            do { let item = try await ContextReader.capture(bundleID: id, displayID: displayID); try Task.checkCancellation(); attachments = [item]; tab = .ask; expanded = true }
            catch { self.error = error.localizedDescription }
        }
    }
    func summon() {
        if welcome.active { tab = .ask; notchPinned = true; expanded = true; if welcome.voiceEnabled { if welcome.progress.stage == .notch, !welcome.progress.canAdvance { welcome.speak(welcome.question) } else { welcome.listen() } }; return }
        tab = .ask; notchPinned = true; expanded = true
        if preferences.listenOnSummon ?? true { startListening() }
    }
    func toggleVoice() {
        if voice.listening || voice.requesting { voice.stop(); return }
        tab = .ask; expanded = true; startListening()
    }
    func previewPersonality(_ personality: IrisPersonality, text: String) {
        guard !busy, !voice.listening, !voice.requesting else { return }
        voice.speak(text, identifier: preferences.voiceID, rate: preferences.speechRate ?? 0.49, provider: preferences.speechProvider, server: preferences.voiceBoxServer ?? VoiceBoxClient.defaultServer, profile: preferences.voiceBoxProfile, speed: (preferences.speechProvider) == "gemini" ? (preferences.geminiSpeechSpeed ?? 1) : (preferences.voiceBoxSpeed ?? 1), preview: true, geminiVoice: preferences.geminiVoice ?? GeminiSpeechClient.defaultVoice, geminiModel: preferences.geminiSpeechModel ?? GeminiSpeechClient.defaultModel, geminiStyle: preferences.personalityID != nil && (preferences.personalityVoiceTone ?? true) ? personality.delivery : (preferences.geminiSpeechStyle ?? "Natural"), geminiAuth: preferences.geminiSpeechAuth ?? "apiKey", economy: preferences.geminiSpeechEconomy ?? true, fishVoice: preferences.selectedFishVoice)
    }
    func reportFloatingSpeechFailure() {
        guard floatingActive, !floatingReply.isEmpty else { return }
        notice = voice.speechError ?? "Voice unavailable. Your answer is still visible."
    }
    func speakFloatingReply(_ text: String) {
        guard floatingActive else { return }
        floatingReply = text
        voice.speak(text, identifier: preferences.voiceID, rate: preferences.speechRate ?? 0.49, provider: preferences.speechProvider, server: preferences.voiceBoxServer ?? VoiceBoxClient.defaultServer, profile: preferences.voiceBoxProfile, speed: (preferences.speechProvider) == "gemini" ? (preferences.geminiSpeechSpeed ?? 1) : (preferences.voiceBoxSpeed ?? 1), geminiVoice: preferences.geminiVoice ?? GeminiSpeechClient.defaultVoice, geminiModel: preferences.geminiSpeechModel ?? GeminiSpeechClient.defaultModel, geminiStyle: preferences.replySpeechStyle, geminiAuth: preferences.geminiSpeechAuth ?? "apiKey", economy: preferences.geminiSpeechEconomy ?? true, fishVoice: preferences.selectedFishVoice)
    }
    func listenFromFloating() {
        if welcome.active, welcome.progress.stage != .explore { welcome.listen(); return }
        collapsePresence()
        if voice.listening || voice.requesting { voice.stop(); return }
        guard !busy else { return }
        voice.stopSpeaking(); startListening()
    }
    private func startListening() {
        if welcome.active, welcome.progress.stage != .explore { welcome.listen(); return }
        guard !busy else { return }
        Task { [weak self] in
            guard let self else { return }
            await voice.start(recognizerProvider:preferences.speechRecognitionProvider ?? "apple",server:preferences.voiceBoxServer ?? VoiceBoxClient.defaultServer,onText: { [weak self] in self?.draft = $0 }, onError: { [weak self] in self?.error = $0 }, onFinal: { [weak self] text in
                guard let self, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                self.draft = text; self.spokenRequest = true; self.ask()
            })
        }
    }
    func exportReply(_ message: ChatMessage, format: String) {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Iris response." + format
        panel.allowedContentTypes = [UTType(filenameExtension: format) ?? .plainText]; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = ResponsePresentation.visibleText(message.text).components(separatedBy: "```iris-study")[0]
            let data = try DocumentWriter.data(content: text, format: format)
            try data.write(to: url, options: .atomic)
            let bookmark = try url.bookmarkData(options: IrisLocalStorage.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            messages.append(.init(role: "assistant", text: "Exported " + url.lastPathComponent + ".", files: [.init(name: url.lastPathComponent, bookmark: bookmark)]))
        } catch { self.error = error.localizedDescription }
    }
    func openChatFile(_ reference: ChatFileReference) {
        do { try actions.openFile(reference) } catch { self.error = error.localizedDescription }
    }
    func useChatFile(_ reference: ChatFileReference) {
        guard !contextBusy, !busy else { return }
        guard attachments.count < AttachmentReader.maximumCount else { error = "Attach up to six files per message."; return }
        contextBusy = true
        contextTask = Task {
            defer { if !Task.isCancelled { contextBusy = false } }
            do { let item = try await actions.readForAttachment(reference); try Task.checkCancellation(); attachments.append(item); tab = .ask }
            catch { self.error = error.localizedDescription }
        }
    }
    func playDiagram(_ entry: DiagramLibrary.Entry, narrate: Bool = true) {
        guard floatingActive else { error = "Open floating Iris to play a diagram."; return }
        guard !busy else { error = "Stop or finish the current task before opening a diagram."; return }
        voice.stop(); voice.stopSpeaking(); error = nil
        floatingReply = narrate ? "Opening " + entry.title + "." : ""
        let content = "{\"preset\":\"" + entry.id + "\",\"narrate\":" + (narrate ? "true" : "false") + "}"
        queueActions([.init(type: "drawOnScreen", content: content)])
    }
    func queueActions(_ plan: [AssistantAction]) {
        actions.pending = plan
        runAutomaticActions()
    }
    func runAutomaticActions() {
        guard !busy, !agents.computerBusy, !computer.running, let first = actions.pending.first,
              ActionPolicy.mayRunAutomatically(first, enabled: preferences.alwaysAllowComputerActions ?? false) else { return }
        perform(first, automatic: true)
    }
    func perform(_ action: AssistantAction, automatic: Bool = false) {
        if action.type == "computerTask" {
            guard !busy, !agents.computerBusy, !computer.running else { return }
            actions.pending.removeAll { $0.id == action.id }
            computer.start(action.target ?? "", preferences: preferences, files: actions) { [weak self] outcome in
                guard let self else { return }
                self.messages.append(.init(role: "assistant", text: outcome))
                if self.floatingActive { self.speakFloatingReply(outcome) }
            }
            return
        }
        guard !computer.running else { notice = "Pause or stop the active computer task first."; return }
        guard !busy, !agents.computerBusy else { notice = "An agent is using the computer. Try this action when it finishes."; return }
        let batch = automatic ? actions.pending : [action]
        busy = true; requestStarted = Date(); requestPhase = action.displayName; liveReply = ""
        actionTask = Task {
            var succeeded = false
            do {
                for next in batch {
                    try Task.checkCancellation()
                    if automatic && !ActionPolicy.mayRunAutomatically(next, enabled: preferences.alwaysAllowComputerActions ?? false) { break }
                    requestPhase = next.displayName
                    let outcome = try await actions.execute(next)
                    guard !Task.isCancelled else { return }
                    if next.type == "readFile" || next.type == "listFiles" {
                        actions.result = outcome
                        messages.append(.init(role: "assistant", text: "Read locally. Open a file below, or attach its text if you want to send it to your model.", files: actions.producedFiles))
                    } else { messages.append(.init(role: "assistant", text: outcome, files: actions.producedFiles)) }
                    if floatingActive && ["guideControl", "focusControl"].contains(next.type) { speakFloatingReply(next.content ?? floatingReply) }
                    else if floatingActive && next.type == "drawOnScreen" {
                        if (try? ScreenDrawing.decode(next.content ?? "").narrate) != true, !floatingReply.isEmpty { speakFloatingReply(floatingReply) }
                    } else if floatingActive { speakFloatingReply(outcome) }
                    actions.pending.removeAll { $0.id == next.id }
                }
                succeeded = true
            } catch { if !Task.isCancelled { self.error = error.localizedDescription; if floatingActive { speakFloatingReply("That action couldn’t finish. " + error.localizedDescription) } } }
            if !Task.isCancelled {
                busy = false; requestPhase = ""; actionTask = nil
                if succeeded && !automatic { runAutomaticActions() }
            }
        }
    }
    func searchWeb(_ query: String) {
        Task {
            do { _ = try await BrowserService.open(BrowserPolicy.searchURL(query), browser: preferences.preferredBrowser) }
            catch { self.error = error.localizedDescription }
        }
    }
    func updateForeground(_ app: NSRunningApplication) {
        guard preferences.observeApps else { foregroundName = "No context shared"; foregroundID = nil; return }
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        foregroundID = app.bundleIdentifier
        let sensitive = !ContextPolicy.permitsCapture(bundleID: app.bundleIdentifier, allowlist: preferences.allowedCaptureApps)
        foregroundName = sensitive ? "\(app.localizedName ?? "App") · protected" : (app.localizedName ?? "Allowed app")
    }
    func updateBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any], let capacity = values[kIOPSCurrentCapacityKey] as? Int else { continue }
            let max = values[kIOPSMaxCapacityKey] as? Int ?? 100
            battery = Int(Double(capacity) / Double(Swift.max(1, max)) * 100); charging = values[kIOPSIsChargingKey] as? Bool ?? false
        }
    }
    func showWorkspace(_ section: WorkspaceSection = .today) { collapsePresence(); workspaceSection = section; openWorkspace?() }
    func timeString(_ seconds: TimeInterval) -> String { let s = max(0, Int(ceil(seconds))); return String(format: "%02d:%02d", s / 60, s % 60) }
    func shutdown() {
        computer.shutdown()
        knowledgeScanTask?.cancel()
        welcome.pause(); connectionTimeout?.cancel(); agents.shutdown()
        connections.stopAutomaticRefresh(); connections.cancel(); accounts.cancel(); voice.stop(); voice.stopSpeaking(); modelTask?.cancel(); contextTask?.cancel(); sessionTimer?.invalidate(); network.cancel(); save()
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let batterySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), batterySource, .defaultMode) }
    }
}
