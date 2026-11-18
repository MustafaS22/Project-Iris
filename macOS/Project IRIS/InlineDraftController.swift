import AppKit
import ApplicationServices
import Combine
import SwiftUI
import QuartzCore

@MainActor final class InlineDraftController: ObservableObject {
    var onVerifiedInsertion: (() -> Void)?
    static let shared = InlineDraftController()
    static let enabledKey = "IrisInlineDraftEnabled"
    static let modifierKey = "IrisInlineDraftModifier"
    static let nearbyKey = "IrisInlineDraftNearbyText"

    enum Phase: Equatable {
        case hidden, prompt, reading, writing, inserting, inserted, recovery, failed(String)
        var isFailure: Bool { if case .failed = self { return true }; return false }
        var avatar: IrisState {
            switch self { case .prompt: .attention; case .reading: .vision; case .writing, .inserting: .thinking; case .inserted: .celebration; case .recovery: .attention; case .failed: .warning; case .hidden: .idle }
        }
        var caption: String {
            switch self { case .prompt: ""; case .reading: "Reading this field…"; case .writing: "Drafting…"; case .inserting: "Inserting…"; case .inserted: "Draft inserted"; case .recovery: "Couldn’t verify insertion"; case .failed(let message): message; case .hidden: "" }
        }
    }

    @Published private(set) var phase: Phase = .hidden
    @Published private(set) var visible = false
    @Published private(set) var arrivalActive = false
    @Published private(set) var accent = Color.accentColor
    private var configuration: (() -> (Preferences, Color)?)?
    private var gesture = InlineDraftGesture()
    private var target: InlineDraftTarget?
    private var panel: InlineDraftPanel?
    private var arrivalPanel: InlineDraftPanel?
    private var arrival: Task<Void, Never>?
    private var capturing = false
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var work: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var removal: Task<Void, Never>?
    private var lifetime = InlineDraftLifetime()
    private var generation: UUID { lifetime.id }
    @Published private(set) var previewOnly = false
    private var retainedDraft: String?
    private var capturedContext = ""
    private var capturedInstruction = ""
    private var capturedPersonalContext = ""
    var personalContext: ((String) -> String)?
    @Published private(set) var promptQuestion = InlineWriting.direction

    func configure(_ configuration: @escaping () -> (Preferences, Color)?) {
        self.configuration = configuration
        reconcileMonitors()
    }

    func reconcileMonitors() {
        gesture.reset()
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        guard enabled, AXIsProcessTrusted(), configuration != nil else { shutdownMonitors(); return }
        guard localMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.gesture.reset()
                switch self.lifetime.activation(frontIsIris: NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier,
                                                frontIsTarget: self.target?.app.processIdentifier == NSWorkspace.shared.frontmostApplication?.processIdentifier) {
                case .keep: break
                case .previewOnly: self.keepAsPreview()
                case .dismissPrompt: self.finish()
                }
            }
        }
    }

    private func shutdownMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        globalMonitor = nil; localMonitor = nil; activationObserver = nil
        if phase != .hidden { finish() }
    }
    func shutdown() { shutdownMonitors(); panel?.orderOut(nil); arrival?.cancel(); arrivalPanel?.orderOut(nil); configuration = nil }

    private func handle(_ event: NSEvent) {
        if event.type != .flagsChanged {
            gesture.reset()
            if capturing { failCapture("Draft paused · the field changed; double tap again when ready"); return }
            if phase == .writing {
                if event.type == .keyDown && event.keyCode == 53 { cancelDraft("Draft cancelled") }
                else { keepAsPreview() }
            }
            return
        }
        let key = InlineDraftKey(rawValue: UserDefaults.standard.string(forKey: Self.modifierKey) ?? "") ?? .command
        let major = event.modifierFlags.intersection([.command, .control, .option, .shift, .function])
        let expected: NSEvent.ModifierFlags = key == .command ? .command : .option
        let leftMask: UInt = key == .command ? 0x08 : 0x20
        guard event.keyCode == key.keyCode, event.modifierFlags.rawValue & leftMask == 0,
              major.isEmpty || major == expected else { gesture.reset(); return }
        let down = event.modifierFlags.rawValue & key.deviceMask != 0
        if gesture.update(down: down, at: event.timestamp) { summon() }
    }

    private func summon() {
        if phase == .writing { finish(); return }
        guard phase != .prompt, phase != .inserting, AXIsProcessTrusted(), let (preferences, color) = configuration?() else { return }
        // A previous success/error's dismissal must never hide this new invocation.
        removal?.cancel(); removal = nil; timer?.cancel(); timer = nil; work?.cancel(); work = nil
        previewOnly = false; target = nil; retainedDraft = nil; capturedContext = ""; capturedInstruction = ""; capturedPersonalContext = ""
        accent = color
        showArrival(at: NSEvent.mouseLocation)
        let invocation = UUID()
        lifetime.begin(id: invocation); capturing = true
        let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
        work = Task { [weak self] in
            guard let self else { return }
            var found: InlineDraftTarget?
            for delay in [0, 80, 150, 250] {
                if delay > 0 { try? await Task.sleep(for: .milliseconds(delay)) }
                guard !Task.isCancelled, self.lifetime.accepts(invocation) else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
                    self.failCapture("Draft paused · the active app changed"); return
                }
                found = InlineDraftTarget.focused()
                if found != nil { break }
            }
            guard !Task.isCancelled, self.lifetime.accepts(invocation) else { return }
            self.capturing = false
            guard let target = found else {
                self.present(.failed(InlineDraftTarget.lastFailure), at: NSEvent.mouseLocation)
                self.dismissAfter(.seconds(6)); return
            }
            await self.prepare(target, preferences: preferences)
        }
    }

    private func prepare(_ target: InlineDraftTarget, preferences: Preferences) async {
        let invocation = generation
        capturing = true
        defer { if generation == invocation { capturing = false } }
        retainedDraft = nil
        capturedInstruction = ""; capturedPersonalContext = ""
        self.target = target
        present(.reading, at: target.caret)
        let existing = InlineWriting.isEmptyField(target.original ?? "") ? "" : (target.original ?? "")
        let canFillProfile = InlineDraftModel.profileValue(preferences: preferences, target: target) != nil
        let usesContext = UserDefaults.standard.object(forKey: Self.nearbyKey) as? Bool ?? true
        capturedContext = usesContext && !canFillProfile ? await target.nearbyText() : ""
        if usesContext, existing.isEmpty, target.selected.isEmpty, !canFillProfile, InlinePersonalContext.needsVisualText(capturedContext) {
            let visualText = await InlineScreenContext.text(around: target)
            if !visualText.isEmpty { capturedContext += "\n" + visualText }
        }
        if usesContext, UserDefaults.standard.object(forKey: "IrisInlineDraftPersonalContext") as? Bool ?? true, existing.isEmpty, target.selected.isEmpty {
            capturedPersonalContext = personalContext?(target.fieldLabel + "\n" + capturedContext) ?? ""
        }
        guard !Task.isCancelled, generation == invocation else { return }
        guard target.isStillFocused() else { failCapture("Draft paused · the field changed; double tap again"); return }
        promptQuestion = InlineWriting.direction
        if target.selected.isEmpty, existing.isEmpty, capturedContext.isEmpty, target.fieldLabel.isEmpty, !canFillProfile {
            present(.prompt, at: target.caret)
        } else {
            begin(preferences: preferences, instruction: nil, nearby: capturedContext, returnFocus: false)
        }
    }

    func submit(_ instruction: String) {
        let text = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phase == .prompt, !text.isEmpty, let (preferences, _) = configuration?() else { return }
        capturedInstruction = String((capturedInstruction + "\nClarification asked: " + promptQuestion + "\nUser direction: " + String(text.prefix(1_600))).suffix(3_200))
        begin(preferences: preferences, instruction: capturedInstruction, nearby: capturedContext, returnFocus: true)
    }

    func cancelPrompt() {
        guard phase == .prompt else { return }
        if let app = target?.app { NSApp.yieldActivation(to: app); app.activate() }
        finish()
    }

    private func begin(preferences: Preferences, instruction: String?, nearby: String, returnFocus: Bool) {
        guard let target else { return }
        let id = UUID()
        removal?.cancel(); removal = nil; timer?.cancel(); timer = nil
        lifetime.begin(id: id); lifetime.stage = .writing; previewOnly = false
        // Mark writing before activate(): macOS can deliver activation synchronously.
        phase = .writing
        if returnFocus {
            lifetime.restoreForWriting()
            panel?.orderOut(nil)
            NSApp.yieldActivation(to: target.app)
            target.app.activate()
        }
        present(.writing, at: target.caret)
        work = Task { [weak self] in
            guard let self else { return }
            do {
                if returnFocus {
                    let end = ProcessInfo.processInfo.systemUptime + 1.25
                    while !target.isStillFocused(),
                          ProcessInfo.processInfo.systemUptime < end { try await Task.sleep(for: .milliseconds(35)) }
                    self.lifetime.restoredFocus()
                }
                try Task.checkCancellation()
                if !target.isStillFocused() { self.keepAsPreview() }
                let result = try await InlineDraftModel.generate(preferences: preferences, target: target, instruction: instruction, nearby: nearby, knownContext: self.capturedPersonalContext)
                try Task.checkCancellation()
                guard self.generation == id else { return }
                self.timer?.cancel(); self.timer = nil
                let draft: String
                switch result {
                case .question(let question):
                    self.promptQuestion = question
                    self.work = nil
                    self.present(.prompt, at: target.caret)
                    return
                case .draft(let text): draft = text
                }
                self.retainedDraft = draft
                guard self.lifetime.mayAutoInsert, target.isStillFocused() else { self.complete(.recovery, id: id); return }
                self.phase = .inserting; self.lifetime.stage = .inserting
                let delivered = await target.insert(draft)
                try Task.checkCancellation()
                guard self.generation == id else { return }
                if delivered {
                    self.onVerifiedInsertion?()
                    self.complete(.inserted, id: id)
                } else {
                    self.retainedDraft = draft
                    self.complete(.recovery, id: id)
                }
            } catch is CancellationError {
                if self.generation == id { self.finish() }
            } catch {
                self.complete(.failed("Couldn’t draft: " + String(error.localizedDescription.prefix(220))), id: id)
            }
        }
        timer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(55))
            guard !Task.isCancelled, let self, self.generation == id else { return }
            self.work?.cancel()
            self.complete(.failed("Draft timed out"), id: id)
        }
    }

    private func complete(_ outcome: Phase, id: UUID) {
        guard generation == id else { return }
        let anchor = target?.caret ?? NSEvent.mouseLocation
        lifetime.finish(); work = nil; timer?.cancel(); timer = nil
        if outcome != .recovery { target = nil; capturedContext = ""; capturedInstruction = ""; capturedPersonalContext = "" }
        present(outcome, at: anchor)
        panel?.ignoresMouseEvents = outcome != .recovery
        if outcome != .recovery { dismissAfter(outcome == .inserted ? .milliseconds(900) : .seconds(9)) }
    }
    private func cancelDraft(_ message: String) {
        work?.cancel()
        complete(.failed(message), id: generation)
    }

    private func keepAsPreview() {
        lifetime.detach(); previewOnly = true
    }
    private func failCapture(_ message: String) {
        work?.cancel(); work = nil; capturing = false
        lifetime.finish()
        arrival?.cancel(); arrivalPanel?.orderOut(nil); arrivalPanel = nil; arrivalActive = false
        present(.failed(message), at: target?.caret ?? NSEvent.mouseLocation)
        dismissAfter(.seconds(6))
    }
    func retryRetainedDraft() {
        guard phase == .recovery, let target, let retainedDraft, !target.app.isTerminated else { return }
        removal?.cancel()
        lifetime.begin(); let id = generation
        lifetime.restoreForWriting()
        NSApp.yieldActivation(to: target.app); target.app.activate()
        present(.inserting, at: target.caret)
        work = Task { [weak self] in
            guard let self else { return }
            let deadline = ProcessInfo.processInfo.systemUptime + 1
            while !target.isStillFocused(), ProcessInfo.processInfo.systemUptime < deadline {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, self.lifetime.accepts(id) else { return }
            }
            self.lifetime.restoredFocus(); self.lifetime.stage = .inserting
            let inserted = await target.insert(retainedDraft)
            guard !Task.isCancelled, self.lifetime.accepts(id) else { return }
            self.complete(inserted ? .inserted : .recovery, id: id)
        }
    }
    func copyRetainedDraft() {
        guard phase == .recovery, let retainedDraft else { return }
        let board = NSPasteboard.general
        board.clearContents()
        if board.setString(retainedDraft, forType: .string) { finish() }
    }

    func dismissRetainedDraft() { if phase == .recovery { finish() } }

    private func dismissAfter(_ delay: Duration) {
        removal?.cancel()
        let ticket = generation
        removal = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.lifetime.accepts(ticket) else { return }
            self.finish()
        }
    }
    private func finish() {
        lifetime.finish(); capturing = false
        arrival?.cancel(); arrival = nil; arrivalPanel?.orderOut(nil); arrivalPanel = nil; arrivalActive = false
        work?.cancel(); work = nil; timer?.cancel(); timer = nil; removal?.cancel()
        target = nil; retainedDraft = nil; capturedContext = ""; capturedInstruction = ""; capturedPersonalContext = ""
        panel?.ignoresMouseEvents = true
        withAnimation(.easeOut(duration: 0.16)) { visible = false }
        let closing = generation
        removal = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(190))
            guard !Task.isCancelled, let self, self.lifetime.accepts(closing), !self.visible else { return }
            self.panel?.orderOut(nil)
            self.phase = .hidden
        }
    }

    private func showArrival(at cursor: CGPoint) {
        arrival?.cancel(); arrivalPanel?.orderOut(nil)
        let window = InlineDraftPanel(takesFocus: false)
        window.contentView = NSHostingView(rootView: InlineDraftArrival(color: accent).modifier(IrisAccessibility()))
        window.setFrame(CGRect(x: cursor.x - 42, y: cursor.y - 42, width: 84, height: 84), display: true)
        window.orderFrontRegardless(); arrivalPanel = window; arrivalActive = true
        arrival = Task { [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(IrisMotion.reduced ? 100 : 300))
            guard !Task.isCancelled else { return }
            window?.orderOut(nil)
            if let self, self.arrivalPanel === window { self.arrivalPanel = nil; self.arrival = nil; self.arrivalActive = false }
        }
    }

    private func present(_ next: Phase, at point: CGPoint) {
        removal?.cancel()
        let prompt = next == .prompt
        if panel == nil || panel?.takesFocus != prompt {
            panel?.orderOut(nil)
            let window = InlineDraftPanel(takesFocus: prompt)
            window.contentView = NSHostingView(rootView: InlineDraftOverlay(controller: self).modifier(IrisAccessibility()))
            panel = window
            visible = false
        }
        guard let panel else { return }
        phase = next
        if next == .prompt { lifetime.stage = .prompt }
        panel.ignoresMouseEvents = !prompt
        let bounds = NSScreen.screens.first(where: { $0.frame.contains(point) })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let size = CGSize(width: prompt ? 372 : next.isFailure ? 380 : next == .recovery ? 376 : 270, height: prompt ? 158 : next.isFailure ? 116 : next == .recovery ? 138 : 80)
        let x = min(max(bounds.minX + 8, point.x - 30), bounds.maxX - size.width - 8)
        let above = point.y + size.height + 9 <= bounds.maxY
        let y = min(max(bounds.minY + 8, above ? point.y + 8 : point.y - size.height - 8), bounds.maxY - size.height - 8)
        let frame = CGRect(origin: CGPoint(x: x, y: y), size: size)
        if panel.isVisible, visible, !IrisMotion.reduced {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else { panel.setFrame(frame, display: true) }
        if prompt {
            NSApp.activate()
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        let presentation = generation
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let self, self.lifetime.accepts(presentation), self.panel === panel, self.phase == next else { return }
            withAnimation(IrisMotion.reduced ? .easeOut(duration: 0.10) : .easeOut(duration: 0.16).delay(self.arrivalPanel == nil ? 0 : 0.13)) { self.visible = true }
        }
    }
}

@MainActor private final class InlineDraftPanel: NSPanel {
    let takesFocus: Bool
    override var canBecomeKey: Bool { takesFocus }
    override var canBecomeMain: Bool { false }
    init(takesFocus: Bool) {
        self.takesFocus = takesFocus
        super.init(contentRect: .zero, styleMask: takesFocus ? [.borderless] : [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false; backgroundColor = .clear; hasShadow = false
        level = .floating; hidesOnDeactivate = false; isReleasedWhenClosed = false
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        ignoresMouseEvents = !takesFocus
        animationBehavior = .none
    }
}

private struct InlineDraftOverlay: View {
    @ObservedObject var controller: InlineDraftController
    @Environment(\.irisReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var instruction = ""
    private var working: Bool { [.reading, .writing, .inserting].contains(controller.phase) }
    private var tint: Color { controller.phase.isFailure ? .orange : controller.accent }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IrisAvatar(state: controller.phase.avatar, color: tint, size: 27, animated: true, desktop: true,
                       guidance: controller.phase == .inserted ? CGSize(width: 0, height: 8) : nil)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 8) {
                if controller.phase == .prompt {
                    Text(controller.promptQuestion).font(.system(size: 12, weight: .medium)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        TextField("A little direction…", text: $instruction)
                            .textFieldStyle(.plain).font(.system(size: 12)).focused($focused)
                            .onSubmit { controller.submit(instruction) }
                        Button { controller.submit(instruction) } label: {
                            Image(systemName: "arrow.up").font(.system(size: 11, weight: .bold))
                                .frame(width: 26, height: 26).background(tint.opacity(0.20), in: Circle())
                        }.buttonStyle(.plain).foregroundStyle(tint)
                            .disabled(instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityLabel("Draft into focused field")
                    }
                    .padding(8).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
                    .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(tint.opacity(focused ? 0.4 : 0.15)) }
                } else if controller.phase == .recovery {
                    Text("Your draft is ready").font(.system(size: 12, weight: .semibold))
                    Text("Keep it, or try the field again.").font(.system(size: 11)).foregroundStyle(IrisDesign.secondary)
                    HStack(spacing: 8) {
                        Button("Copy draft") { controller.copyRetainedDraft() }
                        Button("Try inserting") { controller.retryRetainedDraft() }
                    }.buttonStyle(DraftSmallButton(color: tint))
                } else {
                    HStack(spacing: 8) {
                        Text(controller.phase == .writing && controller.previewOnly ? "Drafting a preview" : controller.phase.caption)
                            .font(.system(size: 12, weight: .medium)).lineLimit(controller.phase.isFailure ? 4 : 1)
                            .contentTransition(.opacity)
                        Spacer(minLength: 0)
                        if controller.phase == .inserted {
                            Image(systemName: "checkmark.circle.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                                .transition(.scale(scale: 0.8).combined(with: .opacity))
                        }
                    }.padding(.top, 3)
                    if working {
                        DraftActivityTrack(color: tint, reduceMotion: reduceMotion)
                            .frame(height: 3).padding(.top, 2).accessibilityHidden(true)
                    } else if controller.phase == .inserted {
                        Text("Ready in your field").font(.system(size: 10)).foregroundStyle(IrisDesign.secondary)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if controller.phase == .recovery {
                Button { controller.dismissRetainedDraft() } label: {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22)
                }.buttonStyle(.plain).foregroundStyle(IrisDesign.secondary).accessibilityLabel("Dismiss draft")
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.075))
                .overlay { RoundedRectangle(cornerRadius: 20).fill(LinearGradient(colors: [tint.opacity(0.075), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)) }
        }
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(LinearGradient(colors: [.white.opacity(0.17), tint.opacity(0.14), .white.opacity(0.055)], startPoint: .topLeading, endPoint: .bottomTrailing)) }
        .shadow(color: .black.opacity(0.26), radius: 9, y: 4)
        .foregroundStyle(IrisDesign.text)
        .scaleEffect(reduceMotion ? 1 : controller.visible ? 1 : 0.96, anchor: .bottomLeading)
        .offset(y: reduceMotion ? 0 : controller.visible ? 0 : 5)
        .opacity(controller.visible ? 1 : 0)
        .animation(reduceMotion ? .easeOut(duration: 0.1) : .spring(response: 0.3, dampingFraction: 0.88), value: controller.visible)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: controller.phase)
        .padding(7).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .onAppear { focused = controller.phase == .prompt }
        .onExitCommand { controller.cancelPrompt() }
    }
}

private struct DraftSmallButton: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(color.opacity(configuration.isPressed ? 0.24 : 0.11), in: Capsule())
    }
}

private struct DraftActivityTrack: View {
    let color: Color
    let reduceMotion: Bool
    @State private var began = Date()
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { time in
            let progress = (sin(time.date.timeIntervalSince(began) * 2.7 - .pi / 2) + 1) / 2
            GeometryReader { geo in
                Capsule().fill(color.opacity(0.12))
                Capsule().fill(LinearGradient(colors: [color.opacity(0.3), color, color.opacity(0.3)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * 0.32)
                    .offset(x: reduceMotion ? 0 : geo.size.width * 0.68 * progress)
            }.clipped()
        }
    }
}

#if DEBUG
extension InlineDraftController {
    static func validateVisuals() async {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("IrisDraftVisualValidation")
        do {
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            let preview = InlineDraftController()
            preview.visible = true; preview.accent = Color(red: 0.76, green: 0.81, blue: 0.56)
            for (name, phase, size) in [
                ("drafting", Phase.writing, NSSize(width: 270, height: 80)),
                ("clarification", Phase.prompt, NSSize(width: 372, height: 158)),
                ("inserted", Phase.inserted, NSSize(width: 270, height: 80)),
                ("recovery", Phase.recovery, NSSize(width: 376, height: 138))
            ] {
                preview.phase = phase
                preview.promptQuestion = "What time would you like to suggest?"
                try await IrisAgentValidation.render(InlineDraftOverlay(controller: preview), size: size, to: output.appendingPathComponent(name + ".png"))
            }
            NSLog("IRIS_DRAFT_VISUAL_PASS %@", output.path)
        } catch { NSLog("IRIS_DRAFT_VISUAL_FAILED %@", error.localizedDescription) }
        NSApp.terminate(nil)
    }
}
#endif
