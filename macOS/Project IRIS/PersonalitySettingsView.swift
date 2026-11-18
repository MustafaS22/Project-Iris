import SwiftUI

struct PersonalitySettingsView: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var scenario = PersonalityScenario.start
    @State private var previewing = false
    private var current: IrisPersonality { iris.preferences.personality }
    var body: some View {
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 8) {
                Text("A little more Iris.").font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                Text("Same capable assistant. A character that clicks with you.").font(.callout).foregroundStyle(IrisDesign.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) { choices.frame(width: 230); preview.frame(minWidth: 300, idealWidth: 340, maxWidth: .infinity) }
                VStack(alignment: .leading, spacing: 24) { choices; preview }
            }
            Divider()
            Toggle("Match voice delivery to personality", isOn: Binding(get: { iris.preferences.personalityID != nil && (iris.preferences.personalityVoiceTone ?? true) }, set: { value in iris.setPreference { $0.personalityID = current.rawValue; $0.personalityVoiceTone = value } })).toggleStyle(.switch).controlSize(.small).font(.callout)
            Text("Keeps your chosen voice. Gemini can match its delivery; other voice providers keep their own delivery. You can change personalities whenever you like.").font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var choices: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(IrisPersonality.allCases) { personality in
                let selected = current == personality
                Button { iris.setPreference { $0.personalityID = personality.rawValue } } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: personality.symbol).irisSymbolStyle().font(.system(size: 19, weight: .semibold)).foregroundStyle(iris.accent).frame(width: 24).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 5) { Text(personality.name).font(.system(size: 15, weight: selected ? .semibold : .medium)); Text(personality.traits).font(.system(size: 11)).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true) }
                        Spacer(minLength: 0)
                        if selected { Image(systemName: "checkmark").irisSymbolStyle().font(.caption.weight(.semibold)).foregroundStyle(iris.accent) }
                    }.padding(13).frame(maxWidth: .infinity, alignment: .leading).background(selected ? iris.accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12)).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : []).accessibilityLabel(personality.name + ". " + personality.traits)
            }
        }
    }
    private var preview: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                IrisAvatar(state: current == .spark ? .celebration : .idle, color: iris.accent, size: 43, animated: true, desktop: true)
                VStack(alignment: .leading, spacing: 5) { Text("Iris · " + current.name).font(.system(size: 21, weight: .semibold)); Text(current.traits).font(.caption).foregroundStyle(IrisDesign.secondary) }
            }
            Text(current.description).font(.system(size: 14)).lineSpacing(4).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            IrisPicker("Sample situation", selection: $scenario, options: PersonalityScenario.allCases.map { .init(value: $0, title: $0.rawValue) })
            VStack(alignment: .leading, spacing: 18) {
                Text(scenario.prompt).font(.system(size: 13)).foregroundStyle(IrisDesign.secondary).frame(maxWidth: .infinity, alignment: .trailing)
                Text(current.sample(scenario)).font(.system(size: 16)).lineSpacing(5).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading).background(LinearGradient(colors: [iris.accent.opacity(0.08), IrisDesign.surface], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 14))
            HStack {
                Button(previewing && (iris.voice.speaking || iris.voice.preparingSpeech) ? "Stop sample" : "Hear sample", systemImage: previewing && (iris.voice.speaking || iris.voice.preparingSpeech) ? "stop.circle" : "speaker.wave.2") {
                    if previewing && (iris.voice.speaking || iris.voice.preparingSpeech) { iris.voice.stopSpeaking(); previewing = false }
                    else { previewing = true; iris.previewPersonality(current, text: current.sample(scenario)) }
                }.buttonStyle(IrisActionStyle()).disabled(iris.busy || iris.voice.listening || iris.voice.requesting)
                Spacer(minLength: 0)
            }
            Text("Written examples are previews, not generated replies. Browsing them uses no AI credits. Hear sample uses your configured voice provider and its normal usage.").font(.system(size: 11)).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = iris.voice.speechError { Text(error).font(.caption).foregroundStyle(.orange) }
        }.onChange(of: current) { _, _ in stopPreview() }.onChange(of: scenario) { _, _ in stopPreview() }
        .onChange(of: iris.voice.speaking) { _, active in if !active && !iris.voice.preparingSpeech { previewing = false } }
        .onChange(of: iris.voice.preparingSpeech) { _, active in if !active && !iris.voice.speaking { previewing = false } }
        .onDisappear { stopPreview() }
    }
    private func stopPreview() { if previewing { iris.voice.stopSpeaking(); previewing = false } }
}

struct PersonalityEntry: View {
    @ObservedObject var iris: IrisOrchestrator
    var compact = false
    @State private var presented = false
    var body: some View {
        Button { presented = true } label: {
            if compact { HStack(spacing: 5) { Text(iris.preferences.personality.name); Image(systemName: "chevron.down").irisSymbolStyle().font(.system(size: 9)) }.font(.caption).foregroundStyle(IrisDesign.secondary) }
            else {
                HStack(spacing: 14) {
                    Image(systemName: iris.preferences.personality.symbol).irisSymbolStyle().font(.system(size: 22)).foregroundStyle(iris.accent)
                    VStack(alignment: .leading, spacing: 5) { Text("Iris's personality · " + iris.preferences.personality.name).font(.system(size: 14, weight: .semibold)); Text("Choose how Iris talks, encourages and helps.").font(.caption).foregroundStyle(IrisDesign.secondary) }
                    Spacer(); Image(systemName: "chevron.right").irisSymbolStyle().font(.caption).foregroundStyle(IrisDesign.secondary)
                }.padding(16).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 12))
            }
        }.buttonStyle(.plain).help("Change Iris's personality").accessibilityLabel("Choose Iris personality. Current: " + iris.preferences.personality.name)
        .sheet(isPresented: $presented) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Spacer(); Button("Done") { presented = false }.buttonStyle(IrisActionStyle()) }
                ScrollView { PersonalitySettingsView(iris: iris) }
            }.padding(28).frame(width: 690, height: 700).background(IrisBackdrop(accent: iris.accent)).foregroundStyle(IrisDesign.text).preferredColorScheme(.dark).environment(\.irisControlAccent, iris.accent)
        }
    }
}
