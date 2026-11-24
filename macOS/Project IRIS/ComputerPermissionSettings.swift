import SwiftUI

struct ComputerPermissionSettings: View {
    @ObservedObject var iris: IrisOrchestrator
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComputerAutonomySettings(session: iris.computer)
            Divider()
            Toggle(isOn: Binding(get: { iris.preferences.alwaysAllowComputerActions ?? false }, set: { value in iris.setPreference { $0.alwaysAllowComputerActions = value } })) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Allow simple app & file recipes automatically").font(.system(size: 14, weight: .semibold))
                    Text("Existing direct actions can run without review. Multi-step Computer tasks use the execution mode above.").font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                }
            }.toggleStyle(.switch)
            Text("Includes opening apps and links, Spotify playback, LM Studio hosting, and reading or replacing files in folders you grant. Project tasks can run code in Terminal with your account’s access. Turn this off to review each action.").font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            Label("Folder grants and macOS permissions still apply. Billed image generation always needs approval.", systemImage: "lock.shield").font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: 620, alignment: .leading)
    }
}
