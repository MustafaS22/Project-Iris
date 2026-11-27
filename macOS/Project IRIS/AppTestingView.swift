import SwiftUI
import AppKit

struct AppTestingView: View {
    @ObservedObject var iris: IrisOrchestrator
    var openAISettings: (() -> Void)? = nil
    var openConnections: (() -> Void)? = nil
    var showsHeading = true
    @State private var demo: Demo?

    private enum Demo: String, Identifiable {
        case computer, diagram
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 12) {
                if showsHeading { Text("App testing").font(.system(size: 30, weight: .semibold)).tracking(-0.7) }
                Text("Revisit setup and check each surface. Your notes, knowledge and connected accounts stay saved.").font(.system(size: 14)).foregroundStyle(IrisDesign.secondary)
            }
            GroupBox("Feature demos") {
                VStack(alignment: .leading, spacing: 4) {
                    demoRow("Computer Use", symbol: "cursorarrow.motionlines", detail: "Watch Iris act in a sample workspace and review an approval.") { demo = .computer }
                    Divider()
                    demoRow("Floating Iris", symbol: "sparkles", detail: "Move the avatar around and try its controls.") { iris.openFloatingPreview?() }
                        .disabled(iris.openFloatingPreview == nil)
                    Divider()
                    demoRow("Animated diagram", symbol: "scribble.variable", detail: "Watch Iris draw a circuit using a built-in lesson.") { demo = .diagram }
                    Divider()
                    demoRow("Double-tap drafting", symbol: "text.cursor", detail: "Click in the sample note in TextEdit and double-tap your drafting key. Generating a draft uses your selected AI.") { iris.showDraftPractice?() }
                        .disabled(iris.showDraftPractice == nil)
                }.padding(.vertical, 4)
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
        .sheet(item: $demo) { item in
            switch item {
            case .computer: ComputerUseDemoView(accent: iris.accent)
            case .diagram: DiagramDemoView(accent: iris.accent)
            }
        }
    }

    private func demoRow(_ name: String, symbol: String, detail: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .foregroundStyle(iris.accent).frame(width: 26).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(IrisDesign.secondary)
            }
            Spacer(minLength: 10)
            Button("Try") { action() }
                .buttonStyle(IrisActionStyle())
                .accessibilityLabel("Try " + name)
        }
        .padding(.vertical, 7)

    }
}


private struct ComputerUseDemoView: View {
    private enum Step: Equatable { case ready, inspecting, approval, editing, verified, denied }
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    @State private var step: Step = .ready
    @State private var anchor: NSView?
    @State private var cursor = IrisComputerCursor()

    private var status: String {
        switch step {
        case .ready: "Ready to organize the sample note"
        case .inspecting: "Finding the note"
        case .approval: "Waiting for your approval"
        case .editing: "Updating the sample note"
        case .verified: "Verified the new title"
        case .denied: "Stopped. The sample note is unchanged."
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Computer Use demo").font(.title2.weight(.semibold))
            Text("Scripted practice in this window. No AI requests or macOS permissions required.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 11) {
                Label("Sample workspace", systemImage: "folder").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack {
                    Label(step == .verified ? "Trip checklist" : "Untitled note", systemImage: "note.text")
                        .font(.headline)
                    Spacer()
                    Image(systemName: step == .verified ? "checkmark.circle.fill" : "pencil")
                        .foregroundStyle(accent).accessibilityHidden(true)
                }
                .padding(10)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                .background(CursorAnchor { anchor = $0 })
            }
            .padding(14)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 12))
            Text(status).font(.callout.weight(.medium)).accessibilityAddTraits(.updatesFrequently)
            if step == .approval {
                Text("Allow Iris to rename “Untitled note” to “Trip checklist”?")
                    .font(.callout).foregroundStyle(.secondary)
            }
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                switch step {
                case .ready, .verified, .denied:
                    Button(step == .ready ? "Run demo" : "Replay") { step = .inspecting }
                        .buttonStyle(.borderedProminent).tint(accent)
                case .approval:
                    Button("Deny") { step = .denied }
                    Button("Allow Once") { step = .editing }
                        .buttonStyle(.borderedProminent).tint(accent)
                case .inspecting, .editing:
                    Button("Stop demo") { step = .denied }
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .task(id: step) {
            guard step == .inspecting || step == .editing else { cursor.hide(); return }
            let editing = step == .editing
            if let anchor, let window = anchor.window, window.isKeyWindow {
                cursor.accent = NSColor(accent)
                let x = editing ? anchor.bounds.maxX - 26 : 22
                let position = window.convertPoint(toScreen: anchor.convert(.init(x: x, y: anchor.bounds.midY), to: nil))
                cursor.show()
                try? cursor.move(to: .init(x: position.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - position.y))
            }
            do {
                try await Task.sleep(for: .milliseconds(editing ? 450 : 650))
                try Task.checkCancellation()
                if editing { cursor.feedback() }
                step = editing ? .verified : .approval
            } catch { return }
        }
        .onDisappear {
            cursor.hide()
        }
    }

    private struct CursorAnchor: NSViewRepresentable {
        let report: (NSView) -> Void
        func makeNSView(context: Context) -> NSView {
            let view = NSView()
            Task { @MainActor in report(view) }
            return view
        }
        func updateNSView(_ view: NSView, context: Context) {}
    }
}

private struct DiagramDemoView: View {
    let accent: Color
    @Environment(\.dismiss) private var dismiss
    @State private var revision = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("A complete circuit").font(.title2.weight(.semibold))
            Text("Built-in animated lesson.").font(.callout).foregroundStyle(.secondary)
            IrisDrawingView(drawing: DiagramLibrary.make("electric-circuit"), accent: accent, revision: revision)
                .frame(height: 290)
                .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Diagram of a complete electrical circuit")
            HStack {
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Replay") { revision += 1 }.buttonStyle(.borderedProminent).tint(accent)
            }
        }
        .padding(24)
        .frame(width: 520)
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
