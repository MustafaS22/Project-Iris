import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StudyWorkbench: View {
    @ObservedObject var iris: IrisOrchestrator
    @AppStorage("IrisStudyCardDraft") private var input = ""
    @State private var selectedID: UUID?
    @State private var revealed = false
    @State private var practiced = Set<UUID>()
    @State private var status = ""
    private var cards: [StudyCard] { iris.data.studyCards ?? [] }
    private var selected: StudyCard? { cards.first { $0.id == selectedID } ?? cards.first }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            DisclosureGroup("Add your own flashcards") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Add one question and answer per line, separated by |. Everything stays on this Mac.").font(.caption).foregroundStyle(IrisDesign.secondary)
                    TextEditor(text: $input).font(.system(size: 14)).frame(height: 100).scrollContentBackground(.hidden).padding(10).background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10)).accessibilityLabel("Questions and answers")
                    HStack {
                        Text("Example: What is a closure? | A function that captures its surrounding values.").font(.caption).foregroundStyle(IrisDesign.secondary)
                        Spacer()
                        Button("Add cards") {
                            let added = StudioTools.cards(from: input)
                            if added.isEmpty { status = "Use question | answer for each card."; return }
                            iris.data.studyCards = cards + added; iris.save(); input = ""; status = "Added \(added.count) cards."; selectedID = added.first?.id; revealed = false
                        }.buttonStyle(IrisActionStyle(primary: true)).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if !status.isEmpty { Text(status).font(.caption).foregroundStyle(iris.accent) }
                }
            }
            HStack { Text("Practice deck").font(.system(size: 24, weight: .semibold)); Spacer(); if !practiced.isEmpty { Button("Reset practice") { practiced = []; revealed = false; selectedID = nil }.font(.caption) } }
            if let card = selected {
                VStack(alignment: .leading, spacing: 18) {
                    HStack { Label("Practice", systemImage: "rectangle.on.rectangle").font(.headline); Spacer(); Text("\(practiced.count) / \(cards.count) practiced").font(.caption).foregroundStyle(IrisDesign.secondary) }
                    FormattedResponse(text: card.question, fontSize: 20).frame(minHeight: 70)
                    if revealed { Divider(); FormattedResponse(text: card.answer, fontSize: 16) }
                    HStack {
                        Button(revealed ? "Hide answer" : "Show answer") { revealed.toggle() }.buttonStyle(IrisActionStyle(primary: true))
                        Button("Got it · next") { practiced.insert(card.id); let index = cards.firstIndex { $0.id == card.id } ?? 0; selectedID = cards[(index + 1) % cards.count].id; revealed = false }
                        Button("Review again") { let index = cards.firstIndex { $0.id == card.id } ?? 0; selectedID = cards[(index + 1) % cards.count].id; revealed = false }
                        Spacer()
                        Button("Remove card", role: .destructive) { iris.data.studyCards = cards.filter { $0.id != card.id }; practiced.remove(card.id); selectedID = nil; revealed = false; iris.save() }
                    }
                }.padding(24).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 16))
            } else { ContentUnavailableView("Build your first practice deck", systemImage: "rectangle.stack", description: Text("Add a few questions above, then reveal answers at your own pace.")) }
        }
    }
}

struct DeveloperWorkbench: View {
    @ObservedObject var iris: IrisOrchestrator
    @AppStorage("IrisDeveloperScratchpad") private var text = ""
    @State private var status = ""
    @State private var failed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Scratchpad", systemImage: "curlybraces").font(.headline)
                Spacer()
                Text("\(text.split(separator: "\n", omittingEmptySubsequences: false).count) lines · \(text.utf8.count) bytes").font(.caption).foregroundStyle(IrisDesign.secondary)
            }
            Text("Draft code or inspect JSON locally. This editor does not execute code or send it to a model.").font(.caption).foregroundStyle(IrisDesign.secondary)
            TextEditor(text: $text).font(.system(size: 13, design: .monospaced)).frame(minHeight: 260).scrollContentBackground(.hidden).padding(14).background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Code and JSON scratchpad")
            HStack(spacing: 12) {
                Button("Validate JSON") { format(apply: false) }
                Button("Format JSON") { format(apply: true) }
                Spacer()
                Button("Export…", systemImage: "square.and.arrow.up") { export() }.buttonStyle(IrisActionStyle(primary: true))
            }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            if !status.isEmpty { Label(status, systemImage: failed ? "exclamationmark.circle" : "checkmark.circle").font(.caption).foregroundStyle(failed ? .orange : iris.accent).textSelection(.enabled) }
            Text("Draft saved automatically on this Mac.").font(.caption).foregroundStyle(IrisDesign.secondary)
        }
    }
    private func format(apply: Bool) {
        do { let formatted = try StudioTools.formatJSON(text); if apply { text = formatted }; failed = false; status = apply ? "JSON formatted." : "Valid JSON." }
        catch { failed = true; status = "Invalid JSON: \(error.localizedDescription)" }
    }
    private func export() {
        let panel = NSSavePanel(); panel.title = "Export scratchpad"; panel.nameFieldStringValue = "scratchpad.txt"; panel.allowedContentTypes = [.plainText]; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try text.write(to: url, atomically: true, encoding: .utf8); failed = false; status = "Saved \(url.lastPathComponent)." }
        catch { failed = true; status = error.localizedDescription }
    }
}
