import AppKit
import Combine
import Sparkle
import SwiftUI

/// Sparkle owns downloading, signature validation, atomic replacement and relaunch.
/// No AI calls, private content, or permission-database changes are involved.
@MainActor final class IrisUpdates: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var canCheck = false
    @Published private(set) var status = "Check for a newer Iris without leaving the app."
    @Published private(set) var issue: String?
    @Published private(set) var automaticChecks = false
    @Published private(set) var lastChecked: Date?
    private var started = false
    private var subscriptions = Set<AnyCancellable>()
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    var beforeInstalling: (() -> Void)?

    func start() {
        guard !started, !ProcessInfo.processInfo.arguments.contains("--iris-validation") else { return }
        started = true
        controller.startUpdater()
        let updater = controller.updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastChecked)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
    }
    func check() {
        start()
        guard canCheck else { return }
        issue = nil; status = "Checking for updates…"
        controller.checkForUpdates(nil)
    }
    func setAutomaticChecks(_ enabled: Bool) {
        start()
        controller.updater.automaticallyChecksForUpdates = enabled
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        issue = nil; status = "Iris \(item.displayVersionString) is available. Review the update window to install it."
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        issue = nil
        status = error.localizedDescription
    }
    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        beforeInstalling?()
        status = "Installing Iris \(item.displayVersionString). Iris will restart when it’s ready."
    }
    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        if let error = error as NSError?, error.code != SUError.noUpdateError.rawValue {
            issue = error.localizedDescription
            status = "The update didn’t finish. Your installed Iris is still available."
        }
    }
}

struct IrisUpdatesView: View {
    @ObservedObject var updates: IrisUpdates
    let accent: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 46, weight: .semibold)).foregroundStyle(accent).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keep Iris up to date").font(.system(size: 24, weight: .semibold))
                    IrisVersionLabel().foregroundStyle(IrisDesign.secondary)
                    Text(updates.status).font(.callout).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 14) {
                Button(action: updates.check) { Label("Check for updates", systemImage: "arrow.clockwise").fixedSize() }
                    .buttonStyle(IrisActionStyle(primary: true)).disabled(!updates.canCheck)
                if let date = updates.lastChecked { Text("Last checked \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption).foregroundStyle(IrisDesign.secondary) }
            }
            if let issue = updates.issue { Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(.orange).font(.callout).textSelection(.enabled) }
            Divider()
            Toggle("Check for updates automatically", isOn: Binding(get: { updates.automaticChecks }, set: updates.setAutomaticChecks)).toggleStyle(.switch)
            Text("Checks about once a day. You choose when to download, install and restart. No AI usage is involved.").font(.callout).foregroundStyle(IrisDesign.secondary)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Label("Your Iris stays yours", systemImage: "checkmark.shield.fill").font(.headline)
                Text("Updates are verified before installation and replace Iris in its current location. Your chats, knowledge, memories, settings and saved provider credentials stay in place.").font(.callout).foregroundStyle(IrisDesign.secondary)
                Text("macOS controls permissions. Moving from an older ad hoc build or changing signing identity can require approval again. Updates never reset or bypass your permissions.").font(.caption).foregroundStyle(IrisDesign.secondary)
            }
            Link("Release notes & previous versions", destination: URL(string: "https://projectiris.lovelyabbey.chatgpt.site/releases")!).foregroundStyle(accent)
        }.onAppear { updates.start() }
    }
}
