import SwiftUI
import AppKit

struct StudentNotebooksView: View {
    @ObservedObject var iris: IrisOrchestrator
    @ObservedObject var session: NotebookSession
    @State private var query = ""
    @State private var deleting: StudyNotebook?
    var body: some View {
        if let id = iris.selectedNotebookID, iris.data.notebooks?.contains(where: { $0.id == id }) == true {
            NotebookWorkspaceView(iris: iris, session: session, id: id)
        } else {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Study Spaces").font(.system(size: 26, weight: .semibold))
                        Text("A home for your reading, questions and breakthroughs.").foregroundStyle(IrisDesign.secondary)
                    }
                    Spacer()
                    Button("New space", systemImage: "plus") {
                        let book = StudyNotebook(title: "Untitled study space")
                        iris.data.notebooks = (iris.data.notebooks ?? []) + [book]; iris.selectedNotebookID = book.id; iris.save()
                    }.buttonStyle(IrisActionStyle(primary: true))
                }
                TextField("Find a study space", text: $query).textFieldStyle(IrisTextFieldStyle())
                let books = (iris.data.notebooks ?? []).filter { query.isEmpty || $0.displayTitle.localizedCaseInsensitiveContains(query) }.sorted { $0.updatedAt > $1.updatedAt }
                if books.isEmpty {
                    ContentUnavailableView(query.isEmpty ? "Bring a topic to life" : "No matching spaces", systemImage: "books.vertical", description: Text(query.isEmpty ? "Start a space for a topic. Bring your material, talk it through with Iris, then make something worth keeping." : "Try another space title."))
                }
                VStack(spacing: 0) {
                    ForEach(books) { book in
                        HStack(spacing: 20) {
                            Button { iris.selectedNotebookID = book.id } label: {
                                HStack(spacing: 20) {
                                    Image(systemName: "rectangle.3.group").irisSymbolStyle().font(.system(size: 28, weight: .semibold)).foregroundStyle(iris.accent).frame(width: 52, height: 64)
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(book.displayTitle).font(.system(size: 20, weight: .semibold)).lineLimit(2)
                                        Text(book.sources.isEmpty ? "Ready for your first piece of reading" : book.sources.prefix(2).map(\.name).joined(separator: " · ")).font(.system(size: 12)).foregroundStyle(IrisDesign.secondary).lineLimit(1)
                                        Text("\(book.outputs.count) saved pieces · \(book.updatedAt.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(IrisDesign.secondary)
                                    }
                                    Spacer(); Image(systemName: "arrow.up.right").irisSymbolStyle().foregroundStyle(iris.accent)
                                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            Button { deleting = book } label: { Image(systemName: "trash").irisSymbolStyle().frame(width: 28, height: 28) }.buttonStyle(.plain).foregroundStyle(IrisDesign.secondary).help("Delete space").accessibilityLabel("Delete \(book.displayTitle)").disabled(session.busy || session.reading)
                        }.padding(.vertical, 22)
                        Divider()
                    }
                }
            }
            .alert("Delete this study space?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("Cancel", role: .cancel) { deleting = nil }
                Button("Delete space", role: .destructive) { iris.data.notebooks?.removeAll { $0.id == deleting?.id }; iris.save(); deleting = nil }
            } message: { Text("Removes this space’s reading, saved work and conversation. Original files remain unchanged.") }
        }
    }
}

struct NotebookWorkspaceView: View {
    @ObservedObject var iris: IrisOrchestrator
    @ObservedObject var session: NotebookSession
    let id: UUID
    @State private var section = "Explore"
    @State private var shelfExpanded = false
    @State private var question = ""
    @State private var preview: NotebookEvidence?
    @State private var selectedOutput: UUID?
    @State private var addText = false
    @State private var sourceName = ""
    @State private var sourceText = ""
    private var book: StudyNotebook { iris.data.notebooks?.first { $0.id == id } ?? .init(title: "Study space") }
    private var locked: Bool { session.busy || session.reading }
    private var active: Bool { session.activeNotebookID == id }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top, spacing: 18) {
                Button { iris.selectedNotebookID = nil } label: { Image(systemName: "arrow.left").irisSymbolStyle().frame(width: 32, height: 32) }.buttonStyle(.plain).help("All study spaces")
                IrisAvatar(state: session.reading && active ? .vision : session.busy && active ? .thinking : .idle, color: iris.accent, size: 42, animated: true, desktop: true)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Space title", text: Binding(get: { book.displayTitle }, set: { value in mutate { $0.title = String(value.prefix(100)) } })).textFieldStyle(.plain).font(.system(size: 25, weight: .semibold)).disabled(locked)
                    Text("\(book.sources.filter(\.enabled).count) selected sources · saved on this Mac").font(.caption).foregroundStyle(IrisDesign.secondary)
                }
                Spacer()
                if locked { Button("Stop") { session.stop() }.buttonStyle(IrisActionStyle()) }
            }
            if let error = session.error { Label(error, systemImage: "exclamationmark.circle").font(.callout).foregroundStyle(.orange).textSelection(.enabled) }
            if session.busy && active { HStack(spacing: 10) { ProgressView().controlSize(.small); Text(session.phase).font(.caption).foregroundStyle(iris.accent) } }
            DisclosureGroup(isExpanded: $shelfExpanded) {
                sources.padding(.top, 18)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "tray.full").irisSymbolStyle().foregroundStyle(iris.accent)
                    Text("Reading shelf").font(.system(size: 14, weight: .semibold))
                    Text("\(book.sources.filter(\.enabled).count) selected").font(.caption).foregroundStyle(IrisDesign.secondary)
                    Spacer()
                }.padding(.vertical, 8)
            }.padding(16).background(IrisDesign.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))
            IrisTabBar(items: ["Explore", "Study kit", "Saved work"], selection: $section)
            if section == "Study kit" { study }
            else if section == "Saved work" { savedWork }
            else { chat }

        }
        .frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: book.outputs.count) { old, new in if new > old, let latest = book.outputs.first, latest.kind != "note" { selectedOutput = latest.id; section = "Saved work" } }
        .onAppear { shelfExpanded = book.sources.isEmpty }
        .sheet(isPresented: Binding(get: { selectedOutput != nil }, set: { if !$0 { selectedOutput = nil } })) {
            if let output = book.outputs.first(where: { $0.id == selectedOutput }) { NotebookOutputView(iris: iris, output: output) { selectedOutput = nil } }
        }
        .onChange(of: book.turns.count) { _, _ in if book.turns.last?.role == "assistant" { question = "" } }
        .sheet(item: $preview) { evidence in
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text(evidence.name).font(.title2); Spacer(); Button("Done") { preview = nil } }
                Text("Source excerpt · \(evidence.id)").font(.caption).foregroundStyle(IrisDesign.secondary)
                ScrollView { Text(evidence.excerpt).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            }.padding(28).frame(width: 620, height: 520).preferredColorScheme(.dark)
        }
        .sheet(isPresented: $addText) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Add source text").font(.title2)
                IrisFormField(title: "Source name", prompt: "Lecture notes, chapter or article", text: $sourceName)
                Text("Paste your material").font(.callout)
                TextEditor(text: $sourceText).font(.system(size: 14)).scrollContentBackground(.hidden).padding(12).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 12))
                Text("Up to 18,000 characters per source. Stored locally; selected excerpts are shared when you ask Iris.").font(.caption).foregroundStyle(IrisDesign.secondary)
                HStack { Button("Cancel") { addText = false }; Spacer(); Button("Add source") { mutate { $0.sources.append(.init(name: String(sourceName.prefix(150)), text: String(sourceText.prefix(18000)))) }; sourceText = ""; sourceName = ""; addText = false }.buttonStyle(IrisActionStyle(primary: true)).disabled(sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || book.sources.count >= 12 || locked) }
            }.padding(28).frame(width: 620, height: 520).preferredColorScheme(.dark)
        }
    }
    private var sources: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button("Add files", systemImage: "doc.badge.plus") { session.addFiles(iris: iris, id: id) }.buttonStyle(IrisActionStyle(primary: true)).disabled(locked || book.sources.count >= 12)
            Button("Paste text", systemImage: "doc.on.clipboard") { addText = true }.buttonStyle(.plain).foregroundStyle(iris.accent).disabled(locked || book.sources.count >= 12)
            if book.sources.isEmpty { Text("Add PDFs, Word documents or text. Select the sources Iris should use.").font(.callout).foregroundStyle(IrisDesign.secondary) }
            ForEach(book.sources) { source in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(get: { source.enabled }, set: { value in mutate { notebook in if let index = notebook.sources.firstIndex(where: { $0.id == source.id }) { notebook.sources[index].enabled = value } } })) { Text(source.name).font(.system(size: 13)).lineLimit(2) }.toggleStyle(.checkbox).disabled(locked)
                    HStack {
                        Button("Read") { preview = .init(id: "Local", sourceID: source.id, name: source.name, excerpt: source.text) }
                        Spacer()
                        Button { mutate { $0.sources.removeAll { $0.id == source.id } } } label: { Image(systemName: "minus.circle").irisSymbolStyle() }.help("Remove source from future questions").accessibilityLabel("Remove \(source.name)").disabled(locked)
                    }.font(.caption).buttonStyle(.plain).foregroundStyle(IrisDesign.secondary)
                    Divider()
                }
            }
            if session.reading && active { ProgressView("Reading files…").font(.caption) }
            Text("Each request uses up to 48,000 characters from selected sources, at most 8,000 per source. Check citations against the excerpts.").font(.caption).foregroundStyle(IrisDesign.secondary)
        }
    }
    private var chat: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text("Think it through with Iris").font(.system(size: 19, weight: .semibold)); Spacer() }
            if book.turns.isEmpty {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "text.bubble").irisSymbolStyle().font(.system(size: 36, weight: .semibold)).foregroundStyle(iris.accent)
                    Text("Let’s make it click.").font(.system(size: 22, weight: .medium))
                    Text("Bring a question, a half-formed idea, or the bit that isn’t clicking. Iris works from your selected reading and links back to the evidence.").font(.callout).foregroundStyle(IrisDesign.secondary)
                    Button("Explain the big picture") { question = "What are the main ideas in these sources?" }.buttonStyle(.plain).foregroundStyle(iris.accent)
                }.padding(.vertical, 22)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        ForEach(book.turns) { turn in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(turn.role == "user" ? "You" : "Iris").font(.caption.weight(.semibold)).foregroundStyle(iris.accent)
                                FormattedResponse(text: turn.text, fontSize: 14)
                                if turn.role == "assistant" {
                                    citations(turn.text, turn.evidence)
                                    Button("Save as note", systemImage: "bookmark") { mutate { $0.outputs.insert(.init(title: String(turn.text.prefix(55)), kind: "note", text: turn.text, evidence: turn.evidence), at: 0) } }.font(.caption).buttonStyle(.plain).foregroundStyle(IrisDesign.secondary)
                                }
                            }
                        }
                        if session.busy && active { VStack(alignment: .leading, spacing: 12) { Label(session.phase, systemImage: "sparkles").font(.caption).foregroundStyle(iris.accent); if !session.partial.isEmpty { FormattedResponse(text: prose(session.partial), fontSize: 14) } } }
                        Color.clear.frame(height: 1).id("bottom")
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 8)
                }.frame(minHeight: 180, maxHeight: 430)
                .onAppear { shelfExpanded = book.sources.isEmpty }
        .sheet(isPresented: Binding(get: { selectedOutput != nil }, set: { if !$0 { selectedOutput = nil } })) {
            if let output = book.outputs.first(where: { $0.id == selectedOutput }) { NotebookOutputView(iris: iris, output: output) { selectedOutput = nil } }
        }
        .onChange(of: book.turns.count) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            TextField("Ask about your selected sources…", text: $question, axis: .vertical).lineLimit(2...5).textFieldStyle(IrisTextFieldStyle()).disabled(locked)
            HStack { Text("Shared with \(iris.preferences.source.rawValue) when you send").font(.caption).foregroundStyle(IrisDesign.secondary); Spacer(); Button("Ask Iris", systemImage: "arrow.up") { session.generate(iris: iris, id: id, question: question) }.buttonStyle(IrisActionStyle(primary: true)).disabled(locked || question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || NotebookPolicy.evidence(book.sources).isEmpty) }
        }
    }
    private var study: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Make it stick.").font(.system(size: 26, weight: .semibold))
            Text("Turn your selected reading into a different way to understand it. Everything you make stays in this space.").font(.callout).foregroundStyle(IrisDesign.secondary)
            if session.busy && active && !prose(session.partial).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { FormattedResponse(text: prose(session.partial), fontSize: 14).padding(.vertical, 12) }
            ForEach(["summary", "guide", "mindmap", "flashcards", "quiz"], id: \.self) { kind in
                Button {
                    selectedOutput = nil
                    session.generate(iris: iris, id: id, question: "Create a \(NotebookSession.title(kind).lowercased()) from the selected sources. Focus on the key concepts and cite the evidence.", kind: kind)
                } label: {
                    HStack(spacing: 18) {
                        Image(systemName: symbol(kind)).irisSymbolStyle().font(.system(size: 23, weight: .semibold)).foregroundStyle(iris.accent).frame(width: 40)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(NotebookSession.title(kind)).font(.system(size: 16, weight: .semibold))
                            Text(toolDetail(kind)).font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                        }
                        Spacer(); Image(systemName: "arrow.up.right").irisSymbolStyle().foregroundStyle(iris.accent)
                    }.padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(locked || NotebookPolicy.evidence(book.sources).isEmpty)
                Divider()
            }
            if NotebookPolicy.evidence(book.sources).isEmpty { Label("Add and select reading on your shelf to get started.", systemImage: "tray").font(.caption).foregroundStyle(IrisDesign.secondary) }
        }
    }
    private var savedWork: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text("Worth keeping.").font(.system(size: 26, weight: .semibold)); Spacer(); Text("\(book.outputs.count) pieces").font(.caption).foregroundStyle(IrisDesign.secondary) }
            if book.outputs.isEmpty { ContentUnavailableView("Your ideas will collect here", systemImage: "bookmark", description: Text("Save an answer from Explore or create something in Study kit. It also appears in your Library.")) }
            ForEach(book.outputs) { output in
                Button { selectedOutput = output.id } label: {
                    HStack(spacing: 16) {
                        Image(systemName: symbol(output.kind)).irisSymbolStyle().font(.system(size: 23, weight: .semibold)).foregroundStyle(iris.accent).frame(width: 40)
                        VStack(alignment: .leading, spacing: 6) { Text(output.title).font(.system(size: 16, weight: .medium)).lineLimit(2); Text(output.createdAt, style: .date).font(.caption).foregroundStyle(IrisDesign.secondary) }
                        Spacer(); Image(systemName: "chevron.right").irisSymbolStyle().font(.caption)
                    }.padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Divider()
            }
        }
    }
    private func toolDetail(_ kind: String) -> String {
        ["summary":"Find the thread running through your material.", "guide":"Give a difficult topic a clear route through.", "mindmap":"See how the ideas connect.", "flashcards":"Practice pulling the answer from memory.", "quiz":"Put your understanding to the test."][kind] ?? "Work with your reading."
    }
    private func citations(_ text: String, _ evidence: [NotebookEvidence]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { citationButtons(text, evidence) }
            VStack(alignment: .leading) { citationButtons(text, evidence) }
        }
    }
    @ViewBuilder private func citationButtons(_ text: String, _ evidence: [NotebookEvidence]) -> some View {
        ForEach(NotebookPolicy.citedEvidence(in: text, evidence: evidence)) { item in
            Button("[\(item.id)] \(item.name)") { preview = item }.font(.caption).buttonStyle(.plain).foregroundStyle(iris.accent).lineLimit(1)
        }
    }
    private func mutate(_ update: (inout StudyNotebook) -> Void) { guard let index = iris.data.notebooks?.firstIndex(where: { $0.id == id }) else { return }; update(&iris.data.notebooks![index]); iris.data.notebooks?[index].updatedAt = Date(); iris.save() }
    private func prose(_ text: String) -> String { text.components(separatedBy: "```iris-study")[0].components(separatedBy: "```iris-quiz")[0] }
    private func symbol(_ kind: String) -> String { ["summary":"text.alignleft", "guide":"book", "flashcards":"rectangle.stack", "mindmap":"point.3.connected.trianglepath.dotted", "quiz":"checklist", "note":"bookmark"][kind] ?? "doc.text" }
}

struct NotebookOutputView: View {
    @ObservedObject var iris: IrisOrchestrator
    let output: NotebookOutput
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { Text(output.title).font(.title2); Spacer(); Button("Export…") { export() }; Button("Done", action: close) }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    let prose = output.text.components(separatedBy: "```iris-study")[0].components(separatedBy: "```iris-quiz")[0]
                    if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { FormattedResponse(text: prose, fontSize: 15) }
                    if let artifact = StudioArtifact.parse(output.text) { StudioArtifactView(iris: iris, artifact: artifact, messageID: output.id) }
                    else if let quiz = NotebookPolicy.quiz(output.text) { NotebookQuizView(quiz: quiz, accent: iris.accent) }
                    else if output.text.contains("```iris-") { Text("This study output couldn't be read. Generate it again.").foregroundStyle(.orange) }
                    ForEach(NotebookPolicy.citedEvidence(in: output.text, evidence: output.evidence)) { item in
                        DisclosureGroup("[\(item.id)] \(item.name)") { Text(item.excerpt).font(.caption).textSelection(.enabled).padding(.top, 8) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(28).frame(width: 740, height: 620).background(IrisBackdrop(accent: iris.accent)).preferredColorScheme(.dark)
    }
    private func export() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = output.kind + ".md"; panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try output.text.write(to: url, atomically: true, encoding: .utf8)
            let bookmark = try url.bookmarkData(options: IrisLocalStorage.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            iris.recordCreation(title: url.lastPathComponent, kind: "file", file: .init(name: url.lastPathComponent, bookmark: bookmark))
        } catch { iris.error = error.localizedDescription }
    }
}
struct NotebookQuizView: View {
    let quiz: NotebookQuiz
    let accent: Color
    @State private var selections: [Int: Int] = [:]
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            ForEach(Array(quiz.questions.enumerated()), id: \.offset) { index, question in
                VStack(alignment: .leading, spacing: 12) {
                    FormattedResponse(text: question.question, fontSize: 17)
                    ForEach(Array(question.options.enumerated()), id: \.offset) { choice, text in
                        Button { selections[index] = choice } label: { HStack { Image(systemName: selections[index] == choice ? "largecircle.fill.circle" : "circle").irisSymbolStyle(); Text(text); Spacer() }.font(.system(size: 14)).foregroundStyle(selections[index] == choice ? accent : IrisDesign.text).padding(12).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 10)) }.buttonStyle(.plain)
                    }
                    if let selected = selections[index] { Label(selected == question.answer ? "Correct" : "Try again", systemImage: selected == question.answer ? "checkmark.circle" : "arrow.clockwise").foregroundStyle(selected == question.answer ? .green : .orange); FormattedResponse(text: question.explanation, fontSize: 14) }
                }
                Divider()
            }
        }
    }
}
