import SwiftUI
import AppKit

struct CreationView: View {
    @ObservedObject var iris: IrisOrchestrator
    @StateObject private var draft = CreationDraftModel()
    @AppStorage("IrisCreateKindV2") private var kind = "Document"
    @AppStorage("IrisCreateBriefV2") private var brief = ""
    @AppStorage("IrisCreateFilenameV2") private var filename = "Untitled"
    @AppStorage("IrisCreateFormatV2") private var format = "pdf"
    @State private var tone = "Clear & direct"
    @State private var length = "One page"
    @State private var preview = "Edit"
    @State private var imageStyle = "Illustration"
    @State private var folderID = ""
    @State private var imagePreview: NSImage?
    private let formatNames = ["pdf": "PDF", "rtf": "Rich text", "html": "HTML", "md": "Markdown", "txt": "Plain text", "csv": "CSV", "json": "JSON"]
    private var files: [ChatFileReference] {
        let chat = (iris.data.conversations ?? []).sorted { $0.updatedAt > $1.updatedAt }.flatMap { $0.messages.filter { $0.role == "assistant" }.flatMap { $0.files ?? [] } }
        var ids = Set<UUID>()
        return Array((draft.exports + chat).filter { ids.insert($0.id).inserted }.prefix(8))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Create").font(.system(size: 34, weight: .semibold)).tracking(-0.8)
                    Text("From a rough idea to a file you can use.").font(.system(size: 15)).foregroundStyle(IrisDesign.secondary)
                }
                Spacer(); Image(systemName: "paintbrush.pointed.fill").irisSymbolStyle().font(.system(size: 34, weight: .semibold)).foregroundStyle(iris.accent)
            }
            IrisTabBar(items: ["Document", "Image"], selection: $kind).disabled(draft.busy || draft.reading || iris.busy)
            if kind == "Document" {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 24) { documentBrief.frame(width: 270); editor.frame(minWidth: 330, idealWidth: 330, maxWidth: .infinity) }
                    VStack(alignment: .leading, spacing: 24) { documentBrief; editor }
                }
            } else { imageWorkshop }
            if !files.isEmpty {
                Divider()
                Text("Recent files").font(.system(size: 18, weight: .semibold))
                Text("Open a saved result directly, or attach it to your next conversation.").font(.caption).foregroundStyle(IrisDesign.secondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 12) {
                    ForEach(files) { ChatFileCard(iris: iris, file: $0) }
                }
            }
        }
        .onChange(of: draft.content) { _, _ in if !draft.busy { draft.persist() } }
        .onChange(of: iris.messages.count) { _, _ in loadImage() }
        .onDisappear { draft.saveInLibrary(iris: iris); draft.stop() }
    }
    private var documentBrief: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("The brief").font(.system(size: 20, weight: .semibold))
            Text("Describe the result, or start writing directly in the editor.").font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
            briefEditor("What are we making? Include the audience and key points.")
            IrisPicker("Writing style", selection: $tone, options: ["Clear & direct", "Warm & conversational", "Academic", "Professional"].map { .init(value: $0, title: $0) })
            IrisPicker("Length", selection: $length, options: ["One page", "Short", "Detailed"].map { .init(value: $0, title: $0) })
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Reference material").font(.system(size: 13, weight: .medium)); Spacer(); Button { draft.addReference() } label: { Image(systemName: "plus").irisSymbolStyle() }.disabled(draft.busy || draft.reading || draft.references.count >= 3).help("Add a reference") }
                ForEach(draft.references) { reference in
                    HStack { Image(systemName: "doc.text").irisSymbolStyle().foregroundStyle(iris.accent); Text(reference.name).lineLimit(1); Spacer(); Button { draft.references.removeAll { $0.id == reference.id } } label: { Image(systemName: "xmark").irisSymbolStyle() }.disabled(draft.busy) }.font(.caption)
                }
                if draft.references.isEmpty { Text("Up to three files · optional").font(.caption).foregroundStyle(IrisDesign.secondary) }
                if draft.reading { ProgressView().controlSize(.small) }
            }
            Button(draft.content.isEmpty ? "Generate draft" : "Revise draft", systemImage: "sparkles") {
                draft.generate(iris: iris, brief: brief, format: format, tone: tone, length: length, revise: !draft.content.isEmpty)
            }.buttonStyle(IrisActionStyle(primary: true)).disabled(draft.busy || draft.reading || brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || iris.busy)
            Text("Uses your selected chat model. References are shared only on Generate. Drafting cannot run computer actions or save files.").font(.caption).foregroundStyle(IrisDesign.secondary)
        }
    }
    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("Your draft").font(.system(size: 20, weight: .semibold)); Spacer(); if !draft.busy { Button("New") { draft.saveInLibrary(iris: iris); draft.newDraft() }.font(.caption); if !draft.previousVersion.isEmpty { Button("Restore") { draft.restorePrevious() }.font(.caption).help("Restore the previous draft") } }; if draft.busy { ProgressView().controlSize(.small); Button("Stop") { draft.stop() } } }
            IrisTabBar(items: ["Edit", "Preview"], selection: $preview)
            Group {
                if preview == "Edit" {
                    TextEditor(text: $draft.content).font(.system(size: 14, design: ["csv", "json"].contains(format) ? .monospaced : .default))
                        .scrollContentBackground(.hidden).padding(16).frame(minHeight: 340).disabled(draft.busy).accessibilityLabel("Editable document draft")
                } else {
                    ScrollView {
                        if draft.content.isEmpty { emptyDocument }
                        else { FormattedResponse(text: ["csv", "json"].contains(format) ? "```\(format)\n\(draft.content)\n```" : draft.content, fontSize: 14).padding(18) }
                    }.frame(minHeight: 340, maxHeight: 500)
                }
            }.background(IrisDesign.surface.opacity(0.7), in: RoundedRectangle(cornerRadius: 14))
            if draft.content.isEmpty && !draft.busy {
                HStack(spacing: 12) {
                    Text("Start from").font(.caption).foregroundStyle(IrisDesign.secondary)
                    Button("Study guide") { draft.content = "# Study guide\n\n## Key concepts\n\n## Worked examples\n\n## Questions to practice\n\n## Recap\n" }
                    Button("Project brief") { draft.content = "# Project brief\n\n## Goal\n\n## Audience\n\n## Scope\n\n## Milestones\n\n## Definition of done\n" }
                }.font(.caption).buttonStyle(.plain)
            }
            HStack { Text("\(draft.content.split { $0.isWhitespace || $0.isNewline }.count) words").font(.caption).foregroundStyle(IrisDesign.secondary); Spacer(); Text(draft.busy ? "Drafting…" : "Saved locally").font(.caption).foregroundStyle(IrisDesign.secondary) }
            IrisFormField(title: "Filename", prompt: "Untitled", text: $filename)
            HStack(alignment: .bottom, spacing: 12) {
                IrisPicker("Export as", selection: $format, options: CreationPolicy.formats.map { .init(value: $0, title: formatNames[$0] ?? $0, symbol: "doc") }).disabled(draft.busy)
                Button("Export…", systemImage: "square.and.arrow.up") { draft.export(iris: iris, name: filename, format: format) }.buttonStyle(IrisActionStyle(primary: true)).disabled(draft.busy || draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if !draft.status.isEmpty { Text(draft.status).font(.caption).foregroundStyle(iris.accent) }
            if let error = draft.error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
        }
    }
    private var emptyDocument: some View {
        VStack(spacing: 16) { Image(systemName: "doc.richtext").irisSymbolStyle().font(.system(size: 42, weight: .semibold)).foregroundStyle(iris.accent); Text("A little room for your next idea.").font(.headline); Text("Write in Edit, or generate from your brief.").font(.caption).foregroundStyle(IrisDesign.secondary) }.frame(maxWidth: .infinity).padding(.vertical, 90)
    }
    private func briefEditor(_ prompt: String) -> some View {
        TextField(prompt, text: $brief, axis: .vertical).lineLimit(5...10).textFieldStyle(.plain).font(.system(size: 14)).padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(iris.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12)).disabled(draft.busy)
    }
    private var imageWorkshop: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 20) {
                Image(systemName: "photo.on.rectangle.angled").irisSymbolStyle().font(.system(size: 42, weight: .semibold)).foregroundStyle(iris.accent)
                VStack(alignment: .leading, spacing: 8) { Text("Make the picture in your head.").font(.system(size: 23, weight: .semibold)); Text("Describe the subject, composition, lighting and details that matter.").font(.callout).foregroundStyle(IrisDesign.secondary) }
            }.padding(.vertical, 12)
            briefEditor("Describe your image…")
            HStack(alignment: .bottom, spacing: 16) {
                IrisPicker("Visual style", selection: $imageStyle, options: ["Illustration", "Photography", "Graphic design", "As described"].map { .init(value: $0, title: $0) })
                IrisFormField(title: "Filename", prompt: "Untitled", text: $filename)
            }
            HStack(alignment: .bottom, spacing: 16) {
                IrisPicker("Save in", selection: $folderID, display: iris.actions.folders.first { $0.id == folderID }?.name ?? "Choose a folder", options: [.init(value: "", title: "Choose a folder")] + iris.actions.folders.map { .init(value: $0.id, title: $0.name, symbol: "folder") })
                Button("Grant folder…") { iris.actions.grant() }.buttonStyle(IrisActionStyle())
            }
            Text(ImageGenerationService.reviewDescription).font(.caption).foregroundStyle(IrisDesign.secondary)
            Button("Generate image", systemImage: "sparkles") { prepareImage() }.buttonStyle(IrisActionStyle(primary: true)).disabled(brief.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || folderID.isEmpty || iris.busy)
            if let imagePreview { Image(nsImage: imagePreview).resizable().scaledToFit().frame(maxHeight: 360).clipShape(RoundedRectangle(cornerRadius: 16)).frame(maxWidth: .infinity) }
            if iris.busy { LiveResponseView(iris: iris) }
            ActionReview(iris: iris)
            if !iris.actions.result.isEmpty { Text(iris.actions.result).font(.caption).foregroundStyle(IrisDesign.secondary) }
            DisclosureGroup("Image provider setup") { ImageProviderSettings().padding(.top, 16) }
        }
    }
    private func prepareImage() {
        do {
            let path = try CreationPolicy.filename(filename, format: "png")
            guard iris.actions.folders.contains(where: { $0.id == folderID }) else { return }
            iris.newConversation(); iris.workspaceSection = .create
            let prompt = brief + (imageStyle == "As described" ? "" : "\nVisual style: " + imageStyle)
            iris.messages.append(.init(role: "user", text: "Generate an image: " + prompt))
            iris.perform(.init(type: "generateImage", folder: folderID, path: path, content: prompt))
        } catch { iris.error = error.localizedDescription }
    }
    private func loadImage() {
        guard kind == "Image", let file = iris.messages.last(where: { $0.role == "assistant" })?.files?.first(where: { $0.name.lowercased().hasSuffix(".png") }) else { return }
        imagePreview = try? iris.actions.withFile(file) { NSImage(contentsOf: $0) }
    }
}
