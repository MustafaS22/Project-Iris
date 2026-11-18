import AppKit
import SwiftUI

struct AppleKnowledgeConnectionView: View {
    let source: KnowledgeConnector
    @ObservedObject var connection: KnowledgeConnections
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String> = []
    @State private var query = ""

    private var choices: [AppleKnowledgeSelection]? { connection.appleChoices[source] }
    private var loading: Bool { connection.busy == source }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                SourceLogo(source: source)
                VStack(alignment: .leading, spacing: 4) {
                    Text(source.name).font(.system(size: 21, weight: .semibold))
                    Text("Choose the \(source.appleSelectionLabel) Iris can read.")
                        .font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
                }
            }
            if source == .appleMessages {
                Text("macOS requires Full Disk Access for Messages history. Add the copy of Iris you’re running, then restart Iris. Only selected conversations’ text is imported.")
                    .font(.caption).foregroundStyle(IrisDesign.secondary)
            }
            if let choices, !choices.isEmpty {
                TextField("Find \(source.appleSelectionLabel)", text: $query).textFieldStyle(IrisTextFieldStyle())
                let matches = choices.filter {
                    query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.detail.localizedCaseInsensitiveContains(query)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if matches.isEmpty { Text("No matches. Try a different search.").foregroundStyle(.secondary).padding(10) }
                        ForEach(matches) { choice in
                            Toggle(isOn: Binding(get: { selected.contains(choice.id) }, set: { enabled in
                                if enabled { selected.insert(choice.id) } else { selected.remove(choice.id) }
                            })) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(choice.title).lineLimit(2)
                                    if !choice.detail.isEmpty { Text(choice.detail).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                                }
                            }
                            .disabled(loading || (selected.count >= 10 && !selected.contains(choice.id)))
                            .padding(.vertical, 7).padding(.horizontal, 10)
                            Divider()
                        }
                    }
                }.frame(height: 224).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 10))
                Text("\(selected.count) selected · up to 10. Import refreshes this source’s local copy.")
                    .font(.caption).foregroundStyle(IrisDesign.secondary)
            } else if choices?.isEmpty == true {
                Text("No \(source.appleSelectionLabel) found. Check that \(source.name) is set up on this Mac.")
                    .font(.callout).foregroundStyle(IrisDesign.secondary)
            }
            if loading {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Connecting to \(source.name)…").font(.caption) }
            }
            if let status = connection.status[source.rawValue] {
                Text(status).font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if choices == nil || choices?.isEmpty == true {
                    if source == .appleMessages {
                        Button("Show Iris in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }.buttonStyle(IrisActionStyle())
                    }
                    if let settingsURL {
                        Button("Open System Settings") { NSWorkspace.shared.open(settingsURL) }.buttonStyle(IrisActionStyle())
                    }
                    Button("Retry") { connection.connect(source) }.buttonStyle(IrisActionStyle()).disabled(loading)
                }
                Spacer()
                Button("Done") { dismiss() }.buttonStyle(IrisActionStyle())
                if choices?.isEmpty == false {
                    Button("Import selected") { connection.importAppleSelection(source, ids: selected) }
                        .buttonStyle(IrisActionStyle(primary: true))
                        .disabled(loading || selected.isEmpty || !selected.isSubset(of: Set((choices ?? []).map(\.id))))
                }
            }
        }
        .padding(24).frame(width: 480)
        .background(IrisDesign.canvas).foregroundStyle(IrisDesign.text)
        .task {
            selected = connection.savedAppleSelection(source)
            connection.connect(source)
        }
        .onChange(of: choices) { _, newChoices in
            if let newChoices { selected.formIntersection(newChoices.map(\.id)) }
        }
    }

    private var settingsURL: URL? {
        let target = switch source {
        case .appleMessages: "Privacy_AllFiles"
        case .appleReminders: "Privacy_Reminders"
        default: "Privacy_Automation"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(target)")
    }
}
