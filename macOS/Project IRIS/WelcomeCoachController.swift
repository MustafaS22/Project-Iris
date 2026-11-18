import AppKit
import SwiftUI
import ApplicationServices
import Combine

/// Temporary coaching belongs beside the surface being learned, not inside a second app shell.
@MainActor final class WelcomeCoachController {
    private let iris: IrisOrchestrator
    private let panel = IrisPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var practice: NSWindow?
    private var anchor: CGRect = .zero
    private var userPlaced = false
    private var dragStart: (origin: CGPoint, pointer: CGPoint)?
    init(iris: IrisOrchestrator) {
        self.iris = iris
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: WelcomeCoachView(iris: iris, journey: iris.welcome))
    }
    func update(near target: CGRect? = nil) {
        guard iris.welcome.active else { hide(); return }
        if iris.welcome.progress.stage != .floating { practice?.orderOut(nil) }
        if let target { anchor = target }
        let reference = userPlaced ? CGPoint(x: panel.frame.midX, y: panel.frame.midY) : CGPoint(x: anchor.midX, y: anchor.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(reference) } ?? NSScreen.main
        guard let screen else { return }
        let base = anchor == .zero ? CGRect(x: screen.visibleFrame.maxX - 180, y: screen.visibleFrame.maxY - 140, width: 80, height: 70) : anchor
        guard dragStart == nil else { return }
        let safe = screen.visibleFrame.insetBy(dx: 8, dy: 8), size = WelcomeCoachMetrics.size(iris.welcome.progress.stage)
        var frame = WelcomeCoachPlacement.frame(near: base, size: size, bounds: safe)
        if userPlaced {
            let kept = CGRect(origin: panel.frame.origin, size: size)
            if safe.contains(kept), !kept.intersects(base) { frame = kept }
        } else if iris.welcome.progress.stage != .floating {
            let lowerTop = safe.minY + safe.height * 0.68
            let lower = CGRect(x: frame.minX, y: max(safe.minY + 12, min(frame.minY, lowerTop - frame.height)), width: frame.width, height: frame.height)
            if !lower.intersects(base) { frame = lower }
        }
        if panel.isVisible { panel.setFrame(frame, display: true) }
        else {
            panel.setFrame(frame, display: true); panel.alphaValue = IrisMotion.reduced ? 1 : 0
            panel.orderFrontRegardless()
            if !IrisMotion.reduced { NSAnimationContext.runAnimationGroup { context in context.duration = 0.22; panel.animator().alphaValue = 1 } }
        }
    }
    func moveFromPointer(ending: Bool) {
        guard panel.isVisible else { return }
        if ending { dragStart = nil; userPlaced = true; update(); return }
        let pointer = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (panel.frame.origin, pointer) }
        guard let start = dragStart, let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main else { return }
        let safe = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let x = start.origin.x + pointer.x - start.pointer.x, y = start.origin.y + pointer.y - start.pointer.y
        panel.setFrameOrigin(CGPoint(x: min(max(x, safe.minX), safe.maxX - panel.frame.width), y: min(max(y, safe.minY), safe.maxY - panel.frame.height)))
        userPlaced = true
    }
    func showPractice() {
        guard iris.welcome.active, iris.welcome.progress.stage == .floating else { return }
        if practice == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 470), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isOpaque = false; window.backgroundColor = .clear
            window.title = "Iris practice canvas"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: WelcomePracticeCanvas(iris: iris, journey: iris.welcome))
            window.center(); practice = window
        }
        practice?.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    func hide() { panel.orderOut(nil); if iris.welcome.progress.stage != .floating || !iris.welcome.active { practice?.orderOut(nil) } }
    func close() { panel.close(); practice?.close(); practice = nil }
}

enum WelcomeCoachMetrics {
    static func size(_ stage: WelcomeStage) -> CGSize {
        switch stage {
        case .interview: CGSize(width: 360, height: 316)
        case .notch: CGSize(width: 322, height: 332)
        case .floating: CGSize(width: 322, height: 292)
        case .drafting: CGSize(width: 322, height: 288)
        case .explore: CGSize(width: 340, height: 310)
        case .review: CGSize(width: 380, height: 408)
        case .complete: CGSize(width: 322, height: 228)
        }
    }
}
struct WelcomeCoachView: View {
    @ObservedObject var iris: IrisOrchestrator
    @ObservedObject var journey: WelcomeJourney
    @State private var typed = ""
    private var acceptsAnswer: Bool { [.interview, .notch, .floating].contains(journey.progress.stage) }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IrisAvatar(state: journey.celebrating ? .celebration : iris.state, color: iris.accent, size: 24, animated: true)
                Text(journey.progress.stage == .interview ? "Let’s meet." : journey.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer()
                Button { journey.previous() } label: { Image(systemName: "chevron.left") }.buttonStyle(.plain).accessibilityLabel("Previous lesson")
                Button { iris.restartOnboarding?() } label: { Image(systemName: "pause.fill") }.buttonStyle(.plain).accessibilityLabel("Pause introduction")
            }.foregroundStyle(IrisDesign.secondary).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3).onChanged { _ in journey.moveCoach?(false) }.onEnded { _ in journey.moveCoach?(true) })
                .help("Drag this header to move the guide")
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(journey.progress.stage == .interview || journey.progress.stage == .review ? journey.question : journey.progress.cue).font(.system(size: 16, weight: .medium)).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    if journey.progress.stage == .notch { WelcomeKeys(feedback: journey.keys, accent: iris.accent) }
                    content
                    if let issue = journey.issue ?? iris.voice.speechError { Text(issue).font(.system(size: 11)).foregroundStyle(.orange) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2)
            }
            if journey.busy || iris.busy { HStack(spacing: 8) { ProgressView().controlSize(.mini); Text(iris.requestPhase.isEmpty ? "Putting that together…" : iris.requestPhase).font(.system(size: 11)).foregroundStyle(IrisDesign.secondary) } }
            if acceptsAnswer {
                if !journey.transcript.isEmpty { Text("You · " + journey.transcript).font(.system(size: 11)).foregroundStyle(IrisDesign.secondary).lineLimit(1) }
                HStack(spacing: 8) {
                    Button { journey.listen() } label: { Image(systemName: iris.voice.listening ? "stop.fill" : "mic.fill").frame(width: 25, height: 28) }.buttonStyle(.plain).foregroundStyle(iris.accent).accessibilityLabel(iris.voice.listening ? "Stop listening" : "Speak to Iris")
                    TextField(iris.voice.listening ? "Listening…" : "Or type here…", text: $typed).textFieldStyle(.plain).font(.system(size: 12)).onSubmit(send)
                    Button(action: send) { Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold)) }.buttonStyle(.plain).foregroundStyle(iris.accent).disabled(typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityLabel("Send answer")
                }.padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10)).disabled(journey.busy || iris.busy)
            }
            HStack {
                if journey.progress.stage != .review { Button("Skip") { journey.next(skipping: true) }.buttonStyle(.plain).foregroundStyle(IrisDesign.secondary) }
                Spacer()
                if journey.progress.stage == .review { Button("Let’s begin") { journey.finish() }.buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(iris.accent) }
                else if journey.progress.canAdvance {
                    Button("Take my time") { journey.hold() }.buttonStyle(.plain).foregroundStyle(IrisDesign.secondary)
                    Button("Continue") { journey.next() }.buttonStyle(.plain).fontWeight(.semibold).foregroundStyle(iris.accent)
                } else if journey.progress.stage == .interview { Text("\(journey.progress.questionIndex + 1) of 4 · skip anything personal").foregroundStyle(IrisDesign.secondary) }
            }.font(.system(size: 11)).disabled(journey.busy || iris.busy)
        }.padding(20).frame(width: WelcomeCoachMetrics.size(journey.progress.stage).width, height: WelcomeCoachMetrics.size(journey.progress.stage).height)
            .background { WelcomeMaterial(); Color.black.opacity(0.22) }.clipShape(RoundedRectangle(cornerRadius: 18)).foregroundStyle(IrisDesign.text).preferredColorScheme(.dark)
            .animation(IrisMotion.reduced ? nil : .easeInOut(duration: 0.2), value: journey.progress.stage)
    }
    @ViewBuilder private var content: some View {
        switch journey.progress.stage {
        case .notch:
            if !journey.progress.notchOpened { Button("Open it for me") { journey.openNotchByClick() }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(iris.accent) }
            else if !journey.progress.canAdvance {
                Button("Make my first plan") { journey.submit(journey.progress.starterPrompt) }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(iris.accent)
                Text("Or ask your own question. Your answer appears in the normal Iris chat.").font(.system(size: 11)).foregroundStyle(IrisDesign.secondary)
            } else { Button("Read my answer in the notch") { showReply() }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(iris.accent) }
        case .floating:
            if !journey.progress.floatingOpened || journey.keys.confirmed { WelcomeKeys(feedback: journey.keys, accent: iris.accent) }
            else if !journey.progress.floatingDragged { Label("Click and hold my face, then move it", systemImage: "hand.draw.fill").font(.caption).foregroundStyle(iris.accent) }
            else {
                HStack(spacing: 18) { Button("Try the canvas") { journey.openPracticeCanvas?() }; Button("Type to floating Iris") { iris.openFloatingTyping?() } }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold)).foregroundStyle(iris.accent)
            }
            if !journey.answer.isEmpty { Button("Read my reply") { showReply() }.buttonStyle(.plain).font(.caption).foregroundStyle(iris.accent) }
        case .drafting:
            if !UserDefaults.standard.bool(forKey: InlineDraftController.enabledKey) {
                Button("Enable double-tap drafting") { UserDefaults.standard.set(true, forKey: InlineDraftController.enabledKey); InlineDraftController.shared.reconcileMonitors(); iris.objectWillChange.send() }.buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(iris.accent)
            } else if !AXIsProcessTrusted() {
                Text("Accessibility is needed for insertion. Enable it in Iris Settings → Privacy & access, or skip this lesson.").font(.system(size: 11)).foregroundStyle(IrisDesign.secondary)
                Button("Open Iris settings") { iris.showWorkspace(.settings) }.buttonStyle(.plain).font(.caption).foregroundStyle(iris.accent)
            } else {
                WelcomeKeys(feedback: journey.keys, accent: iris.accent)
                Button("Open a practice draft in TextEdit") { iris.showDraftPractice?() }.buttonStyle(.plain).font(.caption.weight(.semibold)).foregroundStyle(iris.accent)
            }
        case .explore:
            Text("@ can bring knowledge into a question or create a website, document or image. Creations stay in Library; agents handle bigger jobs.").font(.system(size: 12)).lineSpacing(3).foregroundStyle(IrisDesign.secondary)
            Button("Try @ in chat") { iris.showWorkspace(.today) }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold)).foregroundStyle(iris.accent)
            HStack(spacing: 18) { Button("Connect a source") { iris.showWorkspace(.connections) }; Button("Make it mine") { iris.showWorkspace(.settings) } }.buttonStyle(.plain).font(.caption).foregroundStyle(iris.accent)
        case .review:
            if journey.progress.starterPlan != nil { Toggle("Keep my plan in Knowledge", isOn: $journey.keepStarterPlan).font(.system(size: 12)) }
            ForEach(journey.progress.savedDetails, id: \.0) { detail in
                VStack(alignment: .leading, spacing: 6) {
                    Toggle(detail.0 == "name" ? "My name" : detail.0 == "work" ? "Education & work" : detail.0 == "project" ? "My focus" : "How to help me", isOn: Binding(get: { journey.consentToSave.contains(detail.0) }, set: { if $0 { journey.consentToSave.insert(detail.0) } else { journey.consentToSave.remove(detail.0) } })).font(.system(size: 12, weight: .medium))
                    TextField("Edit before saving", text: Binding(get: { journey.progress.answers[detail.0] ?? "" }, set: { journey.progress.answers[detail.0] = String($0.prefix(480)) }), axis: .vertical).textFieldStyle(.plain).font(.system(size: 12)).padding(8).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        default: EmptyView()
        }
    }
    private func showReply() { journey.hold(); iris.tab = .ask; iris.returnToNotch?() }
    private func send() { let text = typed.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; typed = ""; journey.submit(text) }
}

struct WelcomePracticeCanvas: View {
    @ObservedObject var iris: IrisOrchestrator
    @ObservedObject var journey: WelcomeJourney
    @State private var frames: [String: CGRect] = [:]
    @State private var reveal: CGFloat = 0
    @Environment(\.irisReduceMotion) private var reducedMotion
    private let items = [("sun", "Sun", "sun.max.fill", 0.27, 0.57, 60.0), ("earth", "Earth", "globe.europe.africa.fill", 0.67, 0.48, 42.0), ("moon", "Moon", "moon.fill", 0.84, 0.20, 24.0)]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Point at what you’re curious about.").font(.system(size: 27, weight: .semibold)).tracking(-0.6)
            Text("Choose the Sun, Earth or Moon. I’ll draw around it and explain.").font(.system(size: 14)).foregroundStyle(IrisDesign.secondary)
            GeometryReader { geometry in
                ZStack {
                    Ellipse().stroke(iris.accent.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 6])).frame(width: geometry.size.width * 0.81, height: 126).position(x: geometry.size.width * 0.47, y: geometry.size.height * 0.57).accessibilityHidden(true)
                    ForEach(items, id: \.0) { item in
                        Button {
                            journey.explainPractice(item.0); reveal = 0
                            if let rect = frames[item.0] { iris.welcomePointAt?(rect) }
                            withAnimation(reducedMotion ? nil : .easeOut(duration: 0.7)) { reveal = 1 }
                        } label: {
                            VStack(spacing: 10) {
                                Image(systemName: item.2).font(.system(size: item.5, weight: .regular)).foregroundStyle(item.0 == "sun" ? iris.accent : item.0 == "earth" ? Color(red: 0.42, green: 0.66, blue: 0.80) : IrisDesign.text)
                                    .frame(width: item.5 + 22, height: item.5 + 22)
                                    .overlay { if journey.progress.demoTarget == item.0 { Circle().trim(from: 0, to: reducedMotion ? 1 : reveal).stroke(iris.accent, style: StrokeStyle(lineWidth: 2.2, lineCap: .round)).padding(-7).allowsHitTesting(false) } }
                                    .background(WelcomeScreenAnchor { frame in if frames[item.0] != frame { frames[item.0] = frame; if journey.progress.demoTarget == item.0 { iris.welcomePointAt?(frame) } } })
                                Text(item.1).font(.system(size: 12, weight: .medium)).foregroundStyle(IrisDesign.secondary)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).position(x: geometry.size.width * item.3, y: geometry.size.height * item.4).accessibilityLabel("Explain \(item.1)")
                    }
                }
            }.frame(height: 175)
            if journey.progress.demoTarget != nil { Text(journey.question).font(.system(size: 13)).lineSpacing(3).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading).transition(.opacity) }
            Spacer(minLength: 0)
            HStack {
                Text("Practice illustration · not to scale").font(.caption).foregroundStyle(IrisDesign.secondary)
                Spacer()
                Button("Ask something yourself") { iris.openFloatingTyping?() }.buttonStyle(IrisActionStyle(primary: true))
            }
        }.padding(34).padding(.top, 16).frame(width: 660, height: 470).background { WelcomeMaterial(); Color.black.opacity(0.16) }.foregroundStyle(IrisDesign.text).preferredColorScheme(.dark).environment(\.irisControlAccent, iris.accent).onAppear { if journey.progress.demoTarget != nil { reveal = 1 } }
    }
}
private struct WelcomeScreenAnchor: NSViewRepresentable {
    let report: (CGRect) -> Void
    func makeNSView(context: Context) -> Probe { let view = Probe(); view.report = report; return view }
    func updateNSView(_ view: Probe, context: Context) { view.report = report; view.needsLayout = true }
    final class Probe: NSView {
        var report: ((CGRect) -> Void)?
        private var observer: NSObjectProtocol?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
            if let window { observer = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in MainActor.assumeIsolated { self?.publish() } } }
            publish()
        }
        override func layout() { super.layout(); publish() }
        private func publish() { guard let window, bounds.width > 0 else { return }; let rect = window.convertToScreen(convert(bounds, to: nil)); DispatchQueue.main.async { [weak self] in self?.report?(rect) } }
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
}
