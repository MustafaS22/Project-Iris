import SwiftUI
import AppKit
import EventKit

struct KnowledgeConnectionsView: View {
    @ObservedObject var iris: IrisOrchestrator
    var compact = false
    var showsHeading = true
    @State private var sourceToRemove: KnowledgeConnector?
    @State private var selectedDocument: KnowledgeDocument?
    @State private var sharingSource: KnowledgeConnector?
    @State private var filter = ""
    @State private var showWhatsApp = false
    @State private var setupSource: KnowledgeConnector?
    @State private var appleSource: KnowledgeConnector?
    @State private var sourceQuery = ""
    private var visibleSources: [KnowledgeConnector] { KnowledgeConnector.allCases.filter { sourceQuery.isEmpty || $0.name.localizedCaseInsensitiveContains(sourceQuery) || $0.detail.localizedCaseInsensitiveContains(sourceQuery) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !compact && showsHeading { HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Connections").font(.system(size: 30, weight: .semibold)).tracking(-0.7)
                    Text("Bring your world to Iris. Choose what stays local and what helps with answers.").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(iris.knowledge.documents.count) items").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            }
            }
            if let error = iris.knowledge.error { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.orange) }
            TextField("Find a connection", text: $sourceQuery).textFieldStyle(IrisTextFieldStyle())
            if visibleSources.isEmpty { Text("No matching connections. Try another app name.").foregroundStyle(.secondary) }
            ForEach(Array(visibleSources.enumerated()), id: \.element.id) { index, source in
                if index == 0 || visibleSources[index - 1].group != source.group { Text(source.group).font(.system(size: 18, weight: .semibold)).padding(.top, 12) }
                let count = iris.knowledge.documents.filter { $0.source == source }.count
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 14) {
                        SourceLogo(source: source)
                        VStack(alignment: .leading, spacing: 4) { Text(source.name).font(.system(size: 14, weight: .semibold)); Text(source.detail).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
                        Spacer()
                        if iris.connections.busy == source { ProgressView().controlSize(.small); Button("Cancel") { iris.connections.cancel() } }
                        else { Button(connectionLabel(source, count: count)) {
                            if source == .whatsapp { showWhatsApp = true }
                            else if source.usesAppleSelection { appleSource = source }
                            else if AppKnowledgeAPI.tokenSources.contains(source) || source == .googleChat || source == .googleTasks { setupSource = source }
                            else { iris.connections.connect(source) }
                        }.buttonStyle(IrisActionStyle(primary: count == 0)).fixedSize().disabled(iris.connections.busy != nil) }
                    }
                    if let status = iris.connections.status[source.rawValue] { Text(status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled).id(status) }
                    if source == .appleCalendar, !iris.connections.calendars.isEmpty {
                        ForEach(iris.connections.calendars, id: \.calendarIdentifier) { calendar in
                            Toggle(calendar.title, isOn: Binding(get: { iris.connections.selectedCalendars.contains(calendar.calendarIdentifier) }, set: { value in if value { iris.connections.selectedCalendars.insert(calendar.calendarIdentifier) } else { iris.connections.selectedCalendars.remove(calendar.calendarIdentifier) } })).font(.caption)
                        }
                        Button("Import selected calendars · next 30 days") { iris.connections.importCalendarEvents() }.disabled(iris.connections.selectedCalendars.isEmpty)
                    }
                    if count > 0, KnowledgeConnections.supportsAutomaticRefresh(source) {
                        Toggle("Refresh automatically · every 15 minutes while Iris is open", isOn: Binding(get: { iris.connections.automaticSources.contains(source.rawValue) }, set: { iris.connections.setAutomatic(source, enabled: $0) })).toggleStyle(.switch).controlSize(.small).font(.caption)
                    }
                    if count > 0 {
                        HStack {
                            Toggle("Use in answers", isOn: Binding(get: { iris.knowledge.enabled.contains(source.rawValue) }, set: { value in if value { sharingSource = source } else { setSharing(source, false) } })).toggleStyle(.switch).controlSize(.small)
                            Text("\(count) items · on this Mac").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Remove", role: .destructive) { sourceToRemove = source }.font(.caption)
                        }.font(.system(size: 12))
                    }
                }.padding(.vertical, 12)
                Divider()
            }
            HStack {
                Image(systemName: "lock.shield").irisSymbolStyle().foregroundStyle(iris.accent)
                Text("Connected sources can refresh automatically using existing access and your saved selections. File exports remain snapshots. Iris never sends messages or edits source files.").font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup("Google connection help") {
                VStack(alignment: .leading, spacing: 10) {
                    GoogleConnectionHelp()
                    DisclosureGroup("Developer registration") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Iris includes its Desktop OAuth client. A local override is only needed when testing a different Google Cloud project.").font(.caption).foregroundStyle(IrisDesign.secondary)
                            Button("Import a local override…") { do { _ = try GoogleAppConfiguration.importFile() } catch { iris.error = error.localizedDescription } }
                            Button("Use included registration") { GoogleAppConfiguration.useBundled() }
                        }.padding(.top, 8)
                    }

                }.padding(.top, 8)
            }
            if !compact && !iris.knowledge.documents.isEmpty {
                Divider()
                TextField("Find something in your knowledge", text: $filter).textFieldStyle(IrisTextFieldStyle())
                ForEach(iris.knowledge.documents.filter { filter.isEmpty || $0.title.localizedCaseInsensitiveContains(filter) || $0.body.localizedCaseInsensitiveContains(filter) }.prefix(50)) { document in
                    Button { selectedDocument = document } label: {
                        HStack { SourceLogo(source: document.source, size: 18, showsBackground: false); VStack(alignment: .leading, spacing: 4) { Text(document.title).font(.system(size: 13, weight: .medium)); Text(document.source.name).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "arrow.up.right").irisSymbolStyle() }.padding(.vertical, 8)
                    }.buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $appleSource) { source in AppleKnowledgeConnectionView(source: source, connection: iris.connections) }
        .sheet(item: $setupSource) { source in AppConnectorSetup(iris: iris, source: source) }
        .sheet(isPresented: $showWhatsApp) { WhatsAppConnectionView(connection: iris.connections.whatsApp, accent: iris.accent, sharingEnabled: iris.knowledge.enabled.contains(KnowledgeConnector.whatsapp.rawValue)) }
        .alert("Use this source in AI answers?", isPresented: Binding(get: { sharingSource != nil }, set: { if !$0 { sharingSource = nil } })) {
            Button("Keep local", role: .cancel) { sharingSource = nil }
            Button("Allow relevant excerpts") { if let source = sharingSource { setSharing(source, true) }; sharingSource = nil }
        } message: { Text("When you send a question, relevant excerpts from this source may be sent to your selected model provider. You can turn this off at any time.") }
        .alert("Remove this knowledge source?", isPresented: Binding(get: { sourceToRemove != nil }, set: { if !$0 { sourceToRemove = nil } })) {
            Button("Cancel", role: .cancel) { sourceToRemove = nil }
            Button("Remove local knowledge", role: .destructive) { if let source = sourceToRemove { do { iris.connections.setAutomatic(source, enabled: false); try iris.knowledge.remove(source) } catch { iris.error = error.localizedDescription } }; sourceToRemove = nil }
        } message: { Text("This removes imported items from Iris and turns off their use in answers. Original files, mail and calendars are unchanged. Google access can be revoked in your Google Account.") }
        .sheet(item: $selectedDocument) { document in
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text(document.title).font(.title2); Spacer(); Button("Done") { selectedDocument = nil } }
                HStack(spacing: 6) { SourceLogo(source: document.source, size: 16, showsBackground: false); Text(document.source.name) }.font(.caption).foregroundStyle(.secondary)
                ScrollView { Text(document.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Button("Ask about this item") { iris.attachments = [.init(name: document.title, text: document.body)]; selectedDocument = nil; iris.workspaceSection = .today }
            }.padding(28).frame(width: 650, height: 500)
        }
    }
    private func connectionLabel(_ source: KnowledgeConnector, count: Int) -> String {
        if source == .whatsapp { return count > 0 ? "Manage chats" : "Connect" }
        if SocialExportReader.sources.contains(source) { return "Import files" }
        if AppKnowledgeAPI.tokenSources.contains(source) || source == .googleChat || source == .googleTasks { return count > 0 ? "Manage" : "Set up" }
        if source == .files { return "Choose files" }
        if source.usesAppleSelection { return count > 0 ? "Manage" : "Connect" }
        return count > 0 ? "Import again" : "Connect"
    }
    private func setSharing(_ source: KnowledgeConnector, _ value: Bool) { do { try iris.knowledge.setSharing(source, enabled: value) } catch { iris.error = error.localizedDescription } }
}

struct SourceLogo: View {
    var source: KnowledgeConnector
    var size: CGFloat = 34
    var showsBackground = true
    var body: some View {
        Group {
            switch source {
            case .appleNotes: Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Applications/Notes.app")).resizable().scaledToFit()
            case .appleReminders, .appleMessages, .appleMail:
                Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Applications/\(source == .appleReminders ? "Reminders" : source == .appleMessages ? "Messages" : "Mail").app")).resizable().scaledToFit()
            case .appleCalendar: Image(nsImage: NSWorkspace.shared.icon(forFile: "/System/Applications/Calendar.app")).resizable().scaledToFit()
            case .gmail, .drive, .googleCalendar, .googleChat, .googleTasks, .whatsapp, .github, .notion, .slack, .todoist, .linear, .instagram, .x, .telegram:
                Image("ConnectionLogo-\(source.rawValue)").renderingMode(.original).resizable().scaledToFit()
            case .files: Image(systemName: "folder.fill").resizable().irisSymbolStyle().scaledToFit().foregroundStyle(.blue)
            }
        }.frame(width: size, height: size).padding(showsBackground ? 8 : 0).background { if showsBackground { RoundedRectangle(cornerRadius: 12).fill(IrisDesign.surface) } }.accessibilityHidden(true)
    }
}
