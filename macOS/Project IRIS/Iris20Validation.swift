#if DEBUG
import AppKit
import ApplicationServices
import SwiftUI

/// Offline release validation. Never runs during a normal launch or uses production storage.
@MainActor enum Iris20Validation {
    static func run(_ iris: IrisOrchestrator) async {
        NSLog("IRIS_VALIDATION_ACCESSIBILITY_TRUST=%@", AXIsProcessTrusted() ? "yes" : "no")
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("Iris20Validation", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            iris.data = PersistedState()
            iris.data.preferences.source = .local; iris.data.preferences.server = "http://127.0.0.1:5189/v1"; iris.data.preferences.model = "iris-validation"
            iris.data.preferences.speakTypedReplies = false
            try iris.knowledge.ingest([
                .init(externalID: "validation-mail", source: .gmail, title: "Team retreat", body: "The retreat is Friday. Bring a notebook.", updatedAt: Date()),
                .init(externalID: "validation-private", source: .files, title: "Team retreat", body: "UNRELATED_PRIVATE_CONTEXT", updatedAt: Date())])
            try iris.knowledge.setSharing(.gmail, enabled: true); try iris.knowledge.setSharing(.files, enabled: true)
            func require(_ condition: Bool, _ message: String) throws { if !condition { throw IrisFailure.message(message) } }
            func finish() async throws {
                for _ in 0..<300 { if !iris.busy { break }; try await Task.sleep(for: .milliseconds(100)) }
                try require(!iris.busy && iris.error == nil, iris.error ?? "Request timed out")
            }
            iris.draft = "@gmail @website Build a retreat page"; iris.ask(); try await finish()
            let website = try XCTFile(iris, suffix: ".html")
            let html = try iris.actions.withFile(website) { try String(contentsOf: $0, encoding: .utf8) }
            try require(html.contains("<!doctype html>"), "Website wasn't a real HTML file")
            iris.draft = "@document Create a retreat checklist"; iris.ask(); try await finish()
            let pdf = try XCTFile(iris, suffix: ".pdf")
            let bytes = try iris.actions.withFile(pdf) { try Data(contentsOf: $0) }
            try require(bytes.starts(with: Data("%PDF".utf8)), "Document wasn't a real PDF")
            let attachedPDF = try await iris.actions.readForAttachment(pdf)
            try require(attachedPDF.text.lowercased().contains("checklist"), "A created PDF could not be reattached")
            iris.draft = "@flashcards Create two cards about biology"; iris.ask(); try await finish()
            try require(StudioArtifact.parse(iris.messages.last?.text ?? "")?.cards?.count == 2, "Flashcards lost their interactive contract")
            let count = iris.messages.count
            try iris.knowledge.setSharing(.gmail, enabled: false)
            iris.draft = "@gmail summarize the retreat"; iris.ask()
            try require(iris.messages.count == count && iris.error != nil, "A disabled source was submitted")
            iris.error = nil; iris.draft = "@image A friendly yellow robot"; iris.ask()
            try require(iris.busy && iris.activeCreation == .image && iris.actions.pending.isEmpty, "Explicit image request did not start directly")
            iris.cancelModel()
            try require(!iris.busy && iris.activeCreation == nil, "Canceled image did not clear generation progress")
            try require(Set((iris.data.createdItems ?? []).compactMap { $0.file?.id }).isSuperset(of: [website.id, pdf.id]), "Creations did not reach Library")
            let completedMessages = iris.messages
            iris.newConversation(); iris.data.conversations = []
            func snapshot<V: View>(_ view: V, name: String, size: CGSize) async throws {
                let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
                host.sizingOptions = []
                let window = NSWindow(contentRect: .init(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false; window.alphaValue = 0
                window.contentView = host; window.setContentSize(size); window.orderBack(nil)
                try await Task.sleep(for: .milliseconds(200))
                host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw IrisFailure.message("Snapshot allocation failed") }
                host.cacheDisplay(in: host.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { throw IrisFailure.message("Snapshot failed") }
                try png.write(to: output.appendingPathComponent(name + ".png"))
                window.orderOut(nil); window.close()
            }
            iris.data.conversations = [
                "@gmail @website Build a retreat page", "Help me plan tomorrow", "@document A letter to the team", "Explain the diagram on my screen", "@drive Summarize the project notes", "Ideas for the weekend"
            ].enumerated().map { index, text in ChatConversation(updatedAt: Date().addingTimeInterval(Double(-index * 3600)), messages: [.init(role: "user", text: text)]) }
            iris.draft = "@gmail @document Make a checklist for the retreat"
            try await snapshot(ContentView(iris: iris), name: "mention-highlight", size: .init(width: 1220, height: 820))
            iris.data.preferences.theme = .ocean
            try await snapshot(ChatMentionComposer(iris: iris, compact: true).padding(16).background(IrisDesign.canvas).environment(\.irisControlAccent, iris.accent).preferredColorScheme(.dark), name: "compact-highlight", size: .init(width: 600, height: 140))
            iris.data.preferences.theme = .apricot
            iris.messages = Array(completedMessages.prefix(2)); iris.draft = ""
            try await snapshot(ContentView(iris: iris), name: "conversation", size: .init(width: 1220, height: 820))
            try await snapshot(InlineDraftArrival(color: iris.accent).background(IrisDesign.canvas), name: "doubletap-arrival", size: .init(width: 84, height: 84))
            iris.workspaceSection = .settings
            try await snapshot(ContentView(iris: iris), name: "settings", size: .init(width: 1220, height: 820))
            try await snapshot(ContentView(iris: iris), name: "settings-narrow", size: .init(width: 880, height: 700))
            iris.workspaceSection = .knowledge
            try await snapshot(ContentView(iris: iris), name: "knowledge", size: .init(width: 1220, height: 820))
            try await snapshot(AssistantSettingsView(iris: iris, initialSection: "Privacy").background(IrisDesign.canvas).preferredColorScheme(.dark), name: "privacy", size: .init(width: 920, height: 740))
            try await snapshot(AssistantSettingsView(iris: iris, initialSection: "App testing").background(IrisDesign.canvas).preferredColorScheme(.dark), name: "testing", size: .init(width: 920, height: 740))
            try await snapshot(AssistantSettingsView(iris: iris, initialSection: "Connections").background(IrisDesign.canvas).preferredColorScheme(.dark), name: "connections", size: .init(width: 920, height: 740))
            iris.workspaceSection = .library
            try await snapshot(ContentView(iris: iris), name: "library", size: .init(width: 1220, height: 820))
            try Data("PASS: website HTML, PDF bytes, Library persistence, flashcard contract, disabled-source rejection, direct image start and cancel. Eight native snapshots written.\n".utf8).write(to: output.appendingPathComponent("result.txt"))
        } catch { try? Data(("FAIL: " + error.localizedDescription).utf8).write(to: output.appendingPathComponent("result.txt")) }
        NSApp.terminate(nil)
    }
    private static func XCTFile(_ iris: IrisOrchestrator, suffix: String) throws -> ChatFileReference {
        guard let file = iris.messages.last?.files?.first, file.name.hasSuffix(suffix), file.folderID == ChatCreationFiles.folderID else { throw IrisFailure.message("The created file card is missing") }
        return file
    }
}

#endif
