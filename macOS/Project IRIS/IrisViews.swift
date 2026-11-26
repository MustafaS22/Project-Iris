import SwiftUI
import AppKit

struct NotchSurface: View {
    @ObservedObject var iris: IrisOrchestrator
    var notchWidth: CGFloat
    var notchHeight: CGFloat
    var hasNotch: Bool
    var expandedWidth: CGFloat
    var canvasSize: CGSize
    var onSize: (CGSize) -> Void
    var onHover: (Bool) -> Void
    var onDrag: (CGPoint) -> Void
    @Environment(\.irisReduceMotion) private var reduceMotion
    @FocusState private var composeFocused: Bool
    @State private var endConfirmation = false
    @State private var showFocusEditor = false
    var body: some View {
        VStack(spacing: 0) {
            header
            if iris.expanded {
                VStack(alignment: .leading, spacing: 16) {
                    if let error = iris.error { status(error, symbol: "exclamationmark.circle", isError: true) }
                    else if let notice = iris.notice { status(notice, symbol: "checkmark.circle", isError: false) }
                    Group {
                        switch iris.tab {
                        case .focus:
                            if iris.data.session != nil || showFocusEditor { focusContent }
                            else { homeContent }
                        case .ask: askContent
                        case .agents: NotchAgentsView(iris: iris, store: iris.agents)
                        case .capture: captureContent
                        case .settings: quickSettings
                        case .welcome: askContent
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.horizontal, iris.tab == .settings ? 0 : 24).padding(.top, iris.tab == .settings ? 12 : 20).padding(.bottom, iris.tab == .settings ? 0 : 24)
                .transition(.opacity)
            }
        }
        .frame(width: iris.expanded ? (iris.tab == .settings ? max(1, canvasSize.width - 2 * (IrisNotchShape.shoulder + IrisNotchComputerGlow.margin)) : expandedWidth) : (notchWidth + 116))
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, IrisNotchShape.shoulder)
        .background(IrisNotchBackground(expanded: iris.expanded, accent: iris.accent))
        .clipShape(IrisNotchShape(bottomRadius: iris.expanded ? 26 : 14))
        .overlay {
            IrisNotchComputerGlow(shape: IrisNotchShape(bottomRadius: iris.expanded ? 26 : 14),
                                  phase: iris.computer.presentation, accent: iris.accent)
        }
        .contentShape(IrisNotchShape(bottomRadius: iris.expanded ? 26 : 14))
        .overlay(alignment: .bottom) {
            if !iris.expanded, let session = iris.data.session {
                Capsule().fill(iris.accent).frame(width: max(2, (notchWidth + 90) * session.progress(at: iris.now)), height: 2).padding(.bottom, 2).accessibilityHidden(true)
            }
        }
        .foregroundStyle(IrisDesign.text).preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: iris.expanded)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: iris.tab == .settings)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { onSize($0) }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .top)
        .background(IrisDismissShortcut(shortcuts: iris.shortcuts) {
            if iris.welcome.active { iris.voice.stop(); iris.voice.stopSpeaking(); iris.collapsePresence() }
            else if iris.tab == .settings { iris.tab = .focus }
            else { iris.voice.stop(); iris.collapsePresence() }
        }.frame(width: 0, height: 0))
        .alert("End this session?", isPresented: $endConfirmation) {
            Button("Keep focusing", role: .cancel) {}
            Button("End & save", role: .destructive) { iris.endSession() }
        } message: { Text("Your actual focused time will be saved in Sessions.") }
    }
    private var header: some View {
        HStack(spacing: 0) {
            // Keep one live avatar mounted so expansion preserves blink and cursor-gaze continuity.
            Button {
                if iris.computer.needsAttention { iris.computer.revealPermission() } else if iris.floatingActive { iris.returnToNotch?() }
                else { iris.togglePresence() }
            } label: {
                IrisAvatar(state: iris.state, color: iris.accent, size: 30, animated: true)
                    .frame(width: 48, height: notchHeight + 5)
            }.buttonStyle(.plain)
                .help(iris.computer.needsAttention ? "Show permission request" : iris.expanded ? "Collapse Iris" : "Open Iris · \(iris.shortcuts.label(.notch))")
            if iris.expanded {
                HStack(spacing: 2) {
                    mode(.focus, "house", "Home and focus")
                    mode(.ask, "bubble.left.and.bubble.right", "Chat with Iris")
                    mode(.capture, "square.and.pencil", "Capture a note")
                    mode(.agents, "person.2.fill", "Agents")
                }.padding(3).background(IrisDesign.surface, in: Capsule()).padding(.leading, 8)
            }
            Spacer(minLength: notchWidth)
            if iris.expanded {
                HStack(spacing: 4) {
                    Button { iris.showWorkspace() } label: { Image(systemName: "arrow.up.right.square").irisSymbolStyle().frame(width: 30, height: 30) }.help("Open workspace")
                    Button { iris.tab = iris.tab == .settings ? .focus : .settings; iris.notchPinned = true } label: {
                        Image(systemName: "gearshape.fill").irisSymbolStyle().frame(width: 30, height: 30)
                            .foregroundStyle(iris.tab == .settings ? iris.accent : IrisDesign.secondary)
                            .background(iris.tab == .settings ? IrisDesign.control : .clear, in: Circle())
                    }.help("Quick settings").accessibilityLabel("Quick settings").accessibilityAddTraits(iris.tab == .settings ? .isSelected : [])
                    Button { iris.collapsePresence() } label: { Image(systemName: "chevron.up").irisSymbolStyle().frame(width: 30, height: 30) }.help("Collapse Iris · Escape")
                }.buttonStyle(.plain).foregroundStyle(IrisDesign.secondary)
            } else if let activity = iris.activities.first {
                Text(activity.title).font(.system(size: 10, weight: .medium)).lineLimit(1).frame(width: 62)
            } else { Image(systemName: "sparkle").irisSymbolStyle().foregroundStyle(iris.accent).frame(width: 48) }
        }.padding(.horizontal, iris.expanded ? 16 : 6).frame(height: max(notchHeight + 5, iris.expanded ? 38 : 0))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 14).onEnded { value in
            if abs(value.translation.width) > 70 { onDrag(value.location) }
            else if value.translation.height < -20 { iris.collapsePresence() }
            else if value.translation.height > 15 { iris.notchPinned = true; iris.expanded = true }
        })
    }
    private func mode(_ tab: IrisOrchestrator.NotchTab, _ symbol: String, _ label: String) -> some View {
        Button { iris.tab = tab; iris.notchPinned = true } label: {
            Image(systemName: symbol).irisSymbolStyle().font(.system(size: 12, weight: .semibold)).frame(width: 32, height: 30)
                .foregroundStyle(iris.tab == tab ? IrisDesign.text : IrisDesign.secondary)
                .background(iris.tab == tab ? IrisDesign.control : .clear, in: Capsule())
        }.buttonStyle(.plain).help(label).accessibilityLabel(label).accessibilityAddTraits(iris.tab == tab ? .isSelected : [])
    }
    private var quickSettings: some View {
        NotchSettingsView(iris: iris)
            .frame(height: min(610, max(260, canvasSize.height - notchHeight - 90)))
    }
    private var homeContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                VStack(alignment: .leading, spacing: 7) {
                    Text(GreetingPolicy.text(at: timeline.date, name: iris.preferences.name)).font(.system(size: 24, weight: .semibold)).tracking(-0.5)
                    Text(timeline.date, format: .dateTime.weekday(.wide).month(.abbreviated).day()).font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                }
            }
            HStack(spacing: 12) {
                Button { iris.newConversation(); iris.tab = .ask; composeFocused = true } label: { Label("New question", systemImage: "plus.bubble").frame(maxWidth: .infinity) }.buttonStyle(IrisActionStyle(primary: true))
                Button { iris.toggleVoice() } label: { Image(systemName: "mic.fill").irisSymbolStyle().frame(width: 32, height: 32) }.buttonStyle(.plain).help("Speak to Iris").accessibilityLabel("Speak to Iris")
            }
            if let recent = iris.data.conversations?.max(by: { $0.updatedAt < $1.updatedAt }) {
                Button { iris.openConversation(recent); iris.tab = .ask; iris.notchPinned = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath").irisSymbolStyle().foregroundStyle(iris.accent)
                        VStack(alignment: .leading, spacing: 4) { Text("Continue your conversation").font(.system(size: 11)).foregroundStyle(IrisDesign.secondary); Text(recent.title).font(.system(size: 13, weight: .medium)).lineLimit(1) }
                        Spacer(); Image(systemName: "arrow.up.right").irisSymbolStyle().font(.caption).foregroundStyle(IrisDesign.secondary)
                    }.padding(14).background(IrisDesign.surface.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(.plain)
            }
            HStack(spacing: 12) {
                Button { showFocusEditor = true } label: { Label("Focus", systemImage: "timer").frame(maxWidth: .infinity) }
                Button { iris.tab = .capture; iris.notchPinned = true } label: { Label("Quick note", systemImage: "square.and.pencil").frame(maxWidth: .infinity) }
                Button { iris.showWorkspace(.library) } label: { Label("Library", systemImage: "folder").frame(maxWidth: .infinity) }
            }.buttonStyle(.plain).font(.system(size: 12)).padding(.vertical, 6)
            if let note = iris.data.notes.first {
                HStack(alignment: .top, spacing: 8) { Image(systemName: "note.text").irisSymbolStyle().foregroundStyle(iris.accent); Text(note.text).lineLimit(2); Spacer(); Button("All notes") { iris.showWorkspace(.knowledge) } }.font(.system(size: 11)).foregroundStyle(IrisDesign.secondary)
            }
            HStack(spacing: 7) {
                Circle().fill(iris.preferences.providerVerified ? iris.accent : .orange).frame(width: 5, height: 5)
                Text(iris.preferences.providerVerified ? "\(iris.preferences.source.rawValue) ready" : "Connect your AI to start chatting").font(.system(size: 11)).foregroundStyle(IrisDesign.secondary)
                Spacer()
                Button(iris.preferences.providerVerified ? "Settings" : "Set up") { iris.tab = .settings; iris.notchPinned = true }.font(.system(size: 11)).buttonStyle(.plain)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var focusContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let session = iris.data.session {
                HStack(alignment: .lastTextBaseline, spacing: 12) {
                    Text(iris.timeString(session.remaining(at: iris.now)))
                        .font(.system(size: 54, weight: .ultraLight, design: .monospaced)).tracking(-3).contentTransition(.numericText()).foregroundStyle(iris.accent)
                    Text(session.isRunning ? (session.isBreak ? "REST" : "FOCUS") : "PAUSED").font(.system(size: 10, weight: .medium)).tracking(2).foregroundStyle(IrisDesign.secondary)
                }
                ProgressView(value: session.progress(at: iris.now)).tint(iris.accent).accessibilityLabel("Session progress")
                HStack(spacing: 10) {
                    Button { iris.toggleSession() } label: { Label(session.isRunning ? "Pause" : "Resume", systemImage: session.isRunning ? "pause.fill" : "play.fill").frame(maxWidth: .infinity).padding(.vertical, 10) }
                        .buttonStyle(.plain).background(iris.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(iris.accent)
                    Button("End & save") { endConfirmation = true }.buttonStyle(.plain).foregroundStyle(IrisDesign.secondary).padding(.horizontal, 8)
                }
            } else {
                TextField("What deserves your attention?", text: $iris.goal).textFieldStyle(.plain).font(.system(size: 15)).padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    HStack(spacing: 8) {
                        ForEach([15, 25, 50], id: \.self) { minute in
                            Button("\(minute)m") { iris.minutes = minute }
                                .buttonStyle(.plain).font(.system(size: 12, weight: .medium, design: .monospaced)).padding(.horizontal, 11).padding(.vertical, 9)
                                .background(iris.minutes == minute ? iris.accent.opacity(0.16) : .white.opacity(0.05), in: Capsule()).foregroundStyle(iris.minutes == minute ? iris.accent : IrisDesign.secondary)
                        }
                    }
                    Spacer()
                    Stepper(value: $iris.minutes, in: 1...180) { Text("\(iris.minutes)m").font(.system(size: 11, design: .monospaced)) }.fixedSize().help("Custom duration")
                }
                Button { iris.startSession() } label: { HStack { Text("Make room for focus"); Spacer(); Image(systemName: "arrow.right").irisSymbolStyle() }.font(.system(size: 13, weight: .semibold)).padding(14).background(iris.accent, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(.black) }
                    .buttonStyle(.plain).disabled(iris.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                HStack {
                    Text("One goal. A quiet companion.").font(.system(size: 11)).foregroundStyle(IrisDesign.secondary)
                    Spacer()
                    Button("5 min break") { iris.startSession(isBreak: true) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(iris.accent)
                }
            }
        }
    }
    private var canSend: Bool { iris.canSend }
    private var askContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if iris.messages.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What's on your mind?").font(.system(size: 24, weight: .semibold)).tracking(-0.5)
                    Text("Work through an idea, ask about your knowledge, or attach a file.").font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
                }.padding(.vertical, 12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(iris.messages.suffix(8)) { message in
                                HStack {
                                    if message.role == "user" { Spacer(minLength: 40) }
                                    MessageContent(iris: iris, message: message, fontSize: 14)
                                        .padding(14).background(message.role == "user" ? IrisDesign.control : IrisDesign.surface, in: RoundedRectangle(cornerRadius: 16))
                                    if message.role != "user" { Spacer(minLength: 16) }
                                }.id(message.id)
                            }
                            if iris.busy { LiveResponseView(iris: iris, fontSize: 14) }
                        }
                    }.frame(maxHeight: 260)
                    .onChange(of: iris.liveReply) { _, _ in proxy.scrollTo("live-response", anchor: .bottom) }
                    .onChange(of: iris.messages.last?.text) { _, _ in if let id = iris.messages.last?.id { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
            ComputerActivityView(session: iris.computer, accent: iris.accent)
            ChatMentionComposer(iris: iris, compact: true)
            if !iris.actions.pending.isEmpty { Button("Review computer action") { iris.showWorkspace(.today) }.buttonStyle(IrisActionStyle(primary: true)) }
            HStack {
                Text(iris.preferences.source.rawValue).font(.system(size: 11)).foregroundStyle(IrisDesign.secondary)
                Spacer()
                if let answer = iris.messages.last(where: { $0.role == "assistant" }) {
                    Button(iris.voice.speaking || iris.voice.preparingSpeech ? "Stop reading" : "Read aloud") { iris.voice.speaking || iris.voice.preparingSpeech ? iris.voice.stopSpeaking() : iris.voice.speak(ResponsePresentation.visibleText(answer.text).components(separatedBy: "```iris-study")[0], identifier: iris.preferences.voiceID, rate: iris.preferences.speechRate ?? 0.49, provider: iris.preferences.speechProvider, server: iris.preferences.voiceBoxServer ?? VoiceBoxClient.defaultServer, profile: iris.preferences.voiceBoxProfile, speed: (iris.preferences.speechProvider) == "gemini" ? (iris.preferences.geminiSpeechSpeed ?? 1) : (iris.preferences.voiceBoxSpeed ?? 1), geminiVoice: iris.preferences.geminiVoice ?? GeminiSpeechClient.defaultVoice, geminiModel: iris.preferences.geminiSpeechModel ?? GeminiSpeechClient.defaultModel, geminiStyle: iris.preferences.geminiSpeechStyle ?? "Natural", geminiAuth: iris.preferences.geminiSpeechAuth ?? "apiKey", economy: iris.preferences.geminiSpeechEconomy ?? true) }.font(.system(size: 11))
                }
                Button("Full conversation") { iris.showWorkspace() }.font(.system(size: 11))
            }.buttonStyle(.plain)
        }
    }
    private var captureContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keep the thought. Stay in the flow.").font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
            TextField("A thought, a task, a tiny breakthrough…", text: $iris.noteDraft, axis: .vertical).lineLimit(3...5).textFieldStyle(.plain).font(.system(size: 14)).padding(14).background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                Button("\(iris.data.notes.count) saved notes") { iris.showWorkspace(.knowledge) }.foregroundStyle(IrisDesign.secondary)
                Spacer()
                Button { iris.saveNote() } label: { Label("Save on this Mac", systemImage: "plus") }.foregroundStyle(iris.accent).disabled(iris.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.buttonStyle(.plain).font(.system(size: 12))
        }
    }
    private func status(_ text: String, symbol: String, isError: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).irisSymbolStyle().foregroundStyle(isError ? .orange : iris.accent)
            ScrollView { Text(text).font(.system(size: 11)).lineSpacing(3).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }.frame(maxHeight: 60)
            Button { if isError { iris.error = nil } else { iris.notice = nil } } label: { Image(systemName: "xmark").irisSymbolStyle().font(.system(size: 10)).frame(width: 24, height: 24) }.buttonStyle(.plain).help("Dismiss")
        }.padding(10).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }
}
