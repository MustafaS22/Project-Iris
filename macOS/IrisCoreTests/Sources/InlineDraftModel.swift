import Foundation
import AppKit

@MainActor enum InlineDraftModel {
    static func profileValue(preferences: Preferences, target: InlineDraftTarget) -> String? {
        let defaults = UserDefaults.standard
        return InlineWriting.profileValue(field: target.fieldLabel, name: preferences.name,
            email: defaults.string(forKey: "IrisInlineDraftEmail") ?? "",
            phone: defaults.string(forKey: "IrisInlineDraftPhone") ?? "",
            address: defaults.string(forKey: "IrisInlineDraftAddress") ?? "")
    }

    static func generate(preferences: Preferences, target: InlineDraftTarget, instruction: String?, nearby: String, knownContext: String = "", session: URLSession = .shared) async throws -> InlineWritingResult {
        if instruction == nil, target.selected.isEmpty,
           InlineWriting.isEmptyField(target.original ?? ""),
           let value = profileValue(preferences: preferences, target: target) {
            return .draft(value)
        }
        var model = preferences.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if model.isEmpty {
            let models = preferences.source == .local ? try await ModelService.models(server: preferences.server) : try await CloudModelService.models(source: preferences.source)
            model = try ProviderReadiness.model(requested: model, available: models)
        }
        try Task.checkCancellation()
        let selected = target.selected
        let original = target.original ?? ""
        let context: String
        let request: String
        var separator = ""
        if let instruction {
            request = instruction
            context = "Existing field text:\n" + String(original.prefix(4_000)) + "\nSelected text:\n" + String(selected.prefix(4_000))
        } else if !selected.isEmpty {
            request = "Polish the selected text for clarity and natural phrasing. Keep its language, facts, intent and approximate length."
            context = "Selected text:\n" + String(selected.prefix(4_000))
        } else if !InlineWriting.isEmptyField(original) {
            let ns = original as NSString
            let location = min(target.range.location, ns.length)
            let before = ns.substring(to: location)
            let after = ns.substring(from: location)
            if before.last.map({ !$0.isWhitespace }) == true { separator = " " }
            request = "Continue the existing draft at the caret. Return only the new words to insert. Do not repeat surrounding text."
            context = "Before caret:\n" + String(before.suffix(3_000)) + "\nAfter caret:\n" + String(after.prefix(1_000))
        } else {
            request = InlinePersonalContext.emptyFieldInstruction
            context = ""
        }
        let system = InlineWriting.instructions + "\nBe brief by default: a short reply or continuation, and concise emails. Expand only when the user asks or the task requires it. Return the required JSON immediately, without a preamble."
        let screenContext = """
        Application: \(target.app.localizedName ?? "Unknown app")
        Focused field label: \(target.fieldLabel.isEmpty ? "Not exposed by app" : target.fieldLabel)
        Field type: \(target.role)
        Explicitly saved user name: \(preferences.name.isEmpty ? "Not provided" : preferences.name)
        """
        let emptyField = InlineWriting.isEmptyField(original) && selected.isEmpty
        let fullContext = screenContext + "\n\n" + String(context.prefix(3_800)) + "\nVisible context captured at invocation:\n" + String(nearby.suffix(4000)) + (emptyField && !knownContext.isEmpty ? "\nKnown user facts (reference data; use only for this field):\n" + String(knownContext.prefix(1800)) : "")
        let messages = [ChatMessage(role: "user", text: request)]
        let reply: String
        if preferences.source == .local {
            reply = try await ModelService.answer(server: preferences.server, model: model, messages: messages, context: fullContext,
                                                  role: preferences.role, draftInstruction: system, outputLimit: 1400, session: session)
        } else {
            reply = try await CloudModelService.answer(source: preferences.source, model: model, messages: messages, context: fullContext, draftInstruction: system, outputLimit: 1400)
        }
        guard let result = InlineWriting.decode(StreamingPresentation.withoutReasoning(reply)) else {
            throw IrisFailure.message("The AI returned an incomplete or invalid draft. Try a shorter request or choose another model.")
        }
        switch result {
        case .draft(let text): return .draft(separator + text)
        case .question(let question): return .question(question)
        }
    }
}
