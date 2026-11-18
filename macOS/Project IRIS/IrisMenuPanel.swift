import SwiftUI

enum IrisMenuAction {
    case ask(String), speak, type, notch, floating, hideFloating, workspace, history, settings, quit, dismiss
    case conversation(ChatConversation)
}

struct IrisMenuPanel: View {
    @ObservedObject var iris: IrisOrchestrator
    @ObservedObject private var voice: VoiceService
    @ObservedObject private var shortcuts: IrisShortcutStore
    let perform: (IrisMenuAction) -> Void
    @State private var prompt = ""
    @State private var note = ""
    @State private var editingNote = false
    @State private var noteSaved = false
    @FocusState private var promptFocused: Bool
    @Environment(\.irisReduceMotion) private var reduceMotion

    init(iris: IrisOrchestrator, perform: @escaping (IrisMenuAction) -> Void) {
        self.iris = iris; self.voice = iris.voice; self.shortcuts = iris.shortcuts; self.perform = perform
    }
    private var ready: Bool { !iris.needsOnboarding && !iris.onboardingPresented }
    private var status: String {
        if !ready { return "Let’s get you set up" }
        if voice.listening { return "Listening to you" }
        if iris.busy { return iris.requestPhase.isEmpty ? "Working on your request" : iris.requestPhase }
        if voice.speaking { return "Speaking" }
        if !iris.online { return "You’re offline" }
        return "Here when you need me"
    }
    private var recent: [ChatConversation] { Array((iris.data.conversations ?? []).sorted { $0.updatedAt > $1.updatedAt }.prefix(2)) }
    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if ready {
                        if !iris.draft.isEmpty || !iris.attachments.isEmpty {
                            Button("Continue your unfinished draft", systemImage: "square.and.pencil") { perform(.workspace) }
                                .buttonStyle(IrisMenuButtonStyle(accent: iris.accent))
                        } else { composer }
                        HStack(spacing: 10) {
                            Button { perform(.speak) } label: {
                                Label("Speak to Iris", systemImage: "waveform").frame(maxWidth: .infinity)
                            }.buttonStyle(IrisMenuButtonStyle(accent: iris.accent, primary: true)).help(shortcuts.label(.floatingVoice))
                            Button { perform(.type) } label: { Image(systemName: "keyboard").frame(width: 28) }
                                .buttonStyle(IrisMenuButtonStyle(accent: iris.accent)).help("Type to floating Iris · \(shortcuts.label(.floatingText))")
                                .accessibilityLabel("Type to floating Iris")
                        }
                        if iris.busy || voice.speaking || voice.listening {
                            Button {
                                if iris.busy { iris.cancelModel() }
                                voice.stop(); voice.stopSpeaking()
                            } label: { Label("Stop current activity", systemImage: "stop.circle.fill").font(.system(size: 12, weight: .medium)) }
                            .buttonStyle(.plain).foregroundStyle(IrisDesign.secondary)
                        }
                    } else {
                        Text("Your assistant, one click away.").font(.system(size: 17, weight: .semibold))
                        Text("Finish setting up Iris to talk, capture ideas and get a hand on your Mac.").font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
                        Button("Finish setup") { perform(.workspace) }.buttonStyle(IrisMenuButtonStyle(accent: iris.accent, primary: true))
                    }
                    Divider().overlay(.white.opacity(0.04))
                    HStack(spacing: 8) {
                        destination(iris.expanded ? "Close notch" : "Open notch", icon: "macbook", action: .notch)
                        destination(iris.floatingActive ? "Hide avatar" : "Float Iris", icon: "sparkle", action: iris.floatingActive ? .hideFloating : .floating)
                        destination("Workspace", icon: "rectangle.split.2x1.fill", action: .workspace)
                    }
                    if ready {
                        focus
                        capture
                        if !recent.isEmpty {
                            HStack {
                                sectionLabel("PICK UP WHERE YOU LEFT OFF")
                                Spacer()
                                Button("All chats") { perform(.history) }.font(.system(size: 11, weight: .medium)).buttonStyle(.plain).foregroundStyle(iris.accent)
                            }
                            VStack(spacing: 2) {
                                ForEach(recent) { chat in
                                    Button { perform(.conversation(chat)) } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: "bubble.left.fill").foregroundStyle(iris.accent.opacity(0.8)).font(.system(size: 12))
                                            Text(chat.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                            Spacer(minLength: 4)
                                            Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(IrisDesign.secondary)
                                        }.padding(.vertical, 9).padding(.horizontal, 10).contentShape(Rectangle())
                                    }.buttonStyle(IrisMenuRowStyle())
                                }
                            }
                        }
                    }
                }.padding(.horizontal, 18).padding(.bottom, 18)
            }.scrollIndicators(.hidden)
            footer
        }
        .frame(width: 360, height: 580)
        .background {
            ZStack(alignment: .topLeading) {
                Color(white: 0.075)
                RadialGradient(colors: [iris.accent.opacity(0.10), .clear], center: .topLeading, startRadius: 0, endRadius: 260)
            }
        }
        .foregroundStyle(IrisDesign.text).preferredColorScheme(.dark)
        .onAppear { promptFocused = true }
        .onExitCommand { perform(.dismiss) }
    }
    private var header: some View {
        HStack(spacing: 12) {
            IrisAvatar(state: iris.state, color: iris.accent, size: 43, animated: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Iris").font(.system(size: 21, weight: .bold))
                HStack(spacing: 5) {
                    Circle().fill(iris.online ? iris.accent : Color.orange).frame(width: 5, height: 5)
                    Text(status).font(.system(size: 11)).lineLimit(1)
                }.foregroundStyle(IrisDesign.secondary)
            }
            Spacer()
            Button { perform(.settings) } label: {
                Image(systemName: "slider.horizontal.3").font(.system(size: 14, weight: .semibold)).frame(width: 30, height: 30)
            }.buttonStyle(IrisMenuRowStyle()).help("Settings").accessibilityLabel("Iris settings")
        }.padding(18)
    }
    private var composer: some View {
        HStack(spacing: 8) {
            TextField("What can I help with?", text: $prompt).textFieldStyle(.plain)
                .font(.system(size: 13)).focused($promptFocused).onSubmit(send)
                .accessibilityLabel("Ask Iris from the menu bar")
            Button(action: send) {
                Image(systemName: "arrow.up").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.black.opacity(0.85))
                    .frame(width: 27, height: 27).background(iris.accent, in: Circle())
            }.buttonStyle(.plain).disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || iris.busy)
                .opacity(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || iris.busy ? 0.35 : 1).accessibilityLabel("Send to Iris")
        }.padding(.horizontal, 12).padding(.vertical, 11)
            .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(promptFocused ? iris.accent.opacity(0.55) : .white.opacity(0.12)))
    }
    private var focus: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "timer").font(.system(size: 17, weight: .semibold)).foregroundStyle(iris.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text(iris.data.session?.goal ?? "A little room to focus").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if let session = iris.data.session {
                        Text("\(iris.timeString(session.remaining(at: iris.now))) · \(session.isRunning ? "Focusing" : "Paused")").font(.system(size: 11, design: .monospaced)).foregroundStyle(IrisDesign.secondary)
                    } else { Text("25 minutes. One thing at a time.").font(.system(size: 11)).foregroundStyle(IrisDesign.secondary) }
                }
                Spacer(minLength: 0)
                if let session = iris.data.session {
                    Button { iris.toggleSession() } label: { Image(systemName: session.isRunning ? "pause.fill" : "play.fill").frame(width: 24, height: 26) }
                        .buttonStyle(.plain).accessibilityLabel(session.isRunning ? "Pause focus" : "Resume focus")
                    Button { iris.endSession() } label: { Image(systemName: "stop.fill").font(.system(size: 10)).frame(width: 20, height: 26) }.buttonStyle(.plain).accessibilityLabel("End focus session")
                } else {
                    Button("Start") { if iris.goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { iris.goal = "One thing at a time" }; iris.minutes = 25; iris.startSession() }
                        .font(.system(size: 11, weight: .semibold)).buttonStyle(IrisMenuButtonStyle(accent: iris.accent))
                }
            }
            if let session = iris.data.session {
                ProgressView(value: session.progress(at: iris.now)).tint(iris.accent).controlSize(.mini)
            }
        }.padding(13).background(iris.accent.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(iris.accent.opacity(0.12)))
    }
    private var capture: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { editingNote.toggle(); noteSaved = false }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: noteSaved ? "checkmark.circle.fill" : "square.and.pencil").foregroundStyle(iris.accent)
                    Text(noteSaved ? "Saved to your quick notes" : "Catch a thought").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Image(systemName: editingNote ? "chevron.up" : "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(IrisDesign.secondary)
                }.padding(.vertical, 7).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if editingNote {
                TextField("Don’t lose that idea…", text: $note, axis: .vertical).lineLimit(2...3).textFieldStyle(.plain).font(.system(size: 12))
                    .padding(10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10)).accessibilityLabel("Quick note")
                HStack {
                    Text("Saved locally on this Mac").font(.system(size: 10)).foregroundStyle(IrisDesign.secondary)
                    Spacer()
                    Button("Save note") {
                        let previousDraft = iris.noteDraft
                        iris.noteDraft = note; iris.saveNote()
                        let saved = iris.noteDraft.isEmpty
                        iris.noteDraft = previousDraft
                        if saved { note = ""; noteSaved = true; editingNote = false }
                    }.font(.system(size: 11, weight: .semibold)).buttonStyle(IrisMenuButtonStyle(accent: iris.accent))
                        .disabled(note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let error = iris.error { Text(error).font(.system(size: 11)).foregroundStyle(.orange) }
            }
        }
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Text(iris.preferences.source.rawValue).font(.system(size: 10, weight: .medium)).foregroundStyle(IrisDesign.secondary)
            Spacer()
            Text("Iris \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")").font(.system(size: 10)).foregroundStyle(IrisDesign.secondary.opacity(0.7))
            Button { perform(.quit) } label: { Image(systemName: "power").font(.system(size: 12)).frame(width: 28, height: 28) }
                .buttonStyle(IrisMenuRowStyle()).help("Quit Iris").accessibilityLabel("Quit Iris")
        }.padding(.horizontal, 18).padding(.vertical, 8).background(.black.opacity(0.15))
    }
    private func sectionLabel(_ text: String) -> some View { Text(text).font(.system(size: 9, weight: .semibold)).tracking(1.1).foregroundStyle(IrisDesign.secondary.opacity(0.7)) }
    private func destination(_ title: String, icon: String, action: IrisMenuAction) -> some View {
        Button { perform(action) } label: {
            VStack(spacing: 7) { Image(systemName: icon).font(.system(size: 15, weight: .semibold)); Text(title).font(.system(size: 10, weight: .medium)) }
                .frame(maxWidth: .infinity).padding(.vertical, 12).contentShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(IrisMenuRowStyle())
    }
    private func send() {
        let value = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !iris.busy, iris.draft.isEmpty, iris.attachments.isEmpty else { return }
        prompt = ""; perform(.ask(value))
    }
}

private struct IrisMenuButtonStyle: ButtonStyle {
    let accent: Color
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 10)
            .foregroundStyle(primary ? Color.black.opacity(0.85) : accent)
            .background(primary ? accent : accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
private struct IrisMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { MenuRow(label: configuration.label, pressed: configuration.isPressed) }
    private struct MenuRow<Label: View>: View {
        let label: Label
        let pressed: Bool
        @State private var hovered = false
        var body: some View { label.background(.white.opacity(pressed ? 0.10 : hovered ? 0.055 : 0), in: RoundedRectangle(cornerRadius: 11)).onHover { hovered = $0 } }
    }
}
