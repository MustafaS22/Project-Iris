import SwiftUI
import AppKit

struct MemorySettingsView: View {
    @ObservedObject var iris: IrisOrchestrator
    @State private var fact = ""
    @State private var editing: UUID?
    @State private var edited = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Toggle("Use saved memories in answers", isOn: Binding(get: { iris.preferences.memoryEnabled ?? true }, set: { value in iris.setPreference { $0.memoryEnabled = value } }))
            Text("Tell Iris ‘remember that…’ or add a detail here. Use Scan now in Knowledge to extract useful memories from saved notes and enabled sources using your selected AI. Memories stay on this Mac; relevant details may be sent to your AI with a question. Turning memory off stops scans and memory use. Forgetting a memory keeps the original material.").font(.callout).foregroundStyle(IrisDesign.secondary)
            HStack {
                TextField("Something you’d like Iris to remember", text: $fact).textFieldStyle(IrisTextFieldStyle()).accessibilityLabel("New memory")
                Button("Remember") { iris.remember(fact); fact = "" }.buttonStyle(IrisActionStyle(primary: true)).disabled(fact.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("\((iris.data.memories ?? []).count) saved · up to 100").font(.caption).foregroundStyle(IrisDesign.secondary)
            ForEach(iris.data.memories ?? []) { memory in
                VStack(alignment: .leading, spacing: 10) {
                    if editing == memory.id {
                        TextField("Memory", text: $edited).textFieldStyle(IrisTextFieldStyle())
                        HStack { Button("Save") { iris.editMemory(memory.id, text: edited); editing = nil }; Button("Cancel") { editing = nil } }
                    } else {
                        Text(memory.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Edit") { editing = memory.id; edited = memory.text }.accessibilityLabel("Edit memory: \(memory.text)")
                            Button("Forget", role: .destructive) { iris.forget(memory.id) }.accessibilityLabel("Forget memory: \(memory.text)")
                        }.font(.caption)
                    }
                    Divider()
                }.padding(.vertical, 6)
            }
            if (iris.data.memories ?? []).isEmpty { Label("A fresh start. Iris only saves what you ask it to remember.", systemImage: "brain").foregroundStyle(IrisDesign.secondary) }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("From your knowledge").font(.headline)
                Text("Scanned summaries retain their source. Disabled or removed sources are excluded from answers. Unchanged material won’t recreate a forgotten memory.").font(.caption).foregroundStyle(IrisDesign.secondary)
            }
            ForEach(iris.visibleKnowledgeMemories) { record in
                VStack(alignment: .leading, spacing: 8) {
                    Text(record.title).font(.subheadline.weight(.semibold))
                    Text(record.source.flatMap(KnowledgeConnector.init(rawValue:))?.name ?? "Saved note").font(.caption).foregroundStyle(iris.accent)
                    ForEach(Array(record.facts.enumerated()), id: \.offset) { _, fact in Text(fact).textSelection(.enabled).fixedSize(horizontal: false, vertical: true) }
                    Button("Forget these memories", role: .destructive) { iris.forgetKnowledgeMemory(record.id) }.font(.caption)
                    Divider()
                }
            }
            if iris.visibleKnowledgeMemories.isEmpty { Text("No scanned memories yet. Choose Scan now in Knowledge to get started.").font(.callout).foregroundStyle(IrisDesign.secondary) }
        }.toggleStyle(.switch)
    }
}

struct LanguageSettingsView: View {
    @AppStorage("IrisReplyLanguage") private var reply = "auto"
    @AppStorage("IrisInputLanguage") private var input = "auto"
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            IrisPicker("Chat and spoken replies", selection: $reply, options: AssistantLanguage.choices.map { .init(value: $0.0, title: $0.1) })
            Text("By default, Iris matches the language you write or speak. You can also ask for a translation or a different language in any message.").foregroundStyle(IrisDesign.secondary)
            IrisPicker("Speech recognition language", selection: $input, options: [("auto", "Mac’s language")] .map { IrisPickerOption(value: $0.0, title: $0.1) } + AssistantLanguage.choices.dropFirst().map { .init(value: $0.0, title: $0.1) })
            Text("Apple recognition listens in one language at a time. Choose the language you’ll speak; ‘Mac’s language’ uses your system locale. VoiceBox recognition and natural voices support languages according to the model you’ve installed. System speech chooses an available voice matching the reply language.").font(.callout).foregroundStyle(IrisDesign.secondary)
        }
    }
}

struct AccessibilitySettingsView: View {
    @AppStorage("IrisReduceMotion") private var reduceMotion = false
    @AppStorage("IrisHighContrast") private var contrast = false
    @AppStorage("IrisChatTextSize") private var textSize = 15.0
    @ObservedObject var iris: IrisOrchestrator
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Toggle("Reduce animated movement", isOn: $reduceMotion)
            Toggle("Stronger text contrast", isOn: $contrast)
            VStack(alignment: .leading, spacing: 10) {
                Text("Answer text size · \(Int(textSize)) pt")
                Slider(value: $textSize, in: 15...23, step: 1).accessibilityLabel("Answer text size")
                Text("Iris keeps explanations clear and easy to read.").font(.system(size: textSize)).foregroundStyle(IrisDesign.text)
            }
            Toggle("Read typed answers aloud", isOn: Binding(get: { iris.preferences.speakTypedReplies ?? false }, set: { value in iris.setPreference { $0.speakTypedReplies = value } }))
            Text("Iris also respects macOS Reduce Motion and Increase Contrast. Use VoiceOver to navigate labeled controls, Tab and Shift–Tab to move between fields, Return to activate buttons, and Escape to dismiss pickers. macOS Keyboard Navigation controls which native controls Tab visits.").font(.callout).foregroundStyle(IrisDesign.secondary)
        }.toggleStyle(.switch)
    }
}

struct IrisAccessibility: ViewModifier {
    @AppStorage("IrisReduceMotion") private var reduced = false
    @AppStorage("IrisHighContrast") private var contrast = false
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    func body(content: Content) -> some View { content.environment(\.irisAppReduceMotion, reduced || systemReduced).environment(\.irisAppHighContrast, contrast).contrast(contrast ? 1.12 : 1).transaction { if reduced || systemReduced { $0.animation = nil } } }
}

private struct IrisAppContrastKey: EnvironmentKey { static let defaultValue = false }
private struct IrisAppMotionKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var irisAppHighContrast: Bool { get { self[IrisAppContrastKey.self] } set { self[IrisAppContrastKey.self] = newValue } }
    var irisAppReduceMotion: Bool { get { self[IrisAppMotionKey.self] } set { self[IrisAppMotionKey.self] = newValue } }
    var irisReduceMotion: Bool { accessibilityReduceMotion || irisAppReduceMotion }
}

@MainActor enum IrisMotion {
    static var reduced: Bool { UserDefaults.standard.bool(forKey: "IrisReduceMotion") || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
}
