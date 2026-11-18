import AppKit
import SwiftUI
import Combine

@MainActor final class AgentPeekModel: ObservableObject {
    @Published var state: AgentPeekState
    init(selectedID: UUID? = nil) { state = AgentPeekState(selectedID: selectedID) }
    func hover(_ id: UUID, inside: Bool) { state.hover(id, inside: inside, at: ProcessInfo.processInfo.systemUptime) }
    func advance(at time: TimeInterval) {
        var next = state; next.advance(at: time)
        if next.selectedID != state.selectedID { state = next }
    }
    func click(_ id: UUID) { state.click(id) }
    func reset() { if state.selectedID != nil || state.hoveredID != nil { state = AgentPeekState() } }
}

/// The window hugs the visible avatars. Expansion grows downwards, keeping the row stationary.
@MainActor final class AgentCornerController {
    private let iris: IrisOrchestrator
    private let peek = AgentPeekModel()
    private var panel: NSPanel?
    private var timer: Timer?
    private var gesture = AgentCornerGesture()
    private var entered: TimeInterval?
    private var visibleUntil: TimeInterval = 0
    private var shown = false
    private var collapseAfter: TimeInterval?
    init(iris: IrisOrchestrator) {
        self.iris = iris
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in Task { @MainActor [weak self] in self?.tick() } }
    }
    func close() { timer?.invalidate(); timer = nil; panel?.orderOut(nil); panel = nil }
    private func tick() {
        guard !iris.needsOnboarding, !iris.onboardingPresented, !iris.agents.active.isEmpty else { entered = nil; visibleUntil = 0; hide(); return }
        let mouse = NSEvent.mouseLocation, time = ProcessInfo.processInfo.systemUptime
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) else { hide(); return }
        let f = screen.visibleFrame
        let hotspot = NSRect(x: f.maxX-330, y: f.maxY-105, width: 330, height: 105)
        let shaken = gesture.sample(x: mouse.x, time: time, inCorner: NSRect(x: f.maxX-400, y: f.maxY-230, width: 400, height: 230).contains(mouse))
        if hotspot.contains(mouse) {
            if entered == nil { entered = time }
            if time-(entered ?? time) >= 0.3 { visibleUntil = time+2 }
        } else { entered = nil }
        if shaken { visibleUntil = time+4 }
        if shown, panel?.frame.contains(mouse) == true { visibleUntil = time+2 }
        peek.advance(at: time)
        var state = peek.state; state.retain(Set(iris.agents.active.map(\.id)))
        if state.selectedID != peek.state.selectedID { peek.state = state }
        if time < visibleUntil { show(on: screen) } else { hide() }
    }
    private func show(on screen: NSScreen) {
        if panel == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
            panel.level = .floating; panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            panel.contentView = NSHostingView(rootView: AgentCornerView(iris: iris, store: iris.agents, peek: peek))
            self.panel = panel
        }
        guard let panel else { return }
        let expanded = peek.state.selectedID != nil
        let now = ProcessInfo.processInfo.systemUptime
        if expanded { collapseAfter = nil }
        else if panel.frame.height > 80, collapseAfter == nil { collapseAfter = now + 0.28 }
        // Leave room for the detail's exit transition before shrinking the native window.
        let keepExpandedFrame = !expanded && (collapseAfter.map { now < $0 } ?? false)
        let width = max(expanded || keepExpandedFrame ? 316 : 0, CGFloat(min(6, iris.agents.active.count))*66+16)
        let target = NSRect(x: screen.visibleFrame.maxX-width-16, y: screen.visibleFrame.maxY-(expanded || keepExpandedFrame ? 292 : 80)-10, width: width, height: expanded || keepExpandedFrame ? 292 : 80)
        if panel.frame != target { panel.setFrame(target, display: true) }
        guard !shown else { return }
        shown = true; panel.alphaValue = 0; panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18; panel.animator().alphaValue = 1 }
    }
    private func hide() {
        guard shown, let panel else { return }; shown = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.18
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in if self?.shown == false { self?.panel?.orderOut(nil); self?.peek.reset() } }
        }
    }
}

struct AgentBackdrop: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .hudWindow; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct AgentCornerView: View {
    @ObservedObject var iris: IrisOrchestrator
    @ObservedObject var store: IrisAgentStore
    @ObservedObject var peek: AgentPeekModel
    @Environment(\.irisReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 2) {
                ForEach(Array(store.active.prefix(6))) { run in
                    Button { peek.click(run.id) } label: {
                        AgentAvatar(run: run, size: 48)
                            .shadow(color: .black.opacity(0.28), radius: 5, y: 3)
                            .frame(width: 64, height: 66)
                            .background { AgentBackdrop()
                                    .mask(RadialGradient(stops: [.init(color: .black.opacity(0.55), location: 0), .init(color: .black.opacity(0.3), location: 0.5), .init(color: .clear, location: 1)], center: .center, startRadius: 0, endRadius: 34))
                                    .opacity(0.5).allowsHitTesting(false) }
                            .contentShape(Ellipse())
                    }.buttonStyle(.plain).help("\(run.name) · click or hover to see progress")
                        .onHover { peek.hover(run.id, inside: $0) }
                        .accessibilityLabel("Show \(run.name)'s progress")
                }
            }.padding(.horizontal, 8)
            if let id = peek.state.selectedID, let run = store.run(id), run.status.active {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(run.name).font(.system(size: 15, weight: .semibold))
                        Text(run.status.title).font(.system(size: 10, weight: .medium)).foregroundStyle(run.color)
                        Spacer()
                        Button { peek.click(id) } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 24, height: 24) }.buttonStyle(.plain).help("Collapse agent")
                    }
                    Text(AgentPolicy.title(for: run.task)).font(.system(size: 12)).foregroundStyle(IrisDesign.secondary).lineLimit(2)
                    HStack(spacing: 8) { if run.status == .running { ProgressView().controlSize(.mini) }; Text(run.phase).font(.system(size: 12, weight: .medium)).foregroundStyle(run.color).lineLimit(2) }
                    if !run.partial.isEmpty { Text(verbatim: String(run.partial.replacingOccurrences(of: "#", with: "").prefix(220))).font(.system(size: 11)).foregroundStyle(IrisDesign.secondary).lineLimit(3) }
                    HStack {
                        Button("Open agent", systemImage: "arrow.up.right") { store.selectedID = id; iris.showWorkspace(.agents) }
                        Spacer()
                        Button("Stop", systemImage: "stop.fill") { store.stop(id) }
                    }.buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                }.padding(16).frame(width: 284, alignment: .leading)
                    .background { ZStack { AgentBackdrop(); Color.black.opacity(0.65) } }
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 5)
                    .padding(.horizontal, 8)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .foregroundStyle(IrisDesign.text).preferredColorScheme(.dark)
            .animation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.88), value: peek.state.selectedID)
    }
}
