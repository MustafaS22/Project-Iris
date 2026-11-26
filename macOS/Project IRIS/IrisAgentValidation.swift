#if DEBUG
import AppKit
import SwiftUI

/// Deterministic native UI previews and integration checks; no provider or voice calls.
@MainActor enum IrisAgentValidation {
    static func knowledgeMemory(_ iris: IrisOrchestrator) async {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("IrisKnowledgeMemoryValidation")
        func waitForScan() async throws {
            for _ in 0..<500 { if !iris.knowledgeScanning { return }; try await Task.sleep(for: .milliseconds(10)) }
            throw IrisFailure.message("Scan did not settle")
        }
        func response(_ prompt: String) throws -> String {
            let body = try JSONSerialization.jsonObject(with: Data(prompt.utf8)) as! [String: [[String: String]]]
            let records = body["records"]!.map { ["id": $0["id"]!, "facts": ["Synthetic physics revision uses worked examples."]] as [String: Any] }
            return String(decoding: try JSONSerialization.data(withJSONObject: ["records": records]), as: UTF8.self)
        }
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            iris.data = PersistedState()
            guard ProcessInfo.processInfo.arguments.contains("--iris-validation"), iris.knowledge.documents.isEmpty else { throw IrisFailure.message("Validation requires a fresh, isolated database") }
            try iris.knowledge.ingest([
                .init(externalID: "scan-fixture", source: .files, title: "Physics revision", body: String(repeating: "Synthetic physics reference. ", count: 900), updatedAt: Date()),
                .init(externalID: "private-fixture", source: .gmail, title: "Disabled source", body: "Never send this disabled reference", updatedAt: Date())
            ])
            try iris.knowledge.setSharing(.files, enabled: true)
            iris.data.notes = [.init(text: "Physics exam preparation with worked examples.")]
            var requests = 0
            iris.knowledgeScanResponder = { prompt in
                requests += 1
                guard !prompt.contains("Never send this disabled") else { throw IrisFailure.message("Disabled source was sent") }
                return try response(prompt)
            }
            iris.scanKnowledgeNow(); try await waitForScan()
            guard iris.knowledgeScanIssue == nil, requests > 1, iris.data.knowledgeScanAt != nil,
                  KnowledgeMemoryPlan.pending(KnowledgeMemoryPlan.chunks(iris.knowledgeScanInputs), records: iris.data.knowledgeMemories ?? []).isEmpty,
                  iris.memoryContext(for: "physics").contains("Synthetic physics") else { throw IrisFailure.message("Full scan or retrieval failed") }
            let firstCount = requests
            iris.scanKnowledgeNow(); try await waitForScan()
            guard requests == firstCount else { throw IrisFailure.message("Unchanged material used AI again") }
            for record in iris.visibleKnowledgeMemories { iris.forgetKnowledgeMemory(record.id) }
            iris.scanKnowledgeNow(); try await waitForScan()
            guard requests == firstCount, iris.visibleKnowledgeMemories.isEmpty else { throw IrisFailure.message("Forgotten facts reappeared") }
            iris.data.knowledgeMemories = nil; iris.data.notes = []
            iris.knowledgeScanResponder = { prompt in
                try iris.knowledge.setSharing(.files, enabled: false)
                return try response(prompt)
            }
            iris.scanKnowledgeNow(); try await waitForScan()
            guard (iris.data.knowledgeMemories ?? []).isEmpty else { throw IrisFailure.message("Revoked source was committed") }
            try iris.knowledge.setSharing(.files, enabled: true)
            iris.knowledgeScanResponder = { _ in "malformed reply" }
            iris.scanKnowledgeNow(); try await waitForScan()
            guard iris.knowledgeScanIssue != nil, (iris.data.knowledgeMemories ?? []).isEmpty else { throw IrisFailure.message("Invalid reply was marked scanned") }
            iris.knowledgeScanResponder = { prompt in try await Task.sleep(for: .seconds(1)); return try response(prompt) }
            iris.scanKnowledgeNow(); try await Task.sleep(for: .milliseconds(50)); iris.stopKnowledgeScan(); try await waitForScan()
            guard (iris.data.knowledgeMemories ?? []).isEmpty, iris.knowledgeScanIssue == nil else { throw IrisFailure.message("Cancelled scan committed results") }
            iris.knowledgeScanResponder = { try response($0) }
            iris.scanKnowledgeNow(); try await waitForScan()
            guard iris.knowledgeScanIssue == nil, !iris.visibleKnowledgeMemories.isEmpty else { throw IrisFailure.message("Resume failed") }
            iris.data.preferences.memoryEnabled = false
            guard iris.memoryContext(for: "physics").isEmpty else { throw IrisFailure.message("Disabled memory still retrieved") }
            iris.data.preferences.memoryEnabled = true
            try await render(KnowledgeLibraryView(iris: iris), size: .init(width: 760, height: 720), to: output.appendingPathComponent("knowledge-compact.png"))
            try await render(KnowledgeLibraryView(iris: iris), size: .init(width: 1080, height: 740), to: output.appendingPathComponent("knowledge-wide.png"))
            try await render(ScrollView { MemorySettingsView(iris: iris).padding(24) }, size: .init(width: 620, height: 640), to: output.appendingPathComponent("memories.png"))
            NSLog("IRIS_KNOWLEDGE_MEMORY_PASS %@", output.path)
        } catch { NSLog("IRIS_KNOWLEDGE_MEMORY_FAILED %@", error.localizedDescription) }
        iris.knowledgeScanTask?.cancel(); iris.knowledgeScanResponder = nil
        NSApp.terminate(nil)
    }
    static func run(_ iris: IrisOrchestrator) async {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("IrisAgentValidation")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            iris.data = PersistedState()
            let onComplete = iris.agents.didComplete
            iris.agents.didComplete = nil
            iris.agents.answer = { run, partial in
                if run.specialty == .writer { return "# Launch brief\n\nA clear story, one product promise, and a launch plan.\n\n## Deliverables\n- A concise product introduction\n- A week-by-week rollout\n- A checklist for launch day" }
                partial("## Building your study planner\n\nThe weekly calendar and subject list are taking shape. Next, I’m checking the interaction details against your brief.")
                try await Task.sleep(for: .seconds(120))
                return "Finished the local preview"
            }
            let forge = AgentRun(name: "Forge", specialty: .builder, hue: 0.55, task: "Build a complete study planner with a weekly timetable and subject reminders.", context: "", preferences: iris.preferences)
            let forgeID = try iris.agents.deploy(forge)
            let quill = AgentRun(name: "Quill", specialty: .writer, hue: 0.95, task: "Prepare the Iris launch brief and a rollout checklist.", context: "", preferences: iris.preferences)
            _ = try iris.agents.deploy(quill)
            var prism = AgentRun(name: "Prism", specialty: .analyst, hue: 0.36, task: "Compare the supplied biology notes and create a revision guide.", context: "", preferences: iris.preferences)
            prism.status = .waiting; prism.phase = "Review the requested computer actions"
            prism.pending = [.init(type: "createDocument", folder: ChatCreationFiles.folderID, path: "biology-guide.pdf", content: "# Revision guide\n\nA comparison of the supplied notes.", target: "pdf")]
            _ = try iris.agents.deploy(prism)
            try await Task.sleep(for: .milliseconds(500))
            iris.agents.selectedID = forgeID
            try await render(AgentWorkspace(iris: iris, store: iris.agents), size: NSSize(width: 1100, height: 720), to: output.appendingPathComponent("agents-desktop.png"))
            try await render(NotchAgentsView(iris: iris, store: iris.agents).padding(24).background(.black), size: NSSize(width: 560, height: 360), to: output.appendingPathComponent("agents-notch.png"))
            try await render(AgentCornerView(iris: iris, store: iris.agents, peek: AgentPeekModel()), size: NSSize(width: 160, height: 80), to: output.appendingPathComponent("agents-corner.png"))
            try await render(AgentCornerView(iris: iris, store: iris.agents, peek: AgentPeekModel(selectedID: forgeID)), size: NSSize(width: 316, height: 292), to: output.appendingPathComponent("agents-corner-expanded.png"))
            iris.agents.stop(forgeID); iris.agents.stop(prism.id)
            try await Task.sleep(for: .milliseconds(150))
            iris.agents.didComplete = onComplete
            iris.agents.answer = { _, _ in "<!doctype html><html><body><h1>Agent validation</h1></body></html>" }
            iris.draft = "@agent @website Build a study planner"
            iris.ask()
            guard !iris.busy, iris.draft.isEmpty, iris.messages.contains(where: { $0.text.contains("assigned this") }) else { throw IrisFailure.message("Chat did not hand off work to an agent") }
            let deployed = iris.agents.selectedID
            for _ in 0..<100 {
                if let deployed, iris.agents.run(deployed)?.status == .completed { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            guard let deployed, let result = iris.agents.run(deployed), result.status == .completed, let file = result.files.first, file.name.hasSuffix(".html"), let path = file.relativePath,
                  try String(contentsOf: ChatCreationFiles.fileURL(path), encoding: .utf8).contains("Agent validation") else { throw IrisFailure.message("Agent website wasn't saved as a real file") }
            iris.agents.shutdown()
            NSLog("IRIS_AGENT_VALIDATION_PASS %@", output.path)
        } catch { NSLog("IRIS_AGENT_VALIDATION_FAILED %@", error.localizedDescription) }
        NSApp.terminate(nil)
    }
    static func supportLayout(_ iris: IrisOrchestrator) async {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("IrisSupportValidation")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            iris.data = PersistedState()
            iris.draft = "/remember I prefer concise explanations with worked examples."
            iris.ask()
            guard !iris.busy, let saved = iris.data.memories?.first, iris.messages.last?.text.contains("Saved to memory") == true else { throw IrisFailure.message("Local memory command failed") }
            iris.editMemory(saved.id, text: "I prefer worked examples.")
            guard iris.data.memories?.first?.text == "I prefer worked examples." else { throw IrisFailure.message("Memory edit failed") }
            iris.forget(saved.id)
            guard iris.data.memories?.isEmpty == true else { throw IrisFailure.message("Memory removal failed") }
            iris.remember("I prefer concise explanations with worked examples.")
            for page in ["Memory", "Language", "Accessibility"] {
                try await render(AssistantSettingsView(iris: iris, initialSection: page), size: NSSize(width: 1000, height: 720), to: output.appendingPathComponent(page + ".png"))
            }
            NSLog("IRIS_SUPPORT_VISUAL_PASS %@", output.path)
        } catch { NSLog("IRIS_SUPPORT_VISUAL_FAILED %@", error.localizedDescription) }
        NSApp.terminate(nil)
    }
    static func knowledgeLayout(_ iris: IrisOrchestrator) async {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("IrisKnowledgeLayoutValidation")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            iris.data = PersistedState(); iris.workspaceSection = .knowledge
            for width in [880, 1260] {
                try await render(ContentView(iris: iris), size: NSSize(width: width, height: 720), to: output.appendingPathComponent("knowledge-\(width).png"))
            }
            NSLog("IRIS_KNOWLEDGE_LAYOUT_PASS %@", output.path)
        } catch { NSLog("IRIS_KNOWLEDGE_LAYOUT_FAILED %@", error.localizedDescription) }
        NSApp.terminate(nil)
    }
    static func welcomeLayout(_ iris: IrisOrchestrator) async {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("IrisWelcomeValidation")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            iris.data = PersistedState(); iris.welcome.voiceEnabled = false; iris.welcome.handsFree = false; iris.welcome.automaticTransitions = false
            iris.welcome.responder = { _, _ in "Thanks, Alex. What does your work or education look like?" }
            iris.welcome.start(resume: false); iris.welcome.submit("Alex")
            for _ in 0..<100 { if !iris.welcome.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
            guard iris.welcome.question.contains("education"), iris.welcome.progress.questionIndex == 1 else { throw IrisFailure.message("Adaptive interview reply failed") }
            iris.welcome.pause(); iris.welcome.submit("ignored while paused")
            guard iris.welcome.progress.questionIndex == 1 else { throw IrisFailure.message("Paused interview accepted input") }
            iris.welcome.responder = { _, _ in throw IrisFailure.message("Offline provider test") }
            iris.welcome.start(resume: true); iris.welcome.submit("I study computer science")
            for _ in 0..<100 { if !iris.welcome.busy { break }; try await Task.sleep(for: .milliseconds(10)) }
            guard iris.welcome.issue != nil, iris.welcome.progress.questionIndex == 2 else { throw IrisFailure.message("Provider failure lost the interview answer") }
            iris.welcome.responder = nil; iris.welcome.offline = true
            try await render(OnboardingView(iris: iris, finish: {}), size: NSSize(width: 940, height: 780), to: output.appendingPathComponent("01-connect.png"))
            try await render(OnboardingView(iris: iris, startAt: 1, finish: {}), size: NSSize(width: 940, height: 780), to: output.appendingPathComponent("02-voice.png"))
            iris.welcome.start(resume: false)
            for reply in ["Alex", "I study computer science and work part-time.", "A portfolio website and my next exams.", "Help me plan and explain with examples."] { iris.welcome.submit(reply) }
            guard iris.welcome.progress.stage == .notch, !iris.welcome.progress.canAdvance, iris.data.memories?.isEmpty != false else { throw IrisFailure.message("Interview progression or memory consent failed") }
            iris.welcome.noteShortcut(.notch); iris.welcome.submit("How could I plan my project?")
            guard iris.welcome.progress.canAdvance else { throw IrisFailure.message("Real shortcut and reply did not complete notch lesson") }
            try await render(WelcomeConversationView(iris: iris, journey: iris.welcome).padding(24), size: NSSize(width: 580, height: 490), to: output.appendingPathComponent("03-notch.png"))
            iris.welcome.next(); iris.welcome.noteShortcut(.floatingText); iris.welcome.noteDrag()
            iris.welcome.explainPractice("earth")
            guard iris.welcome.progress.demoTarget == "earth", !iris.welcome.progress.canAdvance else { throw IrisFailure.message("Practice explanation falsely completed floating lesson") }
            try await render(WelcomePracticeCanvas(iris: iris, journey: iris.welcome), size: NSSize(width: 660, height: 470), to: output.appendingPathComponent("04-canvas.png"))
            try await render(WelcomeCoachView(iris: iris, journey: iris.welcome), size: NSSize(width: 322, height: 228), to: output.appendingPathComponent("04-coach.png"))
            iris.welcome.submit("Help me find a starting point.")
            guard iris.welcome.progress.canAdvance else { throw IrisFailure.message("Floating practice did not complete") }
            iris.welcome.next()
            try await render(WelcomeConversationView(iris: iris, journey: iris.welcome).padding(24), size: NSSize(width: 580, height: 490), to: output.appendingPathComponent("04-drafting.png"))
            guard !iris.welcome.progress.canAdvance else { throw IrisFailure.message("Drafting completed without insertion") }
            iris.welcome.draftingInserted(); iris.welcome.next(); iris.welcome.next()
            try await render(WelcomeConversationView(iris: iris, journey: iris.welcome).padding(24), size: NSSize(width: 580, height: 490), to: output.appendingPathComponent("05-review.png"))
            iris.welcome.consentToSave = ["project"]; iris.welcome.finish()
            guard iris.data.memories?.count == 1, iris.data.memories?.first?.text.contains("portfolio") == true, iris.welcome.progress.answers.isEmpty, iris.data.notes.first?.text.contains("starting point") == true else { throw IrisFailure.message("Selected memory consent, starter plan or draft cleanup failed") }
            NSLog("IRIS_WELCOME_VALIDATION_PASS %@", output.path)
        } catch { NSLog("IRIS_WELCOME_VALIDATION_FAILED %@", error.localizedDescription) }
        NSApp.terminate(nil)
    }
    static func notchAppearance(_ iris: IrisOrchestrator) async {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("IrisNotchAppearanceValidation")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let outline = IrisNotchShape(bottomRadius: 14).path(in: CGRect(x: 0, y: 0, width: 320, height: 40))
            guard outline.contains(CGPoint(x: 5, y: 0.5)), !outline.contains(CGPoint(x: 5, y: 20)), outline.contains(CGPoint(x: 160, y: 20)) else { throw IrisFailure.message("Notch shoulders or transparent-gutter hit testing failed") }
            iris.data = PersistedState(); iris.data.preferences.name = "Alex"; iris.data.preferences.providerVerified = true; iris.tab = .focus
            for (label, expanded, accent) in [("collapsed", false, Color.orange), ("expanded-warm", true, Color(red: 0.91, green: 0.72, blue: 0.52)), ("expanded-blue", true, Color(red: 0.36, green: 0.65, blue: 0.95))] {
                iris.expanded = expanded; iris.data.preferences.theme = label.contains("blue") ? .ocean : .apricot
                let surface = NotchSurface(iris: iris, notchWidth: 180, notchHeight: 32, hasNotch: true, expandedWidth: 580, canvasSize: CGSize(width: 660, height: 550), onSize: { _ in }, onHover: { _ in }, onDrag: { _ in })
                let preview = VStack(spacing: 14) {
                    IrisNotchBackground(expanded: expanded, accent: accent).frame(width: expanded ? 600 : 316, height: expanded ? 300 : 40).clipShape(IrisNotchShape(bottomRadius: expanded ? 26 : 14))
                    surface
                }.padding(.horizontal, 20).background(Color(red: 0.07, green: 0.14, blue: 0.16))
                try await render(preview, size: NSSize(width: 700, height: expanded ? 900 : 620), to: output.appendingPathComponent(label + ".png"))
            }
            let traceCases: [(String, Bool, ComputerUsePresentation, Color)] = [
                ("trace-collapsed", false, .executing, .orange),
                ("trace-expanded", true, .executing, Color(red: 0.54, green: 0.67, blue: 1)),
                ("trace-waiting", false, .waiting, .orange),
                ("trace-idle", false, .idle, .orange)
            ]
            for (name, expanded, phase, accent) in traceCases {
                let shape = IrisNotchShape(bottomRadius: expanded ? 26 : 14)
                let preview = shape.fill(.black)
                    .frame(width: expanded ? 520 : 316, height: expanded ? 178 : 40)
                    .overlay { IrisNotchComputerGlow(shape: shape, phase: phase, accent: accent) }
                    .overlay { IrisAvatar(state: phase == .waiting ? .permission : .idle, color: accent, size: 30) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(red: 0.07, green: 0.11, blue: 0.14))
                try await render(preview, size: NSSize(width: 640, height: 230), to: output.appendingPathComponent(name + ".png"))
            }
            let cursor = IrisComputerCursor()
            try cursor.renderSample(to: output.appendingPathComponent("cursor-apricot.png"))
            cursor.accent = NSColor(srgbRed: 0.56, green: 0.72, blue: 1, alpha: 1)
            try cursor.renderSample(to: output.appendingPathComponent("cursor-blue.png"))
            NSLog("IRIS_NOTCH_APPEARANCE_PASS %@", output.path)
        } catch { NSLog("IRIS_NOTCH_APPEARANCE_FAILED %@", error.localizedDescription) }
        NSApp.terminate(nil)
    }
    static func render<V: View>(_ content: V, size: NSSize, to url: URL) async throws {
        let view = NSHostingView(rootView: content.background(IrisDesign.canvas).environment(\.irisControlAccent, Color.cyan).foregroundStyle(IrisDesign.text).preferredColorScheme(.dark))
        view.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view; view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(700))
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw IrisFailure.message("Native preview couldn't be rendered") }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw IrisFailure.message("Native preview couldn't be encoded") }
        try data.write(to: url); window.contentView = nil
    }
}
#endif
