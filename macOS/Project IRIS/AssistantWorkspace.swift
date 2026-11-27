import SwiftUI
import AppKit
import AVFoundation

struct AssistantHome: View {
    @ObservedObject var iris: IrisOrchestrator
    @Environment(\.irisReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                IrisAvatar(state: iris.state, color: iris.accent, size: 68, animated: true, desktop: true, isWriting: iris.busy)
                    .modifier(ComputerAvatarGlow(phase: iris.computer.presentation, accent: iris.accent))
                    .onTapGesture { iris.computer.revealPermission() }
                    .frame(width: 88, height: 88)
                if iris.messages.isEmpty {
                    VStack(spacing: 8) {
                        Text(iris.voice.listening ? "I'm listening" : iris.preferences.personality.greeting)
                            .font(.system(size: 27, weight: .semibold)).tracking(-0.5)
                        Text(iris.voice.listening ? "Speak naturally. Pause when you're done." : "Ask, create, or bring your knowledge into the conversation.")
                            .font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
                    }.transition(.opacity.combined(with: .move(edge: .top)))
                }
            }.fixedSize(horizontal: false, vertical: true).padding(.top, 16)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: iris.messages.isEmpty)
            if let error = iris.error {
                HStack { Image(systemName: "exclamationmark.circle").irisSymbolStyle(); Text(error).font(.caption); Spacer(); Button("Dismiss") { iris.error = nil } }.padding(12).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if iris.messages.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("Type @ to choose a source or a tool.").font(.system(size: 13)).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 10) {
                                    quickMention("Website", "globe", "@website ")
                                    quickMention("Document", "doc.richtext", "@document ")
                                    quickMention("Use a source", "at", "@")
                                }
                            }.padding(.vertical, 30)
                        }
                        ForEach(iris.messages) { message in
                            HStack(alignment: .top, spacing: 12) {
                                if message.role == "user" { Spacer(minLength: 60) }
                                else { IrisAvatar(state: .idle, color: iris.accent, size: 26) }
                                MessageContent(iris: iris, message: message, fontSize: 15)
                                    .padding(16)
                                    .background {
                                        RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: message.role == "user" ? [iris.accent.opacity(0.19), iris.accent.opacity(0.07)] : [IrisDesign.surface, iris.accent.opacity(0.035)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    }
                                    .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(message.role == "user" ? iris.accent.opacity(0.17) : Color.white.opacity(0.055), lineWidth: 1) }
                                if message.role != "user" { Spacer(minLength: 28) }
                            }.id(message.id)
                        }
                        ActionReview(iris: iris)
                        if !iris.actions.result.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Label("Local result", systemImage: "lock.doc").font(.headline)
                                ScrollView { Text(iris.actions.result).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 180)
                                HStack { Button("Attach to next question") { iris.attachments = [.init(name: "Computer action result", text: iris.actions.result)] }; Button("Clear") { iris.actions.result = "" } }.font(.caption)
                            }.padding(18).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 16))
                        }
                        if iris.busy { LiveResponseView(iris: iris) }
                    }.padding(.vertical, 8)
                }.onChange(of: iris.activeCreation) { _, kind in if kind != nil { proxy.scrollTo("live-response", anchor: .bottom) } }.onChange(of: iris.liveReply) { _, _ in proxy.scrollTo("live-response", anchor: .bottom) }.onChange(of: iris.messages.count) { _, _ in if let last = iris.messages.last { proxy.scrollTo(last.id, anchor: .bottom) } }
            }.frame(minHeight: 0, maxHeight: .infinity).layoutPriority(1)
            ChatMentionComposer(iris: iris)

        }.dropDestination(for: URL.self) { urls, _ in
            guard !iris.busy, !iris.contextBusy else { return false }
            iris.attachFiles(urls); return !urls.isEmpty
        }.padding(.horizontal, 40).padding(.bottom, 24).frame(maxWidth: 920).frame(maxWidth: .infinity)
    }
    private func quickMention(_ title: String, _ symbol: String, _ prompt: String) -> some View {
        Button { iris.draft = prompt } label: { Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 10).background(iris.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 9)) }.buttonStyle(.plain)
    }

}

struct ActionReview: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var selected: AssistantAction?
    var body: some View {
        ComputerActivityView(session: iris.computer, accent: iris.accent)
        ForEach(iris.actions.pending) { action in
            VStack(alignment: .leading, spacing: 12) {
                Label("Review computer action", systemImage: "hand.raised").font(.headline)
                Text(action.displayName).font(.system(size: 13, weight: .medium))
                Text(action.path ?? action.target ?? "Selected folder").font(.caption).textSelection(.enabled)
                Button("Review…") { selected = action }.disabled(iris.busy).buttonStyle(IrisActionStyle(primary: true))
                Button("Dismiss") { iris.actions.pending.removeAll { $0.id == action.id } }.buttonStyle(.plain).font(.caption)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 16))
        }
        .sheet(item: $selected) { action in
            VStack(alignment: .leading, spacing: 18) {
                Text(action.type == "writeFile" ? "Review file changes" : "Review action").font(.title2.bold())
                Text(action.path ?? action.target ?? "Folder contents").textSelection(.enabled)
                if action.type == "computerTask" {
                    Text("Starting shares the relevant visible app’s interface text with your selected AI during this task. Images are off unless you enable task screenshots in Computer settings. Excluded apps stay blocked. Each consequential input or external tool is reviewed separately. Escape stops the task. Manual input refreshes the observation.").font(.callout).foregroundStyle(IrisDesign.secondary)
                }
                if let browser = action.browser { Label(browser, systemImage: "globe") }
                if let folder = iris.actions.folders.first(where: { $0.id == action.folder || $0.name == action.folder }) { Label(folder.name, systemImage: "folder.fill") }
                if let command = try? iris.actions.commandPreview(action) {
                    Text("Terminal command").font(.headline)
                    Text(command).font(.system(size: 12, design: .monospaced)).textSelection(.enabled).padding(12).background(.black, in: RoundedRectangle(cornerRadius: 10))
                    Text("This runs outside Iris's sandbox with your normal account access. Project scripts and dependency installation can execute code. Only run projects you trust. A server keeps running until you stop it with Control-C in Terminal.").font(.caption).foregroundStyle(.orange)
                }
                if action.type == "generateImage" { Text(ImageGenerationService.reviewDescription).font(.caption).foregroundStyle(.orange) }
                if action.type == "createDocument" { Text("Creates a real document locally from the content below. Replaces the destination if it exists. PDF and RTF preserve Unicode and basic Markdown styling; use HTML for fully typeset LaTeX.").font(.caption).foregroundStyle(IrisDesign.secondary) }
                if action.type == "playSpotifyPlaylist" { Text("Spotify will open and receive a playback request for this playlist. macOS may ask for Automation permission.").font(.caption) }
                if let content = action.content { ScrollView { Text(content).font(.system(size: 13, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(minHeight: 180) }
                Text(action.type == "writeFile" ? "Saving replaces the entire contents if this file already exists. Check the path and text before applying." : "Only the action shown here will run. File contents stay local until you explicitly attach and send them.").font(.caption).foregroundStyle(IrisDesign.secondary)
                HStack { Button("Cancel") { selected = nil }; Spacer(); Button(action.type == "generateImage" ? "Generate image" : action.type == "createDocument" ? "Create document" : action.type == "writeFile" ? "Apply file changes" : "Run this action") { iris.perform(action); selected = nil }.buttonStyle(IrisActionStyle(primary: true)) }
            }.padding(28).frame(width: 600).background(IrisDesign.canvas).preferredColorScheme(.dark)
        }
    }
}

struct AssistantSettingsView: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var section = "Appearance"
    init(iris: IrisOrchestrator, initialSection: String = "Appearance") { self.iris = iris; self._section = State(initialValue: initialSection) }
    @State private var search = ""
    private let groups: [(String, [String])] = [
        ("Personal", ["Appearance", "Personality", "Voice", "Language", "Memory", "Accessibility"]),
        ("Assistant", ["AI", "Live data", "Creation", "Connections"]),
        ("Your Mac", ["Computer", "MCP", "Shortcuts", "Privacy"]),
        ("Support", ["Updates", "App testing"])
    ]
    private func info(_ key: String) -> (title: String, symbol: String, detail: String) {
        switch key {
        case "Updates": return ("Updates", "arrow.triangle.2.circlepath", "Check, download and install newer Iris versions")
        case "Language": return ("Languages", "globe", "Chat, voice replies and speech recognition")
        case "Memory": return ("Memory", "brain", "Details you ask Iris to remember")
        case "Accessibility": return ("Accessibility", "accessibility", "Motion, contrast, reading and speech")
        case "Appearance": return ("Appearance", "paintpalette.fill", "Themes, app icons, menu bar and your name")
        case "Personality": return ("Personality", "face.smiling.fill", "Character, tone and conversation previews")
        case "Voice": return ("Voice & speech", "waveform", "Voices, previews, speech provider and playback")
        case "AI": return ("AI providers", "sparkles", "Models, accounts, API keys and local AI")
        case "Live data": return ("Live information", "sun.max.fill", "Weather, location, date and time")
        case "Creation": return ("Image generation", "photo.fill", "Image provider and generation API key")
        case "Connections": return ("Connections", "point.3.connected.trianglepath.dotted", "Connect apps and manage knowledge sources")
        case "MCP": return ("MCP connections", "puzzlepiece.extension.fill", "Connect trusted tools, APIs and browser automation")
        case "Computer": return ("Computer & files", "desktopcomputer", "Floating Iris, browser, folders and computer actions")
        case "Shortcuts": return ("Shortcuts", "command", "Keyboard shortcuts and Double Tap")
        case "Privacy": return ("Privacy & access", "hand.raised.fill", "Screen Recording, microphone and macOS permissions")
        default: return ("App testing", "ladybug.fill", "Replay onboarding and test Iris’s surfaces")
        }
    }
    private func matches(_ key: String) -> Bool {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let item = info(key)
        return term.isEmpty || "\(key) \(item.title) \(item.detail)".localizedCaseInsensitiveContains(term)
    }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(IrisDesign.secondary)
                    TextField("Find a page", text: $search).textFieldStyle(.plain).font(.system(size: 12)).accessibilityLabel("Find a settings page")
                    if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help("Clear search") }
                }.padding(9).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(groups, id: \.0) { group in
                            let pages = group.1.filter { matches($0) }
                            if !pages.isEmpty {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(group.0).font(.system(size: 10, weight: .semibold)).foregroundStyle(IrisDesign.secondary).padding(.leading, 10).padding(.bottom, 5)
                                    ForEach(pages, id: \.self) { key in
                                        Button { section = key } label: {
                                            HStack(spacing: 9) {
                                                Image(systemName: info(key).symbol).font(.system(size: 13, weight: .medium)).frame(width: 18).foregroundStyle(section == key ? iris.accent : IrisDesign.secondary)
                                                Text(info(key).title).font(.system(size: 12, weight: section == key ? .semibold : .regular)).lineLimit(1)
                                                Spacer(minLength: 0)
                                            }.padding(.horizontal, 10).frame(height: 32)
                                                .background(section == key ? iris.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                                                .contentShape(Rectangle())
                                        }.buttonStyle(.plain).help(info(key).detail).accessibilityAddTraits(section == key ? .isSelected : [])
                                    }
                                }
                            }
                        }
                        if !groups.flatMap({ $0.1 }).contains(where: matches) { Text("No matching pages. Try ‘voice’, ‘files’ or ‘permissions’.").font(.caption).foregroundStyle(IrisDesign.secondary).padding(10) }
                    }
                }.scrollIndicators(.automatic)
                IrisVersionLabel().font(.caption).foregroundStyle(IrisDesign.secondary)
            }.padding(16).frame(width: 210).frame(maxHeight: .infinity).background(IrisDesign.sidebar.opacity(0.65))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(info(section).title).font(.system(size: 22, weight: .semibold)).tracking(-0.3)
                    Text(info(section).detail).font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                }.padding(.horizontal, 28).padding(.vertical, 22)
                Divider().opacity(0.5)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            Group {
                switch section {
                case "Updates": IrisUpdatesView(updates: iris.updates, accent: iris.accent)
                case "Memory": MemorySettingsView(iris: iris)
                case "Language": LanguageSettingsView()
                case "Accessibility": AccessibilitySettingsView(iris: iris)
                case "Appearance": appearance
                case "Personality": PersonalitySettingsView(iris: iris)
                case "Voice": voice
                case "Live data": LiveDataSettings(iris: iris)
                case "AI": SourceSettings(iris: iris)
                case "Creation": ImageProviderSettings()
                case "MCP": MCPSettingsView(session: iris.computer)
                case "Computer": computer
                case "Shortcuts": ShortcutSettingsView(shortcuts: iris.shortcuts)
                case "Connections": KnowledgeConnectionsView(iris: iris, showsHeading: false)
                case "App testing": AppTestingView(iris: iris, openAISettings: { section = "AI" }, openConnections: { section = "Connections" }, showsHeading: false)
                default: PermissionSettings(iris: iris)
                }
                            }
                        }.id("settings-top").padding(28).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
                    }.onChange(of: section) { _, _ in proxy.scrollTo("settings-top", anchor: .top) }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var appearance: some View { IrisAppearanceSettings(iris: iris) }
    private var voice: some View { VoiceSettingsView(iris: iris) }
    private var computer: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) { Image(systemName: "macwindow.badge.plus").irisSymbolStyle().font(.system(size: 48)).foregroundStyle(iris.accent); VStack(alignment: .leading, spacing: 6) { Text("A hand on your Mac").font(.title2.bold()); Text("Open apps and links. Read, create and edit files in folders you choose.").foregroundStyle(IrisDesign.secondary) } }
            HStack(spacing: 16) {
                IrisAvatar(state: .idle, color: iris.accent, size: 36, desktop: true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Floating Iris").font(.headline)
                    Text("\(iris.shortcuts.label(.floatingVoice)) to speak · \(iris.shortcuts.label(.floatingText)) to type. Click Iris for controls; enable app guidance to point at visible controls.").font(.caption).foregroundStyle(IrisDesign.secondary)
                }
                Spacer()
                VStack(spacing: 10) { Button("Summon & speak") { iris.openFloating?() }; Button("Type instead") { iris.openFloatingTyping?() } }.buttonStyle(IrisActionStyle())
            }
            Text("Drag Iris to move it. Click for voice, chat and roaming controls. Drawings never intercept your clicks; clear them with the eraser. Screen contents are not shared automatically.").font(.caption).foregroundStyle(IrisDesign.secondary)
            Divider()
            Button("Privacy & macOS permissions", systemImage: "hand.raised.fill") { section = "Privacy" }.buttonStyle(IrisActionStyle())
            ComputerPermissionSettings(iris: iris)
            VStack(alignment: .leading, spacing: 8) {
                IrisPicker("Open links and searches in", selection: Binding(get: { iris.preferences.preferredBrowser ?? "" }, set: { value in iris.setPreference { $0.preferredBrowser = value } }), display: BrowserService.applications.first(where: { $0.id == iris.preferences.preferredBrowser })?.name ?? ((iris.preferences.preferredBrowser ?? "").isEmpty ? "Default browser" : "Unavailable browser"), options: [.init(value: "", title: "Default browser", detail: "Follow macOS", symbol: "globe")] + BrowserService.applications.map { .init(value: $0.id, title: $0.name, symbol: "globe") })
                Text("You can also ask for a specific browser: “Search for Swift tutorials in Safari.”").font(.caption).foregroundStyle(IrisDesign.secondary)
            }
            Divider()
            Text("Allowed folders").font(.headline)
            HStack { Button("Downloads") { iris.actions.grant(.downloadsDirectory) }; Button("Documents") { iris.actions.grant(.documentDirectory) }; Button("Applications") { iris.actions.grant(.applicationDirectory) }; Button("Other folder…") { iris.actions.grant() } }.buttonStyle(IrisActionStyle())
            ForEach(iris.actions.folders) { folder in HStack { Image(systemName: "folder.fill").irisSymbolStyle().foregroundStyle(iris.accent); Text(folder.name); Spacer(); Button("Revoke") { iris.actions.revoke(folder.id) } }.padding(16).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 12)) }
            if iris.actions.folders.isEmpty { Label("Choose a folder to get started", systemImage: "folder.badge.plus").foregroundStyle(IrisDesign.secondary) }
            if let failure = iris.actions.failure { Text(failure).foregroundStyle(.orange) }
            Text("Your permission choice applies to supported computer actions. File reads stay local; only attach and send content you want your model to receive. Spotify playback, LM Studio hosting and project tasks use macOS app integrations. macOS may request Automation access. General cross-app clicking and file deletion are not supported.").font(.caption).foregroundStyle(IrisDesign.secondary)
        }
    }
    private func pref<T>(_ path: WritableKeyPath<Preferences,T>) -> Binding<T> { Binding(get: { iris.preferences[keyPath:path] }, set: { value in iris.setPreference { $0[keyPath:path] = value } }) }
    private func color(_ theme: IrisTheme) -> Color { theme.color(customHue: iris.preferences.customHue ?? 0.5) }
}
