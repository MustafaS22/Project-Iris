import SwiftUI
import AppKit
import ApplicationServices
import Combine

struct InlineDraftSettingsView: View {
    @AppStorage(InlineDraftController.enabledKey) private var enabled = false
    @AppStorage(InlineDraftController.modifierKey) private var modifier = InlineDraftKey.command
    @AppStorage(InlineDraftController.nearbyKey) private var nearby = true
    @AppStorage("IrisInlineDraftPersonalContext") private var personal = true
    @AppStorage("IrisInlineDraftEmail") private var email = ""
    @AppStorage("IrisInlineDraftPhone") private var phone = ""
    @AppStorage("IrisInlineDraftAddress") private var address = ""
    @State private var trusted = AXIsProcessTrusted()

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            Toggle(isOn: $enabled) {
                Label("Double Tap to Draft", systemImage: "text.cursor").font(.system(size: 14, weight: .semibold))
            }.toggleStyle(.switch).controlSize(.small)
            Text("Tap the right modifier twice in an editable field. Iris fills a known name field, polishes selected text, continues a draft, or writes a reply. It asks a specific question when essential details are missing. Nothing is sent.")
                .font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            if enabled {
                IrisPicker("Double tap", selection: $modifier, options: InlineDraftKey.allCases.map { .init(value: $0, title: $0.title) })
                Toggle("Use on-screen context", isOn: $nearby).toggleStyle(.switch).controlSize(.small)
                Toggle("Use my saved details for empty fields", isOn: $personal).toggleStyle(.switch).controlSize(.small).disabled(!nearby)
                Text("Empty fields can become replies or form answers. Iris uses the nearby question and relevant profile details, personal notes, and facts you’ve stated in chat. Turn this off to use only the visible context. If screen access is already allowed, unreadable app text can be read locally from a small area around the field; the image is never sent to your AI.")
                    .font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Double Tap uses your selected AI provider. When on, each Double Tap sends a small excerpt near the focused field and its label to your selected AI provider. This helps with email subjects, replies, letters and messages. It only reads when invoked; protected fields are excluded. Saved autofill details are filled locally, without an AI request.")
                    .font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
                DisclosureGroup("Autofill details · optional") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Iris uses your name from Appearance. Add other details here only if you want Double Tap to fill them into matching fields. These stay on this Mac until you insert them.")
                            .font(.caption).foregroundStyle(IrisDesign.secondary)
                        autofillField("Email", value: $email)
                        autofillField("Phone", value: $phone)
                        autofillField("Mailing address", value: $address)
                    }.padding(.top, 10)
                }.font(.system(size: 12, weight: .medium))
                if !trusted {
                    Text("Allow Iris in System Settings → Privacy & Security → Accessibility so it can locate the caret and insert the draft.")
                        .font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Open Accessibility Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }.buttonStyle(IrisActionStyle())
                        Button("Show Iris in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                        }.buttonStyle(IrisActionStyle())
                        Button("Check access") { refresh() }.buttonStyle(IrisActionStyle())
                    }
                }
            }
        }
        .padding(16).background(IrisDesign.surface, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { refresh() }
        .onChange(of: enabled) { _, _ in refresh() }
        .onChange(of: modifier) { _, _ in InlineDraftController.shared.reconcileMonitors() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh() }
    }

    private func autofillField(_ title: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(IrisDesign.secondary)
            TextField("Not saved", text: value)
                .textFieldStyle(.plain).font(.system(size: 13))
                .padding(.horizontal, 11).padding(.vertical, 9)
                .background(IrisDesign.control, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(IrisDesign.secondary.opacity(0.15)))
                .accessibilityLabel("Double Tap autofill " + title)
        }
    }

    private func refresh() {
        trusted = AXIsProcessTrusted()
        InlineDraftController.shared.reconcileMonitors()
    }
}
