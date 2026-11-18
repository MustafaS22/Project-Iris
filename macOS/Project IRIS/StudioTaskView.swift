import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct StudioTaskView: View {
    @ObservedObject var iris: IrisOrchestrator
    let skill: StudioSkill
    @State private var brief = ""
    @State private var level = "Balanced"
    @State private var count = 10
    @State private var folderID = ""
    @State private var feedback = ""
    private var answer: ChatMessage? { iris.messages.last { $0.role == "assistant" } }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(skill.title).font(.system(size: 24, weight: .semibold))
                Text(skill.subtitle).font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
            }
            TextField(skill.student ? "What would you like to understand? Add a topic, question or instructions…" : "Describe the outcome, constraints or code you want help with…", text: $brief, axis: .vertical)
                .lineLimit(4...8).textFieldStyle(.plain).font(.system(size: 14)).padding(16)
                .background(iris.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 12)).disabled(iris.busy)
            HStack(alignment: .bottom, spacing: 16) {
                IrisPicker(skill.student ? "Learning depth" : "Approach", selection: $level, options: (skill.student ? ["Quick overview", "Balanced", "In depth"] : ["Smallest useful version", "Balanced", "Production review"]).map { .init(value: $0, title: $0) }).disabled(iris.busy)
                if skill == .flashcards { Stepper("\(count) cards", value: $count, in: 4...40, step: 2).font(.caption).frame(width: 115).disabled(iris.busy) }
            }
            if !skill.student && (skill == .app || skill == .website) {
                IrisPicker("Project destination · optional", selection: $folderID, footerTitle: "Grant a project folder…", footerAction: { iris.actions.grant() }, options: [.init(value: "", title: "Discuss before saving", symbol: "bubble.left")] + iris.actions.folders.map { .init(value: $0.id, title: $0.name, symbol: "folder") }).disabled(iris.busy)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(skill.student ? "Study material" : "Code & specifications").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button("Add files", systemImage: "paperclip") { iris.chooseStudioReference() }.font(.caption).disabled(iris.contextBusy || iris.studioReferences.count >= 3 || iris.busy)
                }
                if iris.studioReferences.isEmpty {
                    Label("Bring up to three references, or work from your brief.", systemImage: "doc.badge.plus").font(.caption).foregroundStyle(IrisDesign.secondary)
                }
                ForEach(iris.studioReferences) { reference in
                    DisclosureGroup {
                        ScrollView { Text(String(reference.text.prefix(12000))).font(.caption).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 150)
                        Button("Remove reference") { iris.studioReferences.removeAll { $0.id == reference.id } }.font(.caption).disabled(iris.busy)
                    } label: { Label(reference.name, systemImage: "doc.text").font(.system(size: 12)) }
                }
                if iris.contextBusy { ProgressView().controlSize(.small) }
            }
            HStack {
                if iris.busy { ProgressView().controlSize(.small); Button("Stop") { iris.cancelModel() } }
                else { Button(answer == nil ? "Start working" : "Continue with Iris", systemImage: "sparkles") { generate() }.buttonStyle(IrisActionStyle(primary: true)).disabled(brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || iris.contextBusy) }
                Spacer()
                if answer != nil { Button("New task") { iris.startStudio(skill); brief = "" } .font(.caption).disabled(iris.busy) }
            }
            Text("Uses \(iris.preferences.source.rawValue). Generate shares the brief and references with your selected model. Project execution follows your Computer permission setting.").font(.caption).foregroundStyle(IrisDesign.secondary)
            if iris.busy { LiveResponseView(iris: iris) }
            if let answer {
                Divider()
                HStack {
                    Text("Result").font(.system(size: 18, weight: .semibold)); Spacer()
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(answer.text, forType: .string); feedback = "Copied" }.font(.caption)
                    Button("Export…") { export(answer) }.font(.caption)
                }
                let artifact = StudioArtifact.parse(answer.text)
                let prose = ResponsePresentation.visibleText(answer.text).components(separatedBy: "```iris-study")[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if !prose.isEmpty { FormattedResponse(text: prose, fontSize: 14) }
                if let artifact { StudioArtifactView(iris: iris, artifact: artifact, messageID: answer.id) }
                else if answer.text.contains("```iris-study") { Label("The study format couldn't be read. Continue with Iris to request a corrected result.", systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
                ForEach(answer.files ?? []) { ChatFileCard(iris: iris, file: $0) }
            }
            if !feedback.isEmpty { Text(feedback).font(.caption).foregroundStyle(iris.accent) }
            ActionReview(iris: iris)
        }
        .onAppear { brief = UserDefaults.standard.string(forKey: "IrisStudioBrief-" + skill.rawValue) ?? "" }
        .onChange(of: brief) { _, value in UserDefaults.standard.set(value, forKey: "IrisStudioBrief-" + skill.rawValue) }
    }
    private func generate() {
        iris.draft = brief + "\n\nDepth/approach: " + level
        if skill == .flashcards { iris.draft += "\nCreate \(count) flashcards." }
        if let folder = iris.actions.folders.first(where: { $0.id == folderID }) { iris.draft += "\nUse approved destination \(folder.name) (identifier \(folder.id)) for project files, in a clearly named project subfolder." }
        iris.ask()
    }
    private func export(_ message: ChatMessage) {
        let artifact = StudioArtifact.parse(message.text)
        let panel = NSSavePanel(); panel.canCreateDirectories = true
        panel.nameFieldStringValue = skill.rawValue + (artifact == nil ? ".md" : ".json")
        panel.allowedContentTypes = [artifact == nil ? .plainText : .json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if let artifact { let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; try encoder.encode(artifact).write(to: url, options: .atomic) }
            else { try ResponsePresentation.visibleText(message.text).write(to: url, atomically: true, encoding: .utf8) }
            let bookmark = try url.bookmarkData(options: IrisLocalStorage.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            iris.recordCreation(title: url.lastPathComponent, kind: "file", file: .init(name: url.lastPathComponent, bookmark: bookmark))
            feedback = "Exported \(url.lastPathComponent)"
        } catch { feedback = error.localizedDescription }
    }
}

struct StudioArtifactView: View {
    @ObservedObject var iris: IrisOrchestrator
    var artifact: StudioArtifact
    var messageID: UUID
    @State private var saved = Set<UUID>()
    @State private var cardIndex = 0
    @State private var revealed = false
    var body: some View {
        if artifact.kind == "flashcards", let cards = artifact.cards {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Label("\(cards.count) flashcards", systemImage: "rectangle.stack").font(.headline); Spacer(); Button(saved.contains(messageID) ? "Saved to deck" : "Save to my deck") { iris.data.studyCards = (iris.data.studyCards ?? []) + cards.map { StudyCard(question: $0.question, answer: $0.answer) }; iris.save(); saved.insert(messageID); UserDefaults.standard.set(true, forKey: "IrisSavedStudy-" + messageID.uuidString) }.disabled(saved.contains(messageID)) }
                let index = min(cardIndex, cards.count - 1)
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Text("Card \(index + 1) of \(cards.count)").font(.caption).foregroundStyle(IrisDesign.secondary); Spacer(); Text(revealed ? "Answer" : "Question").font(.caption).foregroundStyle(iris.accent) }
                    FormattedResponse(text: revealed ? cards[index].answer : cards[index].question, fontSize: 18).frame(minHeight: 80)
                    HStack {
                        Button(revealed ? "Show question" : "Reveal answer") { revealed.toggle() }.buttonStyle(IrisActionStyle(primary: true))
                        Spacer()
                        Button { cardIndex = (index - 1 + cards.count) % cards.count; revealed = false } label: { Image(systemName: "arrow.left").irisSymbolStyle() }.help("Previous card")
                        Button { cardIndex = (index + 1) % cards.count; revealed = false } label: { Image(systemName: "arrow.right").irisSymbolStyle() }.help("Next card")
                    }
                }.padding(20).background(iris.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                .onAppear { if UserDefaults.standard.bool(forKey: "IrisSavedStudy-" + messageID.uuidString) { saved.insert(messageID) } }
            }
        } else if artifact.kind == "mindmap", let branches = artifact.branches {
            VStack(spacing: 0) {
                Text(artifact.root ?? "Topic").font(.system(size: 21, weight: .semibold)).padding(18).background(iris.accent.opacity(0.16), in: RoundedRectangle(cornerRadius: 12))
                Rectangle().fill(iris.accent.opacity(0.5)).frame(width: 1, height: 24)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .top)], alignment: .leading, spacing: 20) {
                    ForEach(Array(branches.enumerated()), id: \.offset) { _, branch in
                        VStack(alignment: .leading, spacing: 10) {
                            Label(branch.title, systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.system(size: 15, weight: .semibold)).foregroundStyle(iris.accent)
                            ForEach(Array(branch.details.enumerated()), id: \.offset) { _, detail in Text(detail).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading) }
                        }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading).background(LinearGradient(colors: [iris.accent.opacity(0.09), IrisDesign.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }.textSelection(.enabled)
        }
    }
}
