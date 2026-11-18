import SwiftUI
import AppIntents

@main struct IrisApp: App {
    @StateObject private var session = IrisSession.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group {
                if session.islandMode { IrisIslandSummonView(session: session) }
                else { IrisHome(session: session) }
            }
                .preferredColorScheme(.dark)
                .tint(IrisStyle.accent)
                .onOpenURL { url in
                    guard url.scheme == "iris" else { return }
                    if url.host == "island" { session.summon(islandOnly: true) }
                    else if url.host == "ask" { session.summon() }
                    else if url.host == "conversation" { session.islandMode = false }
                }
                .onReceive(NotificationCenter.default.publisher(for: .irisSummoned)) { _ in consumeSummon() }
                .task { await session.cleanOldActivities(); consumeSummon(); IrisShortcuts.updateAppShortcutParameters() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consumeSummon() }
            if phase == .background { session.leaveForeground() }
        }
    }
    private func consumeSummon() {
        guard UIApplication.shared.applicationState == .active,
              UserDefaults.standard.bool(forKey: "IrisPendingSummon") else { return }
        UserDefaults.standard.removeObject(forKey: "IrisPendingSummon")
        session.summon()
    }
}

extension Notification.Name { static let irisSummoned = Notification.Name("IrisSummoned") }

struct AskIrisIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Iris"
    static let description = IntentDescription("Open Iris and start a voice question. You may need to unlock your iPhone.")
    static var openAppWhenRun = true
    @MainActor func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "IrisPendingSummon")
        NotificationCenter.default.post(name: .irisSummoned, object: nil)
        return .result()
    }
}

struct IrisShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskIrisIslandIntent(), phrases: ["Ask \(.applicationName) in Island"], shortTitle: "Ask Iris in Island", systemImageName: "waveform")
        AppShortcut(intent: ShowIrisIslandIntent(), phrases: ["Show \(.applicationName) in Island"], shortTitle: "Show Iris in Island", systemImageName: "capsule")
        AppShortcut(intent: AskIrisIntent(), phrases: ["Ask \(.applicationName)", "Talk to \(.applicationName)"], shortTitle: "Ask Iris", systemImageName: "waveform")
    }
}


struct AskIrisIslandIntent: AudioRecordingIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Ask Iris in Island"
    static let description = IntentDescription("Start an Iris voice session with a visible Live Activity. Set up the API key and microphone permission in Iris first.")
    static var openAppWhenRun = false
    @available(iOS 26.0, *) static var supportedModes: IntentModes { .background }
    @MainActor func perform() async throws -> some IntentResult {
        try await IrisSession.shared.startIslandRecording()
        return .result()
    }
}

struct ShowIrisIslandIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Show Iris in Island"
    static let description = IntentDescription("Show Iris in the Dynamic Island briefly without opening the chat or recording audio.")
    static var openAppWhenRun = false
    @available(iOS 26.0, *) static var supportedModes: IntentModes { .background }
    @MainActor func perform() async throws -> some IntentResult {
        try await IrisSession.shared.showIsland()
        return .result()
    }
}

struct IrisIslandSummonView: View {
    @ObservedObject var session: IrisSession
    var body: some View {
        VStack(spacing: 24) {
            IrisFace(size: 96, active: session.listening || session.busy)
            Text(session.phase).font(.title2.weight(.semibold))
            Text("Iris stays with you in the Island during this session.").foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let error = session.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Button("Open conversation") { session.islandMode = false }.buttonStyle(.bordered)
            Button("Stop session") { session.stop(); session.islandMode = false }.buttonStyle(.bordered)
        }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity).background(IrisStyle.background)
    }
}
