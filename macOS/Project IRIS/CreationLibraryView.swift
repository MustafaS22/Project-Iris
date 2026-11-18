import SwiftUI
import AppKit

extension IrisOrchestrator {
    func recordCreation(title: String, kind: String, text: String? = nil, file: ChatFileReference? = nil) {
        var items = data.createdItems ?? []
        if let file, items.contains(where: { $0.file?.id == file.id }) { return }
        items.insert(.init(title: title, kind: kind, text: text, file: file), at: 0)
        data.createdItems = items; save()
    }
    /// Backfills files already stored by earlier versions. No folder scan or additional file access.
    func collectExistingCreations() {
        var items = data.createdItems ?? []
        var ids = Set(items.compactMap { $0.file?.id })
        let conversations = data.conversations ?? []
        let files = conversations.flatMap { $0.messages.filter { $0.role == "assistant" }.flatMap { $0.files ?? [] } }
        let exports = UserDefaults.standard.data(forKey: "IrisCreationExportsV2").flatMap { try? JSONDecoder().decode([ChatFileReference].self, from: $0) } ?? []
        for file in files + exports where ids.insert(file.id).inserted { items.append(.init(title: file.name, kind: "file", file: file)) }
        let draft = UserDefaults.standard.string(forKey: "IrisCreationDraftV2") ?? ""
        if !draft.isEmpty, !items.contains(where: { $0.text == draft }) { items.append(.init(title: "Saved draft", kind: "draft", text: draft)) }
        let scratchpad = UserDefaults.standard.string(forKey: "IrisDeveloperScratchpad") ?? ""
        if !scratchpad.isEmpty, !items.contains(where: { $0.text == scratchpad }) { items.append(.init(title: "Saved code note", kind: "draft", text: scratchpad)) }
        if items.count != (data.createdItems ?? []).count { data.createdItems = items; save() }
    }
}

struct CreationLibraryView: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var query = ""
    @State private var filter = "Files"
    @State private var selected: CreatedItem?
    @State private var output: NotebookOutput?
    private func matches(_ text: String) -> Bool { query.isEmpty || text.localizedCaseInsensitiveContains(query) }
    private var notebooks: [StudyNotebook] { (iris.data.notebooks ?? []).filter { matches($0.displayTitle) }.sorted { $0.updatedAt > $1.updatedAt } }
    private var projects: [ChatConversation] { (iris.data.conversations ?? []).filter { $0.skillID != nil && matches($0.title) }.sorted { $0.updatedAt > $1.updatedAt } }
    private var files: [CreatedItem] { (iris.data.createdItems ?? []).filter { $0.file != nil && matches($0.title) }.sorted { $0.createdAt > $1.createdAt } }
    private var drafts: [CreatedItem] { (iris.data.createdItems ?? []).filter { $0.file == nil && matches($0.title) }.sorted { $0.createdAt > $1.createdAt } }
    private var outputs: [NotebookOutput] { (iris.data.notebooks ?? []).flatMap(\.outputs).filter { matches($0.title) || matches($0.text) }.sorted { $0.createdAt > $1.createdAt } }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                VStack(alignment: .leading, spacing: 8) { Text("Library").font(.system(size: 34, weight: .semibold)); Text("Files, study material and projects — each in its own place.").font(.callout).foregroundStyle(IrisDesign.secondary) }
                Spacer()
                Button("New in chat", systemImage: "plus") { iris.newConversation(); iris.draft = "@" }.buttonStyle(IrisActionStyle(primary: true))
            }
            TextField("Search your library", text: $query).textFieldStyle(IrisTextFieldStyle())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                category("Files", "folder.fill", count: files.count)
                category("Study", "books.vertical.fill", count: notebooks.count + outputs.count)
                category("Projects", "square.stack.3d.up.fill", count: projects.count)
                category("Drafts", "doc.text.fill", count: drafts.count)
            }
            if filter == "Study" {
                HStack {
                    Text("Study spaces and saved learning material").font(.callout).foregroundStyle(IrisDesign.secondary)
                    Spacer()
                    Button("Open study workspace", systemImage: "arrow.up.right") { iris.workspaceSection = .tools }.buttonStyle(IrisActionStyle())
                }
            }
            if show("Study Spaces") && !notebooks.isEmpty {
                heading("Study Spaces", "rectangle.3.group")
                ForEach(notebooks) { book in
                    libraryRow(book.displayTitle, "\(book.sources.count) sources · \(book.outputs.count) outputs", "rectangle.3.group", date: book.updatedAt) { iris.selectedNotebookID = book.id; UserDefaults.standard.set("Student", forKey: "IrisStudioModeV2"); iris.workspaceSection = .tools }
                }
            }
            if show("Projects") && !projects.isEmpty {
                heading("Projects & tasks", "square.stack.3d.up")
                ForEach(projects) { project in libraryRow(project.title, project.skillID.flatMap(StudioSkill.init(rawValue:))?.title ?? "Studio task", project.skillID.flatMap(StudioSkill.init(rawValue:))?.symbol ?? "doc.text", date: project.updatedAt) { iris.openConversation(project) } }
            }
            if show("Study outputs") && !outputs.isEmpty {
                heading("Study outputs", "rectangle.stack")
                ForEach(outputs) { item in libraryRow(item.title, NotebookSession.title(item.kind), "doc.richtext", date: item.createdAt) { output = item } }
            }
            if show("Files") && !files.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(files) { item in if let file = item.file { ChatFileCard(iris: iris, file: file) } }
                }
            }
            if show("Drafts") && !drafts.isEmpty {
                heading("Drafts", "doc.text")
                ForEach(drafts) { item in libraryRow(item.title, String((item.text ?? "").prefix(100)), "doc.text", date: item.createdAt) { selected = item } }
            }
            if empty { ContentUnavailableView(query.isEmpty ? "No \(filter.lowercased()) yet" : "Nothing matches here", systemImage: "square.stack.3d.up", description: Text(query.isEmpty ? "Saved work appears in its matching category. Create something in chat, or choose another category above." : "Try another title or library category.")) }
        }.onAppear { iris.collectExistingCreations() }
        .sheet(item: $output) { item in NotebookOutputView(iris: iris, output: item) { output = nil } }
        .sheet(item: $selected) { item in
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text(item.title).font(.title2); Spacer(); Button("Done") { selected = nil } }
                ScrollView { FormattedResponse(text: item.text ?? "", fontSize: 15) }
                HStack {
                    Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.text ?? "", forType: .string) }
                    Button("Edit draft") { let current = UserDefaults.standard.string(forKey: "IrisCreationDraftV2") ?? ""; if !current.isEmpty { UserDefaults.standard.set(current, forKey: "IrisCreationPreviousDraftV2") }; UserDefaults.standard.set(item.text ?? "", forKey: "IrisCreationDraftV2"); UserDefaults.standard.set(item.title, forKey: "IrisCreateBriefV2"); UserDefaults.standard.set("Document", forKey: "IrisCreateKindV2"); selected = nil; iris.workspaceSection = .create }.buttonStyle(IrisActionStyle(primary: true))
                }
            }.padding(28).frame(width: 720, height: 580).preferredColorScheme(.dark)
        }
    }
    private func show(_ category: String) -> Bool { filter == category || (filter == "Study" && ["Study Spaces", "Study outputs"].contains(category)) }
    private var empty: Bool { (!show("Study Spaces") || notebooks.isEmpty) && (!show("Projects") || projects.isEmpty) && (!show("Study outputs") || outputs.isEmpty) && (!show("Files") || files.isEmpty) && (!show("Drafts") || drafts.isEmpty) }
    private func category(_ title: String, _ symbol: String, count: Int) -> some View {
        Button { filter = title } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: symbol).irisSymbolStyle().foregroundStyle(iris.accent)
                    Spacer()
                    Text("\(count)").font(.system(size: 12, weight: .medium)).foregroundStyle(IrisDesign.secondary).monospacedDigit()
                }
                Text(title).font(.system(size: 14, weight: .semibold))
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(filter == title ? iris.accent.opacity(0.12) : IrisDesign.surface, in: RoundedRectangle(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(filter == title ? iris.accent.opacity(0.4) : Color.white.opacity(0.06)) }
        }.buttonStyle(.plain).accessibilityLabel("\(title), \(count) items").accessibilityAddTraits(filter == title ? .isSelected : [])
    }
    private func heading(_ title: String, _ symbol: String) -> some View { Label(title, systemImage: symbol).font(.system(size: 20, weight: .semibold)).padding(.top, 8) }
    private func libraryRow(_ title: String, _ detail: String, _ symbol: String, date: Date, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: symbol).irisSymbolStyle().font(.system(size: 25, weight: .semibold)).foregroundStyle(iris.accent).frame(width: 44, height: 50)
                VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(2); Text(detail).font(.caption).foregroundStyle(IrisDesign.secondary).lineLimit(2) }
                Spacer(); Text(date, style: .date).font(.caption).foregroundStyle(IrisDesign.secondary); Image(systemName: "chevron.right").irisSymbolStyle().font(.caption)
            }.padding(.vertical, 10).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}
