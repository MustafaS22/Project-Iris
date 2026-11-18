import SwiftUI

struct DiagramLibraryBrowser: View {
    let accent: Color
    let choose: (DiagramLibrary.Entry, Bool) -> Void
    var chooseReference: ((DiagramReference, Bool) -> Void)? = nil
    @State private var query = ""
    @State private var narrate = true
    @State private var searching = false
    @State private var found: DiagramReference?
    @State private var searchError: String?
    private var visible: [DiagramLibrary.Entry] {
        let term=query.trimmingCharacters(in:.whitespacesAndNewlines)
        return DiagramLibrary.entries.filter { (term.isEmpty || ($0.title+" "+$0.subject+" "+$0.aliases.joined(separator:" ")).localizedCaseInsensitiveContains(term)) }
    }
    var body: some View {
        VStack(alignment:.leading,spacing:14) {
            Text("Diagram library").font(.system(size:20,weight:.semibold))
            Text("Choose a topic. Iris draws and explains it in steps.").font(.system(size:12)).foregroundStyle(.secondary)
            HStack {Image(systemName:"magnifyingglass");TextField("Find a topic or subject",text:$query).textFieldStyle(.plain)}
                .padding(10).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
            Toggle("Speak the explanation", isOn: $narrate).toggleStyle(.switch).controlSize(.small).font(.system(size:12))
            if !query.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
                Button(searching ? "Finding a reference…" : "Find a diagram online") {
                    guard !searching else{return};searching=true;searchError=nil
                    let requested=query
                    Task {do {let result=try await DiagramReferenceStore.search(requested);if query==requested{found=result}} catch {if query==requested{searchError=error.localizedDescription}};searching=false}
                }.disabled(searching).font(.system(size:12,weight:.semibold))
            }
            if let found {
                HStack {
                    Button("Show "+found.title) {chooseReference?(found,narrate)}.lineLimit(1)
                    if let url=URL(string:found.sourceURL){Link("Source",destination:url)}
                }.font(.system(size:12))
                Text(found.credit).font(.system(size:9)).foregroundStyle(.secondary)
            }
            if let searchError {Text(searchError).font(.system(size:11)).foregroundStyle(.orange)}
            ScrollView {
                LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                    ForEach(visible) {entry in
                        VStack(alignment:.leading,spacing:4) {
                        Button {choose(entry,narrate)} label: {
                            VStack(alignment:.leading,spacing:6) {
                                IrisDrawingView(drawing:entry.drawing,accent:accent,previewElapsed:100)
                                    .frame(width:600,height:400).scaleEffect(0.255,anchor:.topLeading)
                                    .frame(width:153,height:102,alignment:.topLeading).clipped().accessibilityHidden(true)
                                Text(entry.title).font(.system(size:12,weight:.semibold)).foregroundStyle(.primary).lineLimit(2)
                                Text(entry.subject + (entry.drawing.figure == nil ? " · Drawn by Iris" : " · Reference")).font(.system(size:10)).foregroundStyle(.secondary)
                                if entry.drawing.figure != nil, let reference=DiagramReferenceStore.reference(entry.id) {
                                    Text(reference.license).font(.system(size:9)).foregroundStyle(.secondary)
                                }
                            }.padding(8).frame(maxWidth:.infinity,alignment:.leading)
                                .background(.white.opacity(0.035),in:RoundedRectangle(cornerRadius:12))
                                .overlay(RoundedRectangle(cornerRadius:12).strokeBorder(accent.opacity(0.18)))
                        }.buttonStyle(.plain).accessibilityLabel("Play "+entry.title+", "+entry.subject)
                        if entry.drawing.figure != nil, let reference=DiagramReferenceStore.reference(entry.id),let source=URL(string:reference.sourceURL) {
                            HStack {
                                if let imageURL=URL(string:reference.imageURL){Link("Full-size",destination:imageURL)}
                                Spacer()
                                Link("Source & license",destination:source)
                            }.font(.system(size:10)).padding(.horizontal,8)
                        }
                        }
                    }
                }
                if visible.isEmpty {Text("No matching topic. Ask Iris for a custom diagram instead.").font(.callout).foregroundStyle(.secondary).padding()}
            }
            Text("Saved figures work offline. Online search shares only your topic with Wikimedia. Your chosen voice provider may use speech quota.")
                .font(.system(size:10)).foregroundStyle(.secondary)
        }.padding(18).frame(width:390,height:500).preferredColorScheme(.dark)
            .onChange(of:query){_,_ in found=nil;searchError=nil}
    }
}
