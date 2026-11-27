import SwiftUI

struct ComputerPermissionSettings: View {
    @ObservedObject var iris: IrisOrchestrator
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ComputerAutonomySettings(session: iris.computer)
            Divider()
            Toggle(isOn: Binding(get: { iris.preferences.alwaysAllowComputerActions ?? false }, set: { value in iris.setPreference { $0.alwaysAllowComputerActions = value } })) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Allow additional file and project actions automatically").font(.system(size: 14, weight: .semibold))
                    Text("Opening apps and links, playback, and browsing granted folders already start directly.").font(.system(size: 12)).foregroundStyle(IrisDesign.secondary)
                }
            }.toggleStyle(.switch)
            Text("Also allows replacing files in granted folders and running project code in Terminal with your account’s access.").font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            Label("Folder grants and macOS permissions apply. Explicit image requests use your selected provider’s quota or billing.", systemImage: "lock.shield").font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: 620, alignment: .leading)
    }
}
