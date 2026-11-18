import AppKit
import Combine
import Carbon
import SwiftUI

/// Only the shortcut currently being taught is observed. No text or other keys are retained.
@MainActor final class WelcomeKeyFeedback: ObservableObject {
    @Published private(set) var flags: NSEvent.ModifierFlags = []
    @Published private(set) var mainKeyDown = false
    @Published private(set) var confirmed = false
    @Published private(set) var chord: IrisKeyChord?
    @Published private(set) var draftKey: InlineDraftKey?
    var onMatched: ((IrisKeyChord) -> Void)?
    private var local: Any?
    private var global: Any?
    private var timer: Timer?
    private var pulse: Task<Void, Never>?
    func expect(_ chord: IrisKeyChord?, draft: InlineDraftKey? = nil) {
        stop(); self.chord = chord; draftKey = draft
        guard chord != nil || draft != nil, !ProcessInfo.processInfo.arguments.contains("--iris-validation") else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in MainActor.assumeIsolated { self?.receive(event) }; return event }
        global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in MainActor.assumeIsolated { self?.receive(event) } }
        // Modifier polling also works before Accessibility is enabled. The registered hotkey
        // confirms the main key, so the tour does not demand Input Monitoring access.
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in MainActor.assumeIsolated {
            guard let self else { return }; let value = NSEvent.modifierFlags.intersection([.control, .option, .command, .shift])
            if self.flags != value { self.flags = value }
        } }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    private func receive(_ event: NSEvent) {
        if let draftKey, event.type == .flagsChanged, event.keyCode == draftKey.keyCode { mainKeyDown = event.modifierFlags.rawValue & draftKey.deviceMask != 0 }
        else if let chord, UInt32(event.keyCode) == chord.keyCode, event.type == .keyDown || event.type == .keyUp {
            mainKeyDown = event.type == .keyDown
            if event.type == .keyDown, !event.isARepeat, IrisKeyChord.carbonFlags(event.modifierFlags) == chord.modifiers { onMatched?(chord) }
        }
    }
    func confirm() {
        guard chord != nil || draftKey != nil else { return }
        pulse?.cancel(); confirmed = true
        pulse = Task { [weak self] in do { try await Task.sleep(for: .milliseconds(2800)); self?.confirmed = false } catch { } }
    }
    func stop() {
        pulse?.cancel(); pulse = nil; timer?.invalidate(); timer = nil
        if let local { NSEvent.removeMonitor(local) }; if let global { NSEvent.removeMonitor(global) }
        local = nil; global = nil; flags = []; mainKeyDown = false; confirmed = false
    }
    var caps: [(Int, String, Bool)] {
        if let draftKey { return [(0, draftKey.title, mainKeyDown || confirmed), (1, "× 2", confirmed)] }
        guard let chord else { return [] }
        let modifiers: [(UInt32, NSEvent.ModifierFlags, String)] = [(UInt32(controlKey), .control, "⌃"), (UInt32(optionKey), .option, "⌥"), (UInt32(shiftKey), .shift, "⇧"), (UInt32(cmdKey), .command, "⌘")]
        var result = modifiers.enumerated().compactMap { i, item -> (Int, String, Bool)? in chord.modifiers & item.0 != 0 ? (i, item.2, flags.contains(item.1) || confirmed) : nil }
        result.append((4, chord.keyName, mainKeyDown || confirmed)); return result
    }
}
struct WelcomeKeys: View {
    @ObservedObject var feedback: WelcomeKeyFeedback
    let accent: Color
    @Environment(\.irisReduceMotion) private var reduced
    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                ForEach(feedback.caps, id: \.0) { cap in
                    Text(cap.1).font(.system(size: 15, weight: .semibold)).frame(minWidth: 36, minHeight: 34).padding(.horizontal, cap.1.count > 2 ? 10 : 2)
                        .foregroundStyle(cap.2 ? Color.black : IrisDesign.text)
                        .background(cap.2 ? accent : Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(cap.2 ? accent : .white.opacity(0.12), lineWidth: 1))
                        .offset(y: cap.2 ? 1.5 : 0)
                        .animation(reduced ? nil : .spring(response: 0.18, dampingFraction: 0.8), value: cap.2)
                        .accessibilityLabel(cap.1 + (cap.2 ? ", pressed" : ", released"))
                }
                if feedback.caps.isEmpty { Text("Shortcut is off").font(.caption).foregroundStyle(IrisDesign.secondary) }
            }
            if feedback.confirmed { Text("Shortcut received").font(.system(size: 10, weight: .medium)).foregroundStyle(accent).transition(.opacity) }
        }.animation(reduced ? nil : .easeOut(duration: 0.18), value: feedback.confirmed)
    }
}
/// Genuine desktop blur rather than a translucent painted rectangle.
struct WelcomeMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        view.appearance = NSAppearance(named: .vibrantDark)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { }
}
