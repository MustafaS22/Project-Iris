import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

/// Notebook requests are separate from assistant actions and cannot execute commands.
@MainActor final class NotebookSession: ObservableObject {
    @Published var busy = false
    @Published var reading = false
    @Published var partial = ""
    @Published var error: String?
    @Published var phase = ""
    @Published var activeNotebookID: UUID?
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    func stop() { requestID = UUID(); task?.cancel(); task = nil; busy = false; reading = false; partial = ""; phase = ""; activeNotebookID = nil }
    func addFiles(iris: IrisOrchestrator, id: UUID) {
        guard !busy, !reading, let book = iris.data.notebooks?.first(where: { $0.id == id }) else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false
        panel.allowedContentTypes = AttachmentReader.contentTypes.filter { $0 != .image }
        panel.message = "Add readable study material. Text is stored on this Mac and sent only when you ask or create a study output."
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        guard book.sources.count + urls.count <= 12 else { error = "A study space can contain 12 reading items. Select fewer files."; return }
        reading = true; error = nil
        let request = UUID(); requestID = request; activeNotebookID = id
        task = Task { [weak iris] in
            guard let iris else { return }
            defer { if requestID == request { reading = false; activeNotebookID = nil; task = nil } }
            do {
                var sources: [NotebookSource] = []
                for url in urls {
                    let item = try await ContextReader.read(url: url); try Task.checkCancellation()
                    guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw IrisFailure.message("\(item.name) contains no readable text. Choose a text document or searchable PDF.") }
                    sources.append(.init(name: item.name, text: String(item.text.prefix(18000))))
                }
                guard requestID == request, let index = iris.data.notebooks?.firstIndex(where: { $0.id == id }) else { return }
                iris.data.notebooks?[index].sources += sources; iris.data.notebooks?[index].updatedAt = Date(); iris.save()
            } catch { if !Task.isCancelled, requestID == request { self.error = error.localizedDescription } }
        }
    }
    func generate(iris: IrisOrchestrator, id: UUID, question: String, kind: String? = nil) {
        guard !busy, !reading, let book = iris.data.notebooks?.first(where: { $0.id == id }), !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let evidence = NotebookPolicy.evidence(book.sources)
        guard !evidence.isEmpty else { error = "Add a source and select it before asking Iris."; return }
        let request = UUID(); requestID = request; activeNotebookID = id; busy = true; error = nil; partial = ""; phase = "Reading selected sources…"
        let prefs = iris.preferences
        var history = book.turns.suffix(10).map { ChatMessage(role: $0.role, text: String($0.text.prefix(6000)).replacingOccurrences(of: "\\[S[0-9]+\\]", with: "", options: .regularExpression)) }
        // Historical answers are not evidence. Current evidence labels are local to this response.
        history.append(.init(role: "user", text: question))
        var instruction = NotebookPolicy.instruction
        if kind == "flashcards" { instruction += "\n" + StudioSkill.flashcards.instruction }
        if kind == "mindmap" { instruction += "\n" + StudioSkill.mindmap.instruction }
        if kind == "quiz" { instruction += "\nReturn five multiple-choice questions in a fenced iris-quiz JSON block: {\"questions\":[{\"question\":\"...\",\"options\":[\"...\",\"...\",\"...\"],\"answer\":0,\"explanation\":\"... [S1]\"}]}. answer is a zero-based correct option index. Include no other code blocks." }
        instruction += "\nStudy-space mode takes precedence over other task skills: no actions or tools. Cite only current source labels. Historical answers are not evidence."
        task = Task { [weak iris] in
            guard let iris else { return }
            do {
                var model = prefs.model
                if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let models = prefs.source == .local ? try await ModelService.models(server: prefs.server) : try await CloudModelService.models(source: prefs.source)
                    model = try ProviderReadiness.model(requested: model, available: models)
                }
                let context = NotebookPolicy.context(evidence)
                var last = Date.distantPast
                let onPartial: @MainActor (String) -> Void = { [weak self] raw in
                    guard let self, self.requestID == request, !Task.isCancelled, Date().timeIntervalSince(last) > 0.12 else { return }
                    last = Date(); self.partial = ResponsePresentation.visibleText(raw); self.phase = "Writing from your sources…"
                }
                let reply: String
                if prefs.source == .local { reply = try await ModelService.answer(server: prefs.server, model: model, messages: history, context: context, role: prefs.role, skill: instruction, personality: prefs.personality, images: [], onPartial: onPartial) }
                else { reply = try await CloudModelService.answer(source: prefs.source, model: model, messages: history, context: context, skill: instruction, personality: prefs.personality, images: [], onPartial: onPartial) }
                try Task.checkCancellation()
                guard requestID == request, let index = iris.data.notebooks?.firstIndex(where: { $0.id == id }) else { return }
                let text = ResponsePresentation.visibleText(reply).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { throw IrisFailure.message("Iris returned an empty answer. Try a more specific question.") }
                if let kind {
                    iris.data.notebooks?[index].outputs.insert(.init(title: Self.title(kind), kind: kind, text: text, evidence: evidence), at: 0)
                } else {
                    iris.data.notebooks?[index].turns += [.init(role: "user", text: question), .init(role: "assistant", text: text, evidence: evidence)]
                    if let turns = iris.data.notebooks?[index].turns { iris.data.notebooks?[index].turns = Array(turns.suffix(80)) }
                }
                iris.data.notebooks?[index].updatedAt = Date(); iris.save()
            } catch { if !Task.isCancelled, requestID == request { self.error = error.localizedDescription } }
            if requestID == request { busy = false; partial = ""; phase = ""; activeNotebookID = nil; task = nil }
        }
    }
    static func title(_ kind: String) -> String { ["summary":"Summary", "guide":"Study guide", "flashcards":"Flashcards", "mindmap":"Mind map", "quiz":"Practice quiz", "note":"Saved answer"][kind] ?? kind }
}
