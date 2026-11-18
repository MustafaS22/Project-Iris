import SwiftUI
import AppKit
import AVFoundation
import Speech

struct ContentView: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var deleteNote: QuickNote?
    @State private var clearHistory = false
    @State private var webQuery = ""
    @AppStorage("IrisSidebarCollapsed") private var sidebarCollapsed = false
    @Environment(\.irisReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 0) {
            if !sidebarCollapsed && iris.workspaceSection != .settings { sidebar; Divider() }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    if iris.workspaceSection == .settings {
                        Button { iris.workspaceSection = .today } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 28, height: 28)
                        }
                        .help("Back to Iris")
                        .accessibilityLabel("Back to Iris")
                    } else if sidebarCollapsed {
                        Button { sidebarCollapsed = false } label: { Image(systemName: "sidebar.left").irisSymbolStyle().frame(width: 28, height: 28) }.buttonStyle(.plain).help("Show sidebar").accessibilityLabel("Show sidebar")
                    }
                    Text(iris.workspaceSection.rawValue).font(.system(size: 13, weight: .semibold)).foregroundStyle(IrisDesign.secondary)
                    Spacer()
                    if iris.voice.listening { Button("Stop listening", systemImage: "mic.fill") { iris.voice.stop() }.foregroundStyle(.orange) }
                    if iris.workspaceSection == .today {
                        Button { iris.newConversation() } label: { Image(systemName: "square.and.pencil").irisSymbolStyle().frame(width: 28, height: 28) }.help("New chat").disabled(iris.messages.isEmpty)
                    }
                    Button { iris.returnToNotch?() } label: { Label("Back to notch", systemImage: "rectangle.topthird.inset.filled") }.font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                }.buttonStyle(.plain).padding(.leading, sidebarCollapsed || iris.workspaceSection == .settings ? 84 : 24).padding(.trailing, 24).frame(height: 56)
                Divider()
                if iris.workspaceSection == .today { AssistantHome(iris: iris).frame(maxWidth: .infinity, maxHeight: .infinity).clipped() } else if iris.workspaceSection == .agents { AgentWorkspace(iris: iris, store: iris.agents) } else if iris.workspaceSection == .knowledge { KnowledgeLibraryView(iris: iris) } else if iris.workspaceSection == .settings { AssistantSettingsView(iris: iris) } else { ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if let error = iris.error {
                            HStack(alignment: .top) { Image(systemName: "exclamationmark.circle").irisSymbolStyle(); Text(error).textSelection(.enabled); Spacer(); Button("Dismiss") { iris.error = nil } }.font(.system(size: 12)).padding(16).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                        }
                        switch iris.workspaceSection {
                            case .today: EmptyView()
                            case .agents: EmptyView()
                            case .tools: StudioView(iris: iris)
                            case .create: CreationView(iris: iris)
                            case .library: CreationLibraryView(iris: iris)
                            case .chats: ChatHistoryView(iris: iris)
                            case .knowledge: EmptyView()
                            case .connections: KnowledgeConnectionsView(iris: iris)
                            case .sessions: sessions
                            case .settings: AssistantSettingsView(iris: iris)
                            case .testing: AppTestingView(iris: iris)
                        }
                    }.padding(32).frame(maxWidth: iris.workspaceSection == .tools ? .infinity : 850, alignment: .leading).frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            }
            .background(IrisBackdrop(accent: iris.accent))
        }.frame(minWidth: 880, minHeight: 650).ignoresSafeArea(.container, edges: .top)
            .tint(iris.accent).environment(\.irisControlAccent, iris.accent).textFieldStyle(IrisTextFieldStyle())
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: iris.workspaceSection)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: sidebarCollapsed)
            .foregroundStyle(IrisDesign.text).preferredColorScheme(.dark).groupBoxStyle(IrisGroupStyle())
            .alert("Delete this note?", isPresented: Binding(get: { deleteNote != nil }, set: { if !$0 { deleteNote = nil } })) {
                Button("Cancel", role: .cancel) { deleteNote = nil }
                Button("Delete", role: .destructive) { if let note = deleteNote { iris.removeNote(note.id) }; deleteNote = nil }
            } message: { Text("This removes the note from local Iris storage.") }
            .alert("Clear session history?", isPresented: $clearHistory) {
                Button("Cancel", role: .cancel) {}
                Button("Clear history", role: .destructive) { iris.data.history = []; iris.save() }
            }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button { sidebarCollapsed = true } label: { Image(systemName: "sidebar.left").irisSymbolStyle().frame(width: 28, height: 28) }.buttonStyle(.plain).help("Hide sidebar").accessibilityLabel("Hide sidebar")
            }.padding(.horizontal, 16).frame(height: 56)
            HStack(spacing: 10) { IrisBrandMark(color: iris.accent); Text("Iris").font(.system(size: 22, weight: .bold)); Text("2.0").font(.system(size: 10, weight: .medium)).foregroundStyle(IrisDesign.secondary); Spacer() }.padding(.horizontal, 24).padding(.top, 8).padding(.bottom, 18)
            Divider().opacity(0.5)
            Button { iris.newConversation() } label: {
                Label("New conversation", systemImage: "plus.bubble").font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    .background(iris.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain).padding(12)
            VStack(spacing: 4) {
                ForEach([IrisOrchestrator.WorkspaceSection.today, .agents, .library, .knowledge], id: \.self) { section in navigationRow(section) }
            }.padding(.horizontal, 12)
            if !(iris.data.conversations ?? []).isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Recent chats").font(.system(size: 11, weight: .semibold)).foregroundStyle(IrisDesign.secondary)
                        Spacer()
                        Button { iris.workspaceSection = .chats } label: {
                            Label("View all", systemImage: "chevron.right").labelStyle(.titleOnly).font(.system(size: 11))
                        }.buttonStyle(.plain).foregroundStyle(IrisDesign.secondary).help("Open chat history")
                    }.padding(.horizontal, 12)
                    ScrollView {
                        VStack(spacing: 3) {
                            ForEach(Array((iris.data.conversations ?? []).sorted { $0.updatedAt > $1.updatedAt }.prefix(6))) { conversation in
                                RecentChatRow(title: conversation.sidebarTitle,
                                    selected: iris.workspaceSection == .today && !iris.messages.isEmpty && iris.data.activeConversationID == conversation.id,
                                    accent: iris.accent) { iris.openConversation(conversation) }
                            }
                        }
                    }.scrollIndicators(.hidden).frame(minHeight: 36, maxHeight: 225)
                }.padding(.horizontal, 12).padding(.top, 24).layoutPriority(-1)

            }
            Spacer(minLength: 20)
            VStack(spacing: 4) { navigationRow(.settings) }.padding(.horizontal, 12)
            HStack { Text("Summon Iris").font(.system(size: 10)); Spacer(); Text(iris.shortcuts.label(.notch)).font(.system(size: 10)) }.foregroundStyle(IrisDesign.secondary).padding(20)
        }.frame(width: 228).frame(maxHeight: .infinity).background { IrisDesign.sidebar; LinearGradient(colors: [iris.accent.opacity(0.045), .clear], startPoint: .topLeading, endPoint: .bottomTrailing) }
    }
    private func navigationRow(_ section: IrisOrchestrator.WorkspaceSection) -> some View {
        Button { iris.workspaceSection = section } label: {
            HStack(spacing: 12) {
                Image(systemName: symbol(section)).irisSymbolStyle().font(.system(size: 17, weight: .semibold)).frame(width: 22).foregroundStyle(iris.workspaceSection == section ? iris.accent : IrisDesign.secondary)
                Text(section.rawValue).font(.system(size: 13, weight: iris.workspaceSection == section ? .semibold : .regular))
                Spacer()
                if section == .agents, iris.agents.runningCount > 0 { Text("\(iris.agents.runningCount)").font(.system(size: 10, weight: .semibold)).foregroundStyle(iris.accent) }
                if section == .chats, let count = iris.data.conversations?.count, count > 0 { Text("\(count)").font(.caption).foregroundStyle(IrisDesign.secondary) }
            }.padding(.horizontal, 12).frame(height: 42).background(iris.workspaceSection == section ? IrisDesign.control.opacity(0.8) : .clear, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
    private func symbol(_ section: IrisOrchestrator.WorkspaceSection) -> String {
        switch section { case .today: "bubble.left.and.bubble.right.fill"; case .agents: "person.2.fill"; case .tools: "wrench.and.screwdriver.fill"; case .create: "paintbrush.pointed.fill"; case .library: "folder.fill"; case .chats: "clock.fill"; case .knowledge: "books.vertical.fill"; case .connections: "square.grid.2x2.fill"; case .sessions: "timer"; case .settings: "gearshape.fill"; case .testing: "ladybug.fill" }
    }
    private func title(_ eyebrow: String, _ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 30, weight: .semibold)).tracking(-0.7)
            Text(subtitle).font(.system(size: 14)).lineSpacing(4).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var today: some View {
        VStack(alignment: .leading, spacing: 28) {
            title("Your space", iris.preferences.name.isEmpty ? "Room for your next idea." : "A little room, \(iris.preferences.name).", "Start with one thing. Iris keeps the useful parts close, and the rest quiet.")
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Focus", systemImage: "timer").font(.system(size: 13, weight: .semibold))
                    if let session = iris.data.session {
                        Text(session.goal).font(.system(size: 19, weight: .medium))
                        Text(iris.timeString(session.remaining(at: iris.now))).font(.system(size: 48, weight: .ultraLight, design: .monospaced)).foregroundStyle(iris.accent)
                        Button(session.isRunning ? "Pause session" : "Resume session") { iris.toggleSession() }
                    } else {
                        Text("What will you make room for?").font(.system(size: 22, weight: .medium))
                        TextField("One small goal", text: $iris.goal).textFieldStyle(IrisTextFieldStyle())
                        HStack { Stepper("\(iris.minutes) minutes", value: $iris.minutes, in: 1...180); Spacer(); Button("Begin") { iris.startSession(); iris.expanded = true }.buttonStyle(.borderedProminent).disabled(iris.goal.isEmpty) }
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 20))
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("Think with Iris").font(.system(size: 20, weight: .medium)); Spacer(); if !iris.messages.isEmpty { Button("Clear conversation") { iris.messages = [] } .font(.caption) } }
                if iris.messages.isEmpty { Text("Ask about an idea, work through a problem, or attach something to read. Conversation stays in memory until you quit.").font(.system(size: 13)).foregroundStyle(.secondary) }
                ForEach(iris.messages) { message in
                    VStack(alignment: .leading, spacing: 6) { Text(message.role == "user" ? "YOU" : "IRIS").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary); MessageContent(iris: iris, message: message, fontSize: 14) }.padding(.vertical, 8)
                }
            ForEach(iris.attachments) { attachment in Label(attachment.name, systemImage: "paperclip").font(.caption).foregroundStyle(.secondary) }
                TextField("What's on your mind?", text: $iris.draft, axis: .vertical).lineLimit(2...6).textFieldStyle(IrisTextFieldStyle())
                HStack { Button("Attach a file", systemImage: "paperclip") { iris.chooseFile() }; Button(iris.voice.listening ? "Stop microphone" : "Voice", systemImage: iris.voice.listening ? "stop.fill" : "mic") { iris.toggleVoice() }; Spacer(); if iris.busy { ProgressView().controlSize(.small); Button("Stop") { iris.cancelModel() } } else { Button("Send", systemImage: "arrow.up") { iris.ask() }.buttonStyle(.borderedProminent).disabled(!iris.canSend) } }
                if !iris.knowledge.enabled.isEmpty { Text("Personalized with approved knowledge sources. Relevant excerpts are sent only when you press Send.").font(.caption).foregroundStyle(.secondary) }
                Text("Local tools: /note your thought · /break. Computer actions follow your permission settings.").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("A useful detour").font(.system(size: 20, weight: .medium))
                HStack { TextField("Search the web in your browser", text: $webQuery).textFieldStyle(IrisTextFieldStyle()); Button("Open search") { iris.searchWeb(webQuery) }.disabled(webQuery.isEmpty) }
                Text("Opens your search in the default browser. Iris doesn't read your browser or send messages.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var sessions: some View {
        VStack(alignment: .leading, spacing: 24) {
            title("Your rhythm", "Time, well spent.", "A factual record of the time you set aside. No streaks to lose. No pressure to catch up.")
            let total = iris.data.history.filter { !$0.isBreak }.reduce(0) { $0 + $1.focusedSeconds }
            HStack(alignment: .firstTextBaseline, spacing: 8) { Text("\(Int(total / 60))").font(.system(size: 60, weight: .ultraLight, design: .monospaced)); Text("minutes of focus").foregroundStyle(.secondary) }
            if iris.data.history.isEmpty { Text("Your first session will appear here when you finish it.").foregroundStyle(.secondary) }
            ForEach(iris.data.history) { record in
                HStack(alignment: .top, spacing: 16) {
                    Image(systemName: record.isBreak ? "leaf" : (record.completed ? "checkmark.circle" : "circle.lefthalf.filled")).irisSymbolStyle().foregroundStyle(iris.accent).frame(width: 24)
                    VStack(alignment: .leading, spacing: 6) { Text(record.goal).font(.system(size: 15, weight: .medium)); Text(record.summary).font(.system(size: 12)).foregroundStyle(.secondary) }
                    Spacer(); Text(record.date, style: .date).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
                Divider()
            }
            if !iris.data.history.isEmpty { Button("Clear history", role: .destructive) { clearHistory = true } }
        }
    }
    private var settings: some View {
        VStack(alignment: .leading, spacing: 28) {
            title("Make Iris yours", "Quietly, your way.", "You choose what Iris knows, when she appears, and which parts of your Mac she can access.")
            GroupBox("About you") { VStack(alignment: .leading, spacing: 16) { TextField("Your name", text: pref(\.name)); IrisPicker("I use Iris as a", selection: pref(\.role), options: UserRole.allCases.map { .init(value: $0, title: $0.rawValue) }); TextField("Interests and subjects", text: pref(\.interests)); themePicker }.padding(12) }
            GroupBox("Knowledge source") { SourceSettings(iris: iris).padding(12) }
            GroupBox("Presence & timing") {
                VStack(alignment: .leading, spacing: 16) {
                    Toggle("Gentle session-completion peeks", isOn: pref(\.proactive))
                    Text("Opt-in only. At most one automatic peek per 30 minutes; no automatic peeks during quiet hours or detected full-screen work.").font(.caption).foregroundStyle(.secondary)
                    Toggle("Quiet hours", isOn: pref(\.quietEnabled))
                    HStack { IrisPicker("From", selection: pref(\.quietStart), display: String(format: "%02d:00", iris.preferences.quietStart), options: (0..<24).map { .init(value: $0, title: String(format: "%02d:00", $0)) }); IrisPicker("Until", selection: pref(\.quietEnd), display: String(format: "%02d:00", iris.preferences.quietEnd), options: (0..<24).map { .init(value: $0, title: String(format: "%02d:00", $0)) }) }.disabled(!iris.preferences.quietEnabled)
                    IrisPicker("Home display", selection: Binding<UInt32>(get: { iris.preferences.displayID ?? 0 }, set: { value in iris.setPreference { $0.displayID = value == 0 ? nil : value }; iris.reposition?() }), display: NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == iris.preferences.displayID })?.localizedName ?? "Automatic · built-in notch", options: [.init(value: UInt32(0), title: "Automatic", detail: "Prefer the built-in notch", symbol: "display")] + NSScreen.screens.map { .init(value: $0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0, title: $0.localizedName, symbol: "display") })
                    Text("Control ⌥ Space opens Iris. Hover or click the notch; swipe up to fold it away. Drag the top edge across to another display to reanchor.").font(.caption).foregroundStyle(.secondary)
                }.padding(12)
            }
            GroupBox("Privacy & permissions") { PermissionSettings(iris: iris).padding(12) }
            GroupBox("Connected devices") {
                VStack(alignment: .leading, spacing: 12) { Label("No companion connected", systemImage: "iphone.slash").font(.headline); Text("Mobile pairing is not available in this build. The security architecture specifies mutual confirmation, device-key pinning, encrypted transport and revocation. No relay is listening on your network.").font(.system(size: 12)).foregroundStyle(.secondary) }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }
            GroupBox("Available capabilities") {
                VStack(alignment: .leading, spacing: 16) { ForEach(IrisCapability.available) { capability in HStack(alignment: .top) { VStack(alignment: .leading, spacing: 4) { Text(capability.name).font(.system(size: 13, weight: .medium)); Text(capability.description).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(capability.risk.rawValue).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) } } }.padding(12)
            }
            Button("Open app testing", systemImage: "flask") { iris.workspaceSection = .testing }.buttonStyle(IrisActionStyle())
            Text("Iris · Native macOS\nLive camera, reminders, media integration, mobile pairing and autonomous computer control are not available in this build.").font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
    private var themePicker: some View {
        IrisPicker("Accent", selection: pref(\.theme), options: IrisTheme.allCases.map { .init(value: $0, title: $0.rawValue) })
    }
    private func pref<T>(_ keyPath: WritableKeyPath<Preferences, T>) -> Binding<T> { Binding(get: { iris.data.preferences[keyPath: keyPath] }, set: { value in iris.setPreference { $0[keyPath: keyPath] = value } }) }

}

struct SourceSettings: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var disconnect = false
    @State private var googleConfigured = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI provider").font(.system(size: 13, weight: .medium)).foregroundStyle(IrisDesign.secondary)
            IrisTabBar(items: KnowledgeSource.modelProviders.map(\.rawValue), selection: Binding(get: { iris.preferences.source.rawValue }, set: { value in
                guard let provider = KnowledgeSource(rawValue: value) else { return }
                iris.data.preferences.source = provider; iris.data.preferences.model = ""; iris.providerChanged(); iris.accounts.refreshStatus(provider)
            })).disabled(iris.accounts.authorizing || iris.testing)
            if iris.preferences.source == .openAI { Label("Recommended", systemImage: "checkmark.seal.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(IrisDesign.blue) }
            if iris.preferences.source == .local {
                TextField("Server URL", text: field(\.server)).textFieldStyle(IrisTextFieldStyle())
                Text("Start LM Studio's local server and load a chat model. Default: http://127.0.0.1:1234/v1. Remote servers require HTTPS.").font(.caption).foregroundStyle(.secondary)
            } else {
                Text(iris.preferences.source == .openAI ? "Use an eligible ChatGPT account, with permission to use your plan in Iris. Your ChatGPT conversations aren't shared." : "Use Google sign-in with Iris's registered Google app. Gemini API access and quota are separate from the Gemini consumer subscription.").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    if iris.accounts.authorizing { ProgressView().controlSize(.small); Button("Cancel sign-in") { iris.accounts.cancel() } }
                    else {
                        Button(iris.preferences.source == .openAI ? "Continue with ChatGPT" : (googleConfigured ? "Continue with Google" : "Set up Google sign-in…")) { signIn() }.buttonStyle(IrisActionStyle(primary: true))
                        Button("Disconnect") { disconnect = true }
                    }
                }
                Text(iris.accounts.status).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if iris.preferences.source == .gemini && !googleConfigured {
                    Text("The Google app registration is missing from this build. Contact the developer or use the advanced configuration below.").font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                if iris.availableModels.isEmpty { TextField("Model identifier · leave blank to discover", text: field(\.model)).textFieldStyle(IrisTextFieldStyle()) }
                else { IrisPicker("Model", selection: model, options: iris.availableModels.map { .init(value: $0, title: $0, symbol: "cpu") }) }
                Button(iris.testing ? "Connecting…" : "Reconnect") { iris.testConnection() }.disabled(iris.testing || iris.accounts.authorizing)
                if iris.testing { ProgressView().controlSize(.small) }
            }
            HStack(alignment: .top, spacing: 6) { Image(systemName: iris.preferences.providerVerified ? "checkmark.circle.fill" : "info.circle").irisSymbolStyle(); Text(iris.connectionResult).textSelection(.enabled) }.font(.caption).foregroundStyle(iris.preferences.providerVerified ? .green : .secondary)
            Text("Iris connects automatically. Model discovery does not send a test prompt. Your first question verifies a real response. Account tokens stay in this Mac’s Keychain.").font(.system(size: 10)).foregroundStyle(.secondary)
            if iris.preferences.source == .gemini {
                DisclosureGroup("Google troubleshooting") {
                    VStack(alignment: .leading, spacing: 8) { GoogleConnectionHelp(); Button("Import a local override…") { do { if try GoogleAppConfiguration.importFile() { googleConfigured = true } } catch { iris.error = error.localizedDescription } }; Link("Official Google setup", destination: URL(string: "https://ai.google.dev/gemini-api/docs/oauth")!) }.font(.caption).padding(.top, 8)
                }
            }
        }
        .onAppear { if !ProcessInfo.processInfo.arguments.contains("--iris-validation") { iris.accounts.refreshStatus(iris.preferences.source) }; googleConfigured = (try? GoogleAppConfiguration.read()) != nil }
        .alert("Disconnect this account?", isPresented: $disconnect) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) { do { try iris.accounts.disconnect(iris.preferences.source); iris.providerChanged() } catch { iris.error = error.localizedDescription } }
        } message: { Text("Saved tokens are removed from this Mac. You can revoke Iris's access in your provider account as well.") }
    }
    private func signIn() {
        let provider = iris.preferences.source
        Task {
            do {
                var googleID = ""
                if provider == .gemini {
                    if try GoogleAppConfiguration.read() == nil { guard try GoogleAppConfiguration.importFile() else { return } }
                    guard let config = try GoogleAppConfiguration.read() else { return }; googleID = config.clientID; googleConfigured = true
                }
                try await iris.accounts.signIn(source: provider, googleClientID: googleID)
                iris.providerChanged()
                iris.refreshConnection(immediate: true)
            } catch is CancellationError { iris.accounts.status = "Sign-in cancelled" }
            catch { iris.accounts.status = "Connection needs attention"; iris.error = error.localizedDescription }
        }
    }
    private var model: Binding<String> { Binding(get: { iris.preferences.model }, set: { value in iris.data.preferences.model = value; iris.providerChanged() }) }
    private func field(_ path: WritableKeyPath<Preferences, String>) -> Binding<String> { Binding(get: { iris.data.preferences[keyPath: path] }, set: { value in iris.data.preferences[keyPath: path] = value; iris.providerChanged() }) }
}

struct PermissionSettings: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var refreshed = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            permissionRow("Microphone", detail: "Only while you explicitly start voice input", granted: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized, url: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            permissionRow("Speech recognition", detail: "Apple recognition may send audio to Apple", granted: SFSpeechRecognizer.authorizationStatus() == .authorized, url: "x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition")
            ScreenRecordingPermissionRow()
            Toggle("Observe foreground application names", isOn: Binding(get: { iris.preferences.observeApps }, set: { value in iris.setPreference { $0.observeApps = value }; if let app = NSWorkspace.shared.frontmostApplication { iris.updateForeground(app) } }))
            Text("No window titles, keystrokes or background screenshots. Browser and sensitive-app screen capture is always excluded.").font(.caption).foregroundStyle(.secondary)
            if iris.preferences.observeApps {
                HStack { Text(iris.foregroundName).font(.caption); Spacer(); Button("Allow this app for screen reading") { if let id = iris.foregroundID, !ContextPolicy.blockedTokens.contains(where: { id.lowercased().contains($0) }) { iris.setPreference { if !$0.allowedCaptureApps.contains(id) { $0.allowedCaptureApps.append(id) } } } else { iris.error = "This application is protected and cannot be allowed for screen reading." } }.disabled(iris.foregroundID == nil) }
                ForEach(iris.preferences.allowedCaptureApps, id: \.self) { id in HStack { Text(id).font(.system(size: 10, design: .monospaced)); Spacer(); Button("Revoke") { iris.setPreference { $0.allowedCaptureApps.removeAll { $0 == id } } } } }
            }
            Text("Double Tap uses Accessibility to read and fill the focused text field when you invoke it. Manage it in Shortcuts.").font(.caption).foregroundStyle(.secondary)
            Button("Refresh permission status") { ScreenRecordingAccess.shared.refresh(); refreshed += 1 }.font(.caption)
        }.id(refreshed)
    }
    private func permissionRow(_ name: String, detail: String, granted: Bool, url: String) -> some View {
        HStack(alignment: .top) { Image(systemName: granted ? "checkmark.circle" : "lock.circle").irisSymbolStyle().foregroundStyle(granted ? .green : .secondary); VStack(alignment: .leading, spacing: 3) { Text(name).font(.system(size: 13, weight: .medium)); Text(detail).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Settings") { if let url = URL(string: url) { NSWorkspace.shared.open(url) } }.font(.caption) }
    }
}
