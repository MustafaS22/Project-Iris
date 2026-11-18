import SwiftUI

/// Settings stay attached to the notch; the regular chat surface keeps its compact width.
struct NotchSettingsView: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var section = Section.general
    @Environment(\.irisReduceMotion) private var reduceMotion
    private enum Section: String, CaseIterable {
        case general = "General", appearance = "Appearance", personality = "Personality", voice = "Voice", intelligence = "AI connection", computer = "Computer", shortcuts = "Shortcuts"
        var symbol: String {
            switch self {
            case .general: "slider.horizontal.3"
            case .appearance: "paintpalette"
            case .personality: "sparkles"
            case .voice: "waveform"
            case .intelligence: "cpu"
            case .computer: "desktopcomputer"
            case .shortcuts: "command"
            }
        }
        var detail: String {
            switch self {
            case .general: "How Iris fits into your day."
            case .appearance: "A familiar face, in your colors."
            case .personality: "Choose the character you click with."
            case .voice: "How Iris listens and speaks."
            case .intelligence: "The model behind your assistant."
            case .computer: "Choose what Iris can do on your Mac."
            case .shortcuts: "Iris, a few keys away."
            }
        }
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 9) { IrisBrandMark(color: iris.accent).frame(width: 28, height: 28); Text("Settings").font(.system(size: 17, weight: .semibold)) }.padding(.horizontal, 10)
                    ScrollView {
                        VStack(spacing: 5) {
                            ForEach(Section.allCases, id: \.self) { item in
                                Button { section = item } label: {
                                    HStack(spacing: 11) {
                                        Image(systemName: item.symbol).irisSymbolStyle().frame(width: 19)
                                        Text(item.rawValue).font(.system(size: 13, weight: section == item ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.9)
                                        Spacer(minLength: 0)
                                    }.foregroundStyle(section == item ? IrisDesign.text : IrisDesign.secondary)
                                        .padding(.horizontal, 12).padding(.vertical, 13)
                                        .background(section == item ? IrisDesign.control : .clear, in: RoundedRectangle(cornerRadius: 10))
                                        .contentShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain).accessibilityAddTraits(section == item ? .isSelected : [])
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Button { iris.showWorkspace(.settings) } label: { Label("Desktop settings", systemImage: "arrow.up.right.square").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(IrisDesign.secondary)
                        IrisVersionLabel()
                    }.padding(.horizontal, 10)
                }.padding(.horizontal, 14).padding(.vertical, 24).frame(width: geometry.size.width < 600 ? 176 : 205)
                Divider().overlay(Color.white.opacity(0.06))
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(section.rawValue).font(.system(size: 25, weight: .semibold)).tracking(-0.5)
                            Text(section.detail).font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
                        }
                        content
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(geometry.size.width < 720 ? 20 : 30)
                }.id(section)
            }.background(LinearGradient(colors: [IrisDesign.sidebar, IrisDesign.canvas], startPoint: .topLeading, endPoint: .bottomTrailing))
        }.environment(\.irisControlAccent, iris.accent).tint(iris.accent)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: section)
    }
    @ViewBuilder private var content: some View {
        switch section {
        case .general:
            group("About you") {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Your name").font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                    TextField("What should Iris call you?", text: pref(\.name)).textFieldStyle(IrisTextFieldStyle())
                }
            }
            group("Presence") {
                settingToggle("Listen when summoned", isOn: Binding(get: { iris.preferences.listenOnSummon ?? true }, set: { value in iris.setPreference { $0.listenOnSummon = value } }))
                Divider()
                settingToggle("Gentle focus-session peeks", isOn: pref(\.proactive))
                Divider()
                settingToggle("Quiet hours", isOn: pref(\.quietEnabled))
                if iris.preferences.quietEnabled {
                    HStack(spacing: 14) {
                        IrisPicker("From", selection: pref(\.quietStart), options: (0..<24).map { .init(value: $0, title: String(format: "%02d:00", $0)) })
                        IrisPicker("Until", selection: pref(\.quietEnd), options: (0..<24).map { .init(value: $0, title: String(format: "%02d:00", $0)) })
                    }
                }
            }
            group("Welcome tour") {
                Text("Walk through Iris again without clearing your chats or connections.").font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                Button("Replay onboarding", systemImage: "play") { iris.restartOnboarding?() }.buttonStyle(IrisActionStyle())
            }
        case .appearance:
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                ForEach(IrisTheme.allCases, id: \.self) { theme in
                    IrisOnboardingThemeTile(theme: theme, hue: iris.preferences.customHue ?? 0.5, selected: iris.preferences.theme == theme) { iris.setPreference { $0.theme = theme } }
                }
            }
            if iris.preferences.theme == .custom {
                group("Custom accent") { Slider(value: Binding(get: { iris.preferences.customHue ?? 0.5 }, set: { hue in iris.setPreference { $0.customHue = hue } }), in: 0...1).accessibilityLabel("Accent hue") }
            }
        case .personality: PersonalitySettingsView(iris: iris)
        case .voice: VoiceSettingsView(iris: iris)
        case .intelligence: group("Provider & model") { SourceSettings(iris: iris) }
        case .computer:
            group("Computer actions") { ComputerPermissionSettings(iris: iris) }
            group("Screen access") {
                ScreenRecordingPermissionRow()
            }
        case .shortcuts:
            ShortcutSettingsView(shortcuts: iris.shortcuts)
        }
    }
    private func settingToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            Text(title)
            Spacer()
            Toggle(title, isOn: isOn).labelsHidden()
        }
    }
    private func pref<T>(_ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding(get: { iris.preferences[keyPath: key] }, set: { value in iris.setPreference { $0[keyPath: key] = value } })
    }
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(IrisDesign.secondary)
            VStack(alignment: .leading, spacing: 16, content: content).frame(maxWidth: .infinity, alignment: .leading)
                .padding(18).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 14))
        }.font(.system(size: 13)).toggleStyle(.switch).controlSize(.small)
    }
}
