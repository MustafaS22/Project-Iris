import SwiftUI
import AppKit

struct ShortcutSettingsView: View {
    @ObservedObject var shortcuts: IrisShortcutStore
    @State private var recording: IrisShortcutAction?
    @State private var failure: String?
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text("Make Iris a few keys away. Click a shortcut to record your own.")
                .font(.system(size:13)).foregroundStyle(IrisDesign.secondary)
            VStack(spacing:0) {
                ForEach(IrisShortcutAction.allCases) { action in
                    VStack(alignment:.leading,spacing:10) {
                        ViewThatFits(in:.horizontal) {
                            HStack(spacing:18) { description(action); Spacer(minLength:8); controls(action) }
                            VStack(alignment:.leading,spacing:12) { description(action); controls(action) }
                        }
                        if let problem = shortcuts.registrationIssues[action] { Label(problem,systemImage:"exclamationmark.circle.fill").font(.caption).foregroundStyle(.orange) }
                    }.padding(16)
                    if action != IrisShortcutAction.allCases.last { Divider().padding(.horizontal,16) }
                }
            }.background(IrisDesign.surface,in:RoundedRectangle(cornerRadius:14))
            InlineDraftSettingsView()
            HStack {
                Button("Reset all to defaults") { do { try shortcuts.restoreDefaults(); failure = nil } catch { failure = error.localizedDescription } }.buttonStyle(IrisActionStyle())
                Spacer(minLength:0)
            }
            Text("Global shortcuts include Command, Control or Option. macOS-reserved combinations may be unavailable. Changes are saved on this Mac and work immediately.")
                .font(.system(size:11)).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal:false,vertical:true)
            if let failure { Label(failure,systemImage:"exclamationmark.circle.fill").font(.caption).foregroundStyle(.orange) }
        }.sheet(item:$recording) { action in ShortcutRecordingSheet(shortcuts:shortcuts,action:action) }
    }
    private func description(_ action:IrisShortcutAction) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Text(action.title).font(.system(size:13,weight:.semibold))
            Text(action.detail).font(.system(size:11)).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal:false,vertical:true)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func controls(_ action:IrisShortcutAction) -> some View {
        HStack(spacing:9) {
            Button { recording = action; failure = nil } label: {
                HStack(spacing:9) { Text(shortcuts.label(action)).font(.system(size:12,weight:.semibold,design:.monospaced)); Image(systemName:"pencil").irisSymbolStyle().font(.system(size:10)) }
                    .padding(.horizontal,12).padding(.vertical,10).background(IrisDesign.control,in:RoundedRectangle(cornerRadius:8))
            }.buttonStyle(.plain).help("Change \(action.title)").accessibilityLabel("Change \(action.title), \(shortcuts.label(action))")
            if shortcuts.bindings[action] != nil {
                Button { do { try shortcuts.set(nil,for:action); failure = nil } catch { failure = error.localizedDescription } } label: { Image(systemName:"xmark").irisSymbolStyle().font(.system(size:10)).frame(width:25,height:30) }
                    .buttonStyle(.plain).help("Disable \(action.title)").accessibilityLabel("Disable \(action.title)")
            }
        }.fixedSize()
    }
}
private struct ShortcutRecordingSheet: View {
    @ObservedObject var shortcuts:IrisShortcutStore
    let action:IrisShortcutAction
    @Environment(\.dismiss) private var dismiss
    @State private var failure:String?
    var body:some View {
        VStack(alignment:.leading,spacing:18) {
            Label("Set shortcut",systemImage:"keyboard").font(.system(size:20,weight:.semibold))
            Text(action.title).font(.headline)
            Text(action.global ? "Press a key together with Command, Control or Option." : "Press a key or key combination. This shortcut only runs inside Iris.")
                .font(.system(size:13)).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal:false,vertical:true)
            ShortcutKeyCapture { event in
                if event.keyCode == 53 && IrisKeyChord.carbonFlags(event.modifierFlags) == 0 { dismiss(); return }
                do { try shortcuts.set(IrisKeyChord(event:event),for:action); dismiss() } catch { failure = error.localizedDescription }
            }.frame(height:58).background(IrisDesign.control,in:RoundedRectangle(cornerRadius:10))
                .overlay { Text("Press your shortcut…").font(.system(size:14,weight:.medium)).allowsHitTesting(false) }
            if let failure { Label(failure,systemImage:"exclamationmark.circle.fill").font(.caption).foregroundStyle(.orange).fixedSize(horizontal:false,vertical:true) }
            Text("Escape cancels recording. Iris’s global shortcuts pause while you choose.").font(.system(size:11)).foregroundStyle(IrisDesign.secondary)
            HStack { Button("Use default") { do { try shortcuts.set(action.defaultChord,for:action); dismiss() } catch { failure = error.localizedDescription } }; Spacer(); Button("Cancel") { dismiss() } }
        }.padding(26).frame(width:380).background(IrisDesign.canvas).foregroundStyle(IrisDesign.text).preferredColorScheme(.dark)
            .onAppear { shortcuts.beginRecording() }.onDisappear { shortcuts.endRecording() }
    }
}
private struct ShortcutKeyCapture:NSViewRepresentable {
    let record:(NSEvent)->Void
    func makeNSView(context:Context)->CaptureView { let view=CaptureView(); view.record=record; return view }
    func updateNSView(_ view:CaptureView,context:Context) { view.record=record; DispatchQueue.main.async { if view.window?.firstResponder !== view { view.window?.makeFirstResponder(view) } } }
    final class CaptureView:NSView {
        var record:((NSEvent)->Void)?
        override var acceptsFirstResponder:Bool { true }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); DispatchQueue.main.async { self.window?.makeFirstResponder(self) } }
        override func keyDown(with event:NSEvent) { if !event.isARepeat { record?(event) } }
        override func performKeyEquivalent(with event:NSEvent)->Bool { if !event.isARepeat { record?(event) }; return true }
        override func mouseDown(with event:NSEvent) { window?.makeFirstResponder(self) }
    }
}

/// Window-scoped dismiss keys never capture input from other applications or sheets.
struct IrisDismissShortcut: NSViewRepresentable {
    let shortcuts:IrisShortcutStore
    let action:()->Void
    func makeCoordinator()->Coordinator { Coordinator() }
    func makeNSView(context:Context)->NSView { let view=NSView(); context.coordinator.view=view; context.coordinator.shortcuts=shortcuts; context.coordinator.action=action; context.coordinator.start(); return view }
    func updateNSView(_ view:NSView,context:Context) { context.coordinator.shortcuts=shortcuts; context.coordinator.action=action }
    static func dismantleNSView(_ view:NSView,coordinator:Coordinator) { coordinator.stop() }
    @MainActor final class Coordinator {
        weak var view:NSView?
        var shortcuts:IrisShortcutStore?
        var action:(()->Void)?
        private var monitor:Any?
        func start() {
            monitor=NSEvent.addLocalMonitorForEvents(matching:.keyDown) { [weak self] event in
                guard let self, let window=self.view?.window, event.window === window, window.isKeyWindow, self.shortcuts?.matchesDismiss(event) == true else { return event }
                self.action?(); return nil
            }
        }
        func stop() { if let monitor { NSEvent.removeMonitor(monitor) }; monitor=nil }
    }
}
