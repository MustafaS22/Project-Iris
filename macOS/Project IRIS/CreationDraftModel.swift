import SwiftUI
import Combine
import AppKit
import UniformTypeIdentifiers

/// Draft generation has no action executor: file writes happen only through explicit local export.
@MainActor
final class CreationDraftModel: ObservableObject {
    @Published var content = UserDefaults.standard.string(forKey: "IrisCreationDraftV2") ?? ""
    @Published var previousVersion = UserDefaults.standard.string(forKey: "IrisCreationPreviousDraftV2") ?? ""
    @Published var references: [AttachedContext] = []
    @Published var busy = false
    @Published var reading = false
    @Published var error: String?
    @Published var status = ""
    @Published var exports: [ChatFileReference] = []
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    init() {
        if let data = UserDefaults.standard.data(forKey: "IrisCreationExportsV2") { exports = (try? JSONDecoder().decode([ChatFileReference].self, from: data)) ?? [] }
    }
    func saveInLibrary(iris: IrisOrchestrator) {
        guard !busy, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !(iris.data.createdItems ?? []).contains(where: { $0.text == content }) else { return }
        iris.recordCreation(title: String((UserDefaults.standard.string(forKey: "IrisCreateBriefV2") ?? "Saved draft").prefix(80)), kind: "draft", text: content)
    }
    func newDraft() {
        if !content.isEmpty { previousVersion = content; UserDefaults.standard.set(previousVersion, forKey: "IrisCreationPreviousDraftV2") }
        content = ""; error = nil; status = "New draft · previous version available"; persist()
    }
    func restorePrevious() {
        let current = content; content = previousVersion; previousVersion = current
        UserDefaults.standard.set(previousVersion, forKey: "IrisCreationPreviousDraftV2"); persist()
        status = "Previous draft restored"
    }
    func persist() { UserDefaults.standard.set(content, forKey: "IrisCreationDraftV2") }
    func stop() { requestID = UUID(); task?.cancel(); task = nil; busy = false; reading = false; persist() }
    func addReference() {
        guard !busy, !reading, references.count < 3 else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = AttachmentReader.contentTypes; panel.canChooseDirectories = false
        panel.message = "Read a reference locally. Its text or image is sent only when you generate a draft."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        reading = true
        task = Task {
            defer { reading = false }
            do { let item = try await ContextReader.read(url: url); try Task.checkCancellation(); references.append(item) }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
    func generate(iris: IrisOrchestrator, brief: String, format: String, tone: String, length: String, revise: Bool) {
        guard !busy, !reading, !brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let previous = content
        if !previous.isEmpty { previousVersion = previous; UserDefaults.standard.set(previous, forKey: "IrisCreationPreviousDraftV2") }
        let id = UUID(); requestID = id; busy = true; error = nil; status = "Connecting to \(iris.preferences.source.rawValue)…"
        let preferences = iris.preferences, material = references, source = content
        task = Task {
            do {
                var model = preferences.model
                if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let available = preferences.source == .local ? try await ModelService.models(server: preferences.server) : try await CloudModelService.models(source: preferences.source)
                    model = try ProviderReadiness.model(requested: model, available: available)
                }
                let instruction = CreationPolicy.instruction(format: format, tone: tone, length: length)
                let prompt = brief + (revise ? "\n\nRevise this draft and return its complete replacement:\n" + String(source.prefix(60000)) : "")
                let messages = [ChatMessage(role: "user", text: prompt)]
                var last = Date.distantPast
                let partial: @MainActor (String) -> Void = { [weak self] raw in
                    guard let self, self.requestID == id, !Task.isCancelled, Date().timeIntervalSince(last) > 0.12 else { return }
                    let visible = CreationPolicy.editableText(raw)
                    guard !visible.isEmpty else { return }
                    last = Date(); self.status = "Writing your draft…"; self.content = visible
                }
                let reply: String
                if preferences.source == .local {
                    reply = try await ModelService.answer(server: preferences.server, model: model, messages: messages, context: AttachmentPayload.text(material), role: preferences.role, skill: instruction, personality: preferences.personality, images: material.compactMap(\.image), onPartial: partial)
                } else {
                    reply = try await CloudModelService.answer(source: preferences.source, model: model, messages: messages, context: AttachmentPayload.text(material), skill: instruction, personality: preferences.personality, images: material.compactMap(\.image), onPartial: partial)
                }
                try Task.checkCancellation(); guard requestID == id else { return }
                let result = CreationPolicy.editableText(reply)
                guard !result.isEmpty else { throw IrisFailure.message("No editable draft was returned. Try a more specific brief.") }
                content = result; status = "Draft ready · saved in Library"
                iris.recordCreation(title: String(brief.prefix(80)), kind: "draft", text: result)
            } catch { if !Task.isCancelled, requestID == id { self.error = error.localizedDescription; if content.isEmpty { content = previous } } }
            guard requestID == id else { return }
            busy = false; task = nil; persist()
        }
    }
    func export(iris: IrisOrchestrator, name: String, format: String) {
        do {
            let filename = try CreationPolicy.filename(name, format: format)
            let bytes = try DocumentWriter.data(content: content, format: format)
            let panel = NSSavePanel(); panel.nameFieldStringValue = filename; panel.canCreateDirectories = true
            panel.allowedContentTypes = [UTType(filenameExtension: format) ?? .plainText]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            try bytes.write(to: url, options: .atomic)
            let bookmark = try url.bookmarkData(options: IrisLocalStorage.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            exports.insert(.init(name: url.lastPathComponent, bookmark: bookmark), at: 0); exports = Array(exports.prefix(24))
            if let data = try? JSONEncoder().encode(exports) { UserDefaults.standard.set(data, forKey: "IrisCreationExportsV2") }
            if let file = exports.first { iris.recordCreation(title: file.name, kind: "file", file: file) }
            status = "Saved \(url.lastPathComponent)"; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
