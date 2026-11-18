import SwiftUI
import AppKit
import CoreGraphics
import Combine

@MainActor final class ScreenRecordingAccess: ObservableObject {
    static let shared = ScreenRecordingAccess()
    @Published private(set) var granted = CGPreflightScreenCaptureAccess()
    @Published private(set) var checkMessage: String?
    @Published private(set) var restarting = false
    private var panel: NSPanel?

    static let restartArgument = "--iris-screen-access-restart"

    @discardableResult func refresh() -> Bool {
        let current = CGPreflightScreenCaptureAccess()
        if granted != current { granted = current }
        if current { checkMessage = nil }
        return current
    }

    func requireAccess() throws {
        guard refresh() else {
            showSetup()
            throw IrisFailure.message("This copy of Iris doesn’t have screen access yet. Enable it in System Settings, then use Restart Iris in the setup window. Nothing was captured.")
        }
    }

    func requestAccess() {
        guard !refresh() else { return }
        _ = CGRequestScreenCaptureAccess()
        if !refresh() { checkMessage = "Turn on access in System Settings, then restart Iris." }
    }

    func checkAgain() {
        if !refresh() {
            checkMessage = "Access is still off for this session. If the switch is already on, restart Iris."
        }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func showSetup(openSettings shouldOpenSettings: Bool = false, afterRestart: Bool = false) {
        refresh()
        if afterRestart, !granted {
            checkMessage = "Still off after restarting? Remove the old Iris entry in System Settings, then add the copy shown below and turn it on."
        }
        if shouldOpenSettings { openSettings() }
        if let panel { panel.orderFrontRegardless(); return }
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 340), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "Iris Screen Recording"
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: ScreenRecordingSetupView(access: self, appURL: Bundle.main.bundleURL, close: { [weak window] in window?.close() }))
        window.contentView = host
        window.setContentSize(host.fittingSize)
        window.center()
        panel = window
        window.orderFrontRegardless()
    }

    func restart() {
        guard !restarting else { return }
        restarting = true
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = false
        configuration.arguments = [Self.restartArgument, String(ProcessInfo.processInfo.processIdentifier)]
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            let failed = error != nil
            Task { @MainActor in
                if failed {
                    self.restarting = false
                    self.checkMessage = "Iris couldn’t restart automatically. Quit Iris from its menu bar menu, then reopen the copy shown here."
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}

struct ScreenRecordingPermissionRow: View {
    @ObservedObject private var access = ScreenRecordingAccess.shared

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: access.granted ? "checkmark.circle" : "lock.circle")
                .irisSymbolStyle().foregroundStyle(access.granted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("Screen Recording").font(.system(size: 13, weight: .medium))
                Text(access.granted ? "On · Iris can read an app you select." : "Off · Enable access for the copy of Iris you’re using.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(access.granted ? "Manage" : "Set up") {
                access.showSetup(openSettings: true)
            }.font(.caption)
        }
        .onAppear { access.refresh() }
        .onReceive(NSApplication.didBecomeActiveNotification.publisher) { _ in access.refresh() }
    }
}

private struct ScreenRecordingSetupView: View {
    @ObservedObject var access: ScreenRecordingAccess
    let appURL: URL
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(access.granted ? "Screen access is on" : "Enable Screen Recording",
                  systemImage: access.granted ? "checkmark.circle.fill" : "rectangle.dashed.badge.record")
                .font(.system(size: 19, weight: .semibold))
            Text(access.granted ? "Iris can now read an app you select for screen guidance." :
                "Turn on Iris in Privacy & Security → Screen & System Audio Recording. If it’s missing, drag this exact copy into the list or add it with +.")
                .font(.system(size: 13)).foregroundStyle(IrisDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: appURL.path))
                    .resizable().scaledToFit().frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(appURL.lastPathComponent).font(.system(size: 14, weight: .semibold))
                    Text(appURL.deletingLastPathComponent().path)
                        .font(.caption).foregroundStyle(IrisDesign.secondary).lineLimit(1).truncationMode(.middle)
                }
                Spacer()
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([appURL]) }
                    .buttonStyle(IrisActionStyle())
            }.padding(10).background(IrisDesign.control, in: RoundedRectangle(cornerRadius: 10))
                .onDrag { NSItemProvider(object: appURL as NSURL) }
            if !access.granted {
                Text(access.checkMessage ?? "After turning the switch on, restart Iris so macOS applies the change.")
                    .font(.caption).foregroundStyle(IrisDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Request Access") { access.requestAccess() }.buttonStyle(IrisActionStyle())
                    Button("Check Again") { access.checkAgain() }.buttonStyle(IrisActionStyle())
                }
            }
            HStack {
                Button("Open System Settings") { access.openSettings() }.buttonStyle(IrisActionStyle())
                Spacer()
                if access.granted {
                    Button("Done", action: close).buttonStyle(IrisActionStyle(primary: true))
                } else {
                    Button(access.restarting ? "Restarting…" : "Restart Iris") { access.restart() }
                        .buttonStyle(IrisActionStyle(primary: true)).disabled(access.restarting)
                }
            }
        }.padding(20).frame(width: 420).background(IrisDesign.canvas).foregroundStyle(IrisDesign.text).preferredColorScheme(.dark)
            .onReceive(NSApplication.didBecomeActiveNotification.publisher) { _ in access.refresh() }
    }
}

private extension Notification.Name {
    var publisher: NotificationCenter.Publisher { NotificationCenter.default.publisher(for: self) }
}
