import SwiftUI

struct AppTestingView: View {
    @ObservedObject var iris: IrisOrchestrator
    var openAISettings: (() -> Void)? = nil
    var openConnections: (() -> Void)? = nil
    var showsHeading = true
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                if showsHeading { Text("App testing").font(.system(size: 30, weight: .semibold)).tracking(-0.7) }
                Text("Revisit setup and check each surface. Your notes, knowledge and connected accounts stay saved.").font(.system(size: 14)).foregroundStyle(IrisDesign.secondary)
            }
            GroupBox("Replay setup") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Connect AI and voice first, then practice with the real notch, floating avatar and drafting. You can pause and resume.").font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
                    Button("Replay full onboarding", systemImage: "arrow.counterclockwise") { iris.restartOnboardingAt?(0) }.buttonStyle(IrisActionStyle(primary: true))
                    HStack(spacing: 12) {
                        Button("AI setup") { iris.restartOnboardingAt?(3) }
                        Button("Connections setup") { iris.showWorkspace(.connections) }
                        Button("Notch tour") { iris.restartOnboardingAt?(5) }
                    }.buttonStyle(IrisActionStyle())
                }
            }
            GroupBox("Preview the notch") {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Open the real interface without starting a session or sending a question.").font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
                    HStack(spacing: 12) {
                        ForEach(IrisOrchestrator.NotchTab.allCases.filter { $0 != .welcome }, id: \.self) { tab in
                            Button(tab == .focus ? "Home & focus" : tab.rawValue) { iris.tab = tab; iris.notchPinned = true; iris.expanded = true }
                        }
                        Button("Collapse") { iris.collapsePresence() }
                    }.buttonStyle(IrisActionStyle())
                }
            }
            GroupBox("Connection checks") {
                VStack(alignment: .leading, spacing: 12) {
                    Label((try? GoogleAppConfiguration.bundled()) != nil ? "Google registration included in this app" : "Google registration missing", systemImage: "person.crop.circle.badge.checkmark")
                    Label(iris.preferences.providerVerified ? "Selected model passed its last test" : "Selected model has not passed a connection test", systemImage: iris.preferences.providerVerified ? "checkmark.circle" : "circle")
                    Text("A live connection test uses provider allowance. Open AI settings to run it explicitly.").font(.caption).foregroundStyle(IrisDesign.secondary)
                    HStack { Button("AI settings") { if let openAISettings { openAISettings() } else { iris.workspaceSection = .settings } }; Button("Knowledge connections") { if let openConnections { openConnections() } else { iris.workspaceSection = .connections } } }.buttonStyle(IrisActionStyle())
                }.font(.system(size: 13))
            }
        }
    }
}

struct GoogleConnectionHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Google sign-in is built in. If Google blocks access, check these settings:").font(.system(size: 13, weight: .medium))
            Text("Select the exact Google account added to this app's test-user list. In Google Cloud, check Audience, Branding and Data Access in the same project. Enable the API for the service you connect. Organization policies can also restrict access.").font(.caption).foregroundStyle(IrisDesign.secondary)
            Text("Public distribution requires Google's consent and scope review where applicable. Including the client configuration does not bypass Google's approval.").font(.caption).foregroundStyle(IrisDesign.secondary)
            if let project = try? GoogleAppConfiguration.read()?.projectID,
               let url = URL(string: "https://console.cloud.google.com/auth/audience?project=\(project)") {
                Link("Open this project's Google settings", destination: url)
            }
            Link("Review Iris access in Google", destination: URL(string: "https://myaccount.google.com/connections")!)
        }
    }
}
