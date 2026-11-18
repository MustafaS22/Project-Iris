import SwiftUI
import AppKit

/// Search saved material and manage its connections without leaving Knowledge.
struct KnowledgeLibraryView: View {
    @ObservedObject var iris: IrisOrchestrator
    @ObservedObject private var store: KnowledgeStore
    @State private var section = "Library"
    @State private var query = ""
    @State private var source: KnowledgeConnector?
    @State private var selected: LibraryItem?
    @State private var composing = false
    @State private var noteToDelete: QuickNote?
    @State private var reviewingMemories = false
    @Environment(\.irisReduceMotion) private var reduceMotion

    init(iris: IrisOrchestrator) { self.iris = iris; self._store = ObservedObject(wrappedValue: iris.knowledge) }

    private struct LibraryItem: Identifiable {
        let id: String
        let title: String
        let text: String
        let source: KnowledgeConnector?
        let date: Date?
        let note: QuickNote?
        let attachmentID: UUID?
    }
    private var items: [LibraryItem] {
        switch section {
        case "Notes": return iris.data.notes.map { .init(id: $0.id.uuidString, title: String($0.text.split(separator: "\n").first.map(String.init)?.prefix(100) ?? "Note"), text: $0.text, source: nil, date: $0.createdAt, note: $0, attachmentID: nil) }
        case "Attachments": return iris.attachments.map { .init(id: $0.id.uuidString, title: $0.name, text: $0.text, source: nil, date: nil, note: nil, attachmentID: $0.id) }
        default: return store.documents.filter { source == nil || $0.source == source }.map { .init(id: $0.id, title: $0.title, text: $0.body, source: $0.source, date: $0.updatedAt, note: nil, attachmentID: nil) }
        }
    }
    private var results: [LibraryItem] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { term.isEmpty || $0.title.localizedCaseInsensitiveContains(term) || $0.text.localizedCaseInsensitiveContains(term) }
    }
    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 780
            VStack(alignment: .leading, spacing: 0) {
                header.padding(24)
                memoryScan.padding(.horizontal, 24).padding(.bottom, 20)
                IrisTabBar(items: ["Library", "Notes", "Attachments", "Connections"], selection: $section).padding(.horizontal, 24)
                if section == "Connections" {
                    ScrollView { KnowledgeConnectionsView(iris: iris).padding(24) }
                } else {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").irisSymbolStyle().foregroundStyle(.secondary)
                        TextField("Search \(section.lowercased())", text: $query).textFieldStyle(.plain).accessibilityLabel("Search knowledge")
                        if !query.isEmpty { Button { query = "" } label: { Image(systemName: "xmark.circle.fill").irisSymbolStyle() }.buttonStyle(.plain).help("Clear search") }
                    }.padding(11).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 10))
                    if section == "Library" {
                        IrisPicker("Source", selection: $source, display: source?.name ?? "All sources", showsTitle: false, footerTitle: "Manage sources…", footerAction: { section = "Connections" }, options:
                            [.init(value: Optional<KnowledgeConnector>.none, title: "All sources", symbol: "square.grid.2x2")] + KnowledgeConnector.allCases.filter { connector in store.documents.contains { $0.source == connector } }.map { .init(value: Optional($0), title: $0.name, symbol: $0.symbol) }
                        ).frame(width: 190)
                    }
                }.padding(.horizontal, 24).padding(.vertical, 16)
                HStack {
                    Text("\(results.count) \(results.count == 1 ? "item" : "items")").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if section == "Attachments" { Text("Ready for your next message").font(.caption).foregroundStyle(.secondary) }
                    else { Text("Stored on this Mac").font(.caption).foregroundStyle(.secondary) }
                }.padding(.horizontal, 24).padding(.bottom, 12)
                if composing { noteComposer.padding(.horizontal, 24).padding(.bottom, 16) }
                Divider()
                HStack(spacing: 0) {
                    ScrollView {
                        if results.isEmpty { emptyState.padding(32) }
                        else { LazyVStack(spacing: 0) {
                            ForEach(results) { item in
                                itemRow(item)
                                Divider().padding(.leading, 76)
                            }
                        }.padding(.vertical, 8) }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if wide {
                        Divider()
                        Group {
                            if let selected { preview(selected) }
                            else { VStack(spacing: 12) {
                                Image(systemName: "doc.text.magnifyingglass").irisSymbolStyle().font(.system(size: 28)).foregroundStyle(iris.accent)
                                Text("A closer look").font(.headline)
                                Text("Select an item to read it or bring it into a conversation.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity) }
                        }.frame(width: max(310, min(440, geometry.size.width * 0.43)))
                    }
                }
                }
            }
            .sheet(item: Binding(get: { wide ? nil : selected }, set: { selected = $0 })) { item in
                VStack(spacing: 0) {
                    HStack { Spacer(); Button("Done") { selected = nil }.keyboardShortcut(.cancelAction) }.padding(20)
                    preview(item)
                }.frame(minWidth: 520, idealWidth: 620, minHeight: 440, idealHeight: 600)
            }
        }
        .onChange(of: section) { _, _ in selected = nil; query = ""; source = nil }
        .sheet(isPresented: $reviewingMemories) {
            VStack(spacing: 0) {
                HStack { Text("Iris’s memory").font(.title2.bold()); Spacer(); Button("Done") { reviewingMemories = false }.keyboardShortcut(.cancelAction) }.padding(24)
                Divider()
                ScrollView { MemorySettingsView(iris: iris).padding(24) }
            }.frame(width: 620, height: 640)
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: composing)
        .alert("Delete this note?", isPresented: Binding(get: { noteToDelete != nil }, set: { if !$0 { noteToDelete = nil } })) {
            Button("Cancel", role: .cancel) { noteToDelete = nil }
            Button("Delete", role: .destructive) { if let noteToDelete { iris.removeNote(noteToDelete.id); if selected?.note?.id == noteToDelete.id { selected = nil } }; noteToDelete = nil }
        } message: { Text("This removes the note from local Iris storage.") }
    }
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 20) { heading.fixedSize(horizontal: true, vertical: true); Spacer(minLength: 16); actions }
            VStack(alignment: .leading, spacing: 16) { heading; actions }
        }
    }
    private var heading: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your knowledge").font(.system(size: 26, weight: .semibold)).tracking(-0.5)
            Text("Find, read, and ask about what you’ve saved.").font(.system(size: 13)).foregroundStyle(.secondary)
        }
    }
    private var memoryScan: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "brain.head.profile").irisSymbolStyle().font(.system(size: 23)).foregroundStyle(iris.accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Turn knowledge into memory").font(.system(size: 14, weight: .semibold))
                    Text(iris.knowledgeScanStatus.isEmpty ? "Scan saved notes and enabled sources with \(iris.preferences.source.rawValue). Unchanged material is skipped." : iris.knowledgeScanStatus)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2).help(iris.knowledgeScanStatus)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if iris.knowledgeScanning {
                    Button("Stop", action: iris.stopKnowledgeScan).buttonStyle(IrisActionStyle())
                } else {
                    Button(action: iris.scanKnowledgeNow) { Label("Scan now", systemImage: "arrow.trianglehead.2.clockwise.rotate.90").fixedSize() }.buttonStyle(IrisActionStyle())
                }
            }
            if iris.knowledgeScanning { ProgressView(value: iris.knowledgeScanProgress).tint(iris.accent).accessibilityLabel("Knowledge scan progress") }
            if let issue = iris.knowledgeScanIssue { Label(issue, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Text("\(iris.visibleKnowledgeMemories.reduce(0) { $0 + $1.facts.count }) knowledge memories · pending chat attachments excluded").font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Review memories") { reviewingMemories = true }.buttonStyle(.plain).font(.caption.weight(.medium)).foregroundStyle(iris.accent)
            }
        }.padding(16).background(iris.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(iris.accent.opacity(0.16), lineWidth: 1))
    }
    private var actions: some View {
        // Report the actions' real width so the header moves them below the title
        // before SwiftUI can squeeze a two-word label into two lines.
        HStack(spacing: 12) {
            Button { section = "Connections" } label: {
                Label("Add connection", systemImage: "plus.circle.fill").lineLimit(1).fixedSize().frame(minHeight: 22)
            }.buttonStyle(IrisActionStyle())
            Button { section = "Notes"; composing.toggle() } label: {
                Label("New note", systemImage: "square.and.pencil").lineLimit(1).fixedSize().frame(minHeight: 22)
            }.buttonStyle(IrisActionStyle())
            Button { iris.chooseFile(); section = "Attachments" } label: {
                Label("Add files", systemImage: "plus").lineLimit(1).fixedSize().frame(minHeight: 22)
            }.buttonStyle(IrisActionStyle(primary: true))
        }.fixedSize(horizontal: true, vertical: true)
    }
    private var noteComposer: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Write a note…", text: $iris.noteDraft, axis: .vertical).lineLimit(3...6).textFieldStyle(.plain).padding(14).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Text("Saved locally until you choose to use it in chat.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Close") { composing = false }
                Button("Save note") { iris.saveNote(); if iris.noteDraft.isEmpty { composing = false } }.disabled(iris.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
    private func itemRow(_ item: LibraryItem) -> some View {
        Button { selected = item } label: {
            HStack(spacing: 14) {
                if let source = item.source { SourceLogo(source: source) }
                else { Image(systemName: item.note != nil ? "note.text" : "doc.text").irisSymbolStyle().font(.system(size: 20)).foregroundStyle(iris.accent).frame(width: 50, height: 50) }
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.title.isEmpty ? "Untitled" : item.title).font(.system(size: 14, weight: .medium)).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(item.source?.name ?? (item.note != nil ? "Saved note" : "Chat attachment"))
                        if let date = item.date { Text("·"); Text(date, style: .date) }
                    }.font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").irisSymbolStyle().font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 20).padding(.vertical, 14).frame(maxWidth: .infinity)
                .background(selected?.id == item.id ? iris.accent.opacity(0.12) : .clear)
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Preview \(item.title)")
    }
    private func preview(_ item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.source?.name ?? (item.note != nil ? "Saved note" : "Chat attachment")).font(.caption).foregroundStyle(.secondary)
                Text(item.title.isEmpty ? "Untitled" : item.title).font(.system(size: 20, weight: .semibold)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if let source = item.source {
                    Label(store.enabled.contains(source.rawValue) ? "Available for AI answers" : "Kept local · not used automatically", systemImage: store.enabled.contains(source.rawValue) ? "checkmark.shield" : "lock").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            ScrollView { Text(item.text.isEmpty ? "No extracted text is available for this item." : item.text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: .infinity)
            Divider()
            Button("Ask Iris about this", systemImage: "bubble.left") { ask(item) }.buttonStyle(IrisActionStyle(primary: true))
            HStack {
                Button("Copy text", systemImage: "doc.on.doc") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(item.text, forType: .string) }
                Spacer()
                if let note = item.note { Button("Delete", role: .destructive) { noteToDelete = note } }
                if let id = item.attachmentID { Button("Remove", role: .destructive) { iris.attachments.removeAll { $0.id == id }; selected = nil } }
            }.font(.caption)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private func ask(_ item: LibraryItem) {
        if item.attachmentID == nil { iris.attachments = [.init(name: item.title, text: item.text)] }
        selected = nil; iris.workspaceSection = .today; iris.tab = .ask; iris.expanded = true
    }
    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: query.isEmpty ? (section == "Notes" ? "note.text" : "books.vertical") : "magnifyingglass").irisSymbolStyle().font(.system(size: 30)).foregroundStyle(iris.accent)
            Text(!query.isEmpty || source != nil ? "No matching items" : (section == "Notes" ? "A place for your thoughts" : section == "Attachments" ? "No files attached" : "Build your personal library")).font(.headline)
            Text(!query.isEmpty || source != nil ? "Try a different search or source." : section == "Library" ? "Connect a source to import documents, mail, or calendars." : section == "Notes" ? "Save ideas here, then bring them into a chat when you need them." : "Add a file to preview its extracted text and ask Iris about it.").font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if section == "Library", query.isEmpty, source == nil { Button("Connect a source") { section = "Connections" } }
        }.frame(maxWidth: .infinity).padding(.vertical, 32)
    }
}
