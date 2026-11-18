import SwiftUI
import AppKit
import ApplicationServices
import Combine
import Carbon
import QuartzCore
import OSLog

@main
struct Project_IRISApp: App {
    @NSApplicationDelegateAdaptor(IrisAppDelegate.self) var delegate
    var body: some Scene {
        Settings { EmptyView() }
            .commands {
                CommandGroup(after: .appSettings) {
                    Button("Check for Updates…") { delegate.iris.updates.check() }
                    Button("Iris quick panel") { delegate.toggleMenuPanel() }
                        .keyboardShortcut("m", modifiers: [.command, .shift])
                }
            }
    }
}

final class IrisPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class IrisAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    lazy var iris: IrisOrchestrator = {
        if ProcessInfo.processInfo.arguments.contains("--iris-permission-status") {
            print("Iris permissions: accessibility=\(AXIsProcessTrusted()) sandbox=\(IrisLocalStorage.isSandboxed)")
            exit(0)
        }
        IrisLocalStorage.restoreLegacyPreferences()
        return IrisOrchestrator()
    }()
    private var runtimeStarted = false
    private var floating: FloatingIrisController?
    private var agentCorner: AgentCornerController?
    private var notch: NotchController?
    private var workspace: NSWindow?
    private var workspaceOpen = false
    private var onboardingOpen = false
    private var onboarding: NSWindow?
    private var welcomeCoach: WelcomeCoachController?
    private var draftPracticeURL: URL?
    private var status: NSStatusItem?
    private var menuPopover: NSPopover?
    private var menuIconSubscription: AnyCancellable?
    private var lastShortcut: (IrisShortcutAction, TimeInterval)?
    private static let log = Logger(subsystem: "com.projectiris.Project-IRIS", category: "shell")
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        #if DEBUG
        if arguments.contains("--iris-validation"), arguments.contains("--iris-notch-appearance-validation") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await IrisAgentValidation.notchAppearance(iris) }; return
        }
        if arguments.contains("--iris-validation"), arguments.contains("--iris-welcome-validation") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await IrisAgentValidation.welcomeLayout(iris) }; return
        }
        if arguments.contains("--iris-validation"), arguments.contains("--iris-support-validation") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await IrisAgentValidation.supportLayout(iris) }; return
        }
        if arguments.contains("--iris-validation"), arguments.contains("--iris-dock-resource-validation") {
            IrisAppIcons.validateResources(); return
        }
        if arguments.contains("--iris-validation"), arguments.contains("--iris-draft-visual-validation") {
            Task { await InlineDraftController.validateVisuals() }
            return
        }
        if arguments.contains("--iris-validation"), arguments.contains("--iris-knowledge-memory-validation") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await IrisAgentValidation.knowledgeMemory(iris) }; return
        }
        if arguments.contains("--iris-validation"), arguments.contains("--iris-knowledge-layout-validation") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await IrisAgentValidation.knowledgeLayout(iris) }
            return
        }
        if arguments.contains("--iris-validation"), arguments.contains("--iris-agent-validation") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await IrisAgentValidation.run(iris) }
            return
        }
        if arguments.contains("--iris-reference-validation") {
            NSApp.setActivationPolicy(.prohibited)
            DiagramReferenceValidation.run(); return
        }
        if arguments.contains("--iris-validation"), arguments.contains("--iris-20-validation") {
            NSApp.setActivationPolicy(.prohibited)
            Task { await Iris20Validation.run(iris) }
            return
        }
        #endif
        if arguments.contains("--iris-permission-status") { _ = iris; return }
        guard IrisStorageAccess.prepare() else { NSApp.terminate(nil); return }
        if let index = arguments.firstIndex(of: ScreenRecordingAccess.restartArgument),
           arguments.indices.contains(index + 1), let pid = pid_t(arguments[index + 1]),
           let previous = NSRunningApplication(processIdentifier: pid),
           previous.processIdentifier != ProcessInfo.processInfo.processIdentifier,
           previous.bundleURL?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL {
            // Release the old instance's global shortcuts before registering them again.
            Task { @MainActor in
                let deadline = Date().addingTimeInterval(5)
                while !previous.isTerminated, Date() < deadline {
                    try? await Task.sleep(for: .milliseconds(80))
                }
                finishLaunching()
                ScreenRecordingAccess.shared.showSetup(afterRestart: true)
            }
            return
        }
        finishLaunching()
        if arguments.contains(VisualAlignmentCheck.argument) { Task { await VisualAlignmentCheck.run() } }
        if arguments.contains(ScreenRecordingAccess.restartArgument) {
            ScreenRecordingAccess.shared.showSetup(afterRestart: true)
        }
    }

    private func finishLaunching() {
        runtimeStarted = true
        iris.updates.start()
        agentCorner = AgentCornerController(iris: iris)
        updateDockPresence()
        IrisAppIcons.shared.restoreSaved()
        ScreenGuidance.startTracking()
        iris.openFloating = { [weak self] in self?.showFloating() }
        iris.openFloatingTyping = { [weak self] in self?.showFloatingTyping() }
        iris.actions.drawOnScreen = { [weak self] content in
            guard let floating = self?.floating else { throw IrisFailure.message("Open floating Iris first from the menu bar or your keyboard shortcut.") }
            try floating.draw(content)
        }
        iris.prepareFloatingContext = { [weak self] prompt in try await self?.floating?.prepareGuidance(prompt: prompt) }
        iris.actions.guideControl = { [weak self] target, highlight in
            guard let floating = self?.floating else { throw IrisFailure.message("Open floating Iris and enable app guidance first.") }
            try floating.guide(target, highlight: highlight)
        }
        iris.openWorkspace = { [weak self] in self?.showWorkspace() }
        iris.returnToNotch = { [weak self] in
            guard let self else { return }
            self.floating?.hide(); self.hideWorkspace(); self.startPresence()
            self.iris.notchPinned = true; self.iris.expanded = true
            self.notch?.showFromWorkspace()
        }
        iris.reposition = { [weak self] in self?.notch?.reposition() }
        welcomeCoach = WelcomeCoachController(iris: iris)
        iris.welcome.surfaceChanged = { [weak self] in
            guard let self else { return }
            if self.iris.welcome.active {
                switch self.iris.welcome.progress.stage {
                case .notch where !self.iris.welcome.progress.notchOpened:
                    self.iris.collapsePresence()
                case .interview, .floating, .drafting, .review:
                    self.iris.collapsePresence()
                default: break
                }
            }
            self.welcomeCoach?.update(near: [.interview, .notch, .explore, .review].contains(self.iris.welcome.progress.stage) ? self.notch?.welcomeAnchor : nil)
        }
        iris.welcome.moveCoach = { [weak self] ending in self?.welcomeCoach?.moveFromPointer(ending: ending) }
        iris.welcome.openPracticeCanvas = { [weak self] in self?.welcomeCoach?.showPractice() }
        iris.welcomePointAt = { [weak self] rect in self?.floating?.welcomeLook(at: rect) }
        iris.beginWelcomeJourney = { [weak self] resume in
            guard let self else { return }
            self.onboarding?.orderOut(nil); self.onboardingOpen = false
            self.iris.onboardingPresented = false; self.startPresence()
            self.iris.tab = .focus; self.iris.collapsePresence()
            self.iris.welcome.start(resume: resume); self.updateDockPresence()
        }
        iris.endWelcomeJourney = { [weak self] in
            guard let self else { return }
            self.iris.completeOnboarding(); self.onboarding?.close(); self.onboarding = nil
            self.onboardingOpen = false; self.welcomeCoach?.hide(); self.floating?.hide(); self.startPresence()
            self.iris.tab = .focus; self.iris.notchPinned = true; self.iris.expanded = true
            self.updateDockPresence()
        }
        iris.showDraftPractice = { [weak self] in
            guard let self else { return }
            do {
                let file = self.draftPracticeURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("Iris practice-" + UUID().uuidString.prefix(8) + ".txt")
                self.draftPracticeURL = file
                if !FileManager.default.fileExists(atPath: file.path) { try self.iris.welcome.progress.practiceDraft.write(to: file, atomically: true, encoding: .utf8) }
                NSWorkspace.shared.open([file], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"), configuration: NSWorkspace.OpenConfiguration()) { _, error in
                    if let error { Task { @MainActor in self.iris.welcome.issue = error.localizedDescription } }
                }
            } catch { self.iris.welcome.issue = error.localizedDescription }
        }
        InlineDraftController.shared.onVerifiedInsertion = { [weak self] in self?.iris.welcome.draftingInserted() }
        iris.restartOnboarding = { [weak self] in self?.showOnboarding() }
        iris.restartOnboardingAt = { [weak self] step in
            guard let self else { return }
            if step == 5 {
                self.hideWorkspace(); self.floating?.hide(); self.startPresence(); self.iris.onboardingPresented = false
                self.iris.welcome.voiceEnabled = false; self.iris.welcome.handsFree = false
                self.iris.tab = .focus; self.iris.welcome.startLesson(.notch)
            } else { self.showOnboarding(startAt: step) }
        }
        iris.isFullScreen = { [weak self] in self?.notch?.isFullScreen ?? false }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menuIconSubscription = IrisMenuBarIcons.shared.$selection.sink { [weak item] style in
            item?.button?.image = style.image
        }
        item.button?.setAccessibilityLabel("Iris quick panel")
        item.button?.target = self
        item.button?.action = #selector(toggleMenuPanel)
        item.button?.toolTip = "Iris · Ask, capture and focus"
        status = item
        registerHotkey()
        InlineDraftController.shared.personalContext = { [weak self] query in
            guard let iris = self?.iris else { return "" }
            let statements = (iris.data.conversations ?? []).sorted { $0.updatedAt > $1.updatedAt }.prefix(12).flatMap { Array($0.messages.filter { $0.role == "user" }.suffix(8)).reversed().map(\.text) }
            return InlinePersonalContext.context(preferences: iris.preferences, notes: iris.data.notes.map(\.text), statements: Array(statements.prefix(80)), query: query) + "\n" + iris.memoryContext(for: query)
        }
        InlineDraftController.shared.configure { [weak self] in
            guard let self, (!self.iris.needsOnboarding || self.iris.welcome.active), !self.iris.onboardingPresented, !self.iris.shortcuts.isRecording else { return nil }
            return (self.iris.preferences, self.iris.accent)
        }
        if iris.needsOnboarding { showOnboarding() } else { startPresence() }
        Self.log.info("Native notch shell launched")
    }
    @objc fileprivate func toggleMenuPanel() {
        guard let button = status?.button else { return }
        if menuPopover?.isShown == true { menuPopover?.performClose(nil); return }
        let panel: NSPopover
        if let existing = menuPopover { panel = existing }
        else {
            panel = NSPopover()
            panel.behavior = .transient
            panel.contentSize = NSSize(width: 360, height: 580)
            panel.contentViewController = NSHostingController(rootView: IrisMenuPanel(iris: iris) { [weak self] action in self?.performMenuAction(action) })
            menuPopover = panel
        }
        panel.animates = !IrisMotion.reduced
        panel.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        panel.contentViewController?.view.window?.makeKey()
    }
    private func performMenuAction(_ action: IrisMenuAction) {
        menuPopover?.performClose(nil)
        switch action {
        case .ask(let text):
            guard !iris.busy, iris.draft.isEmpty, iris.attachments.isEmpty else { showWorkspace(); return }
            guard !iris.needsOnboarding && !iris.onboardingPresented else { showOnboarding(); return }
            floating?.hide(); hideWorkspace(); startPresence()
            iris.tab = .ask; iris.notchPinned = true; iris.expanded = true
            iris.draft = text; iris.ask()
        case .speak: showFloating()
        case .type: showFloatingTyping()
        case .notch: toggleNotch()
        case .floating: showFloatingQuiet()
        case .hideFloating: hideFloating()
        case .workspace: showWorkspace()
        case .history: iris.workspaceSection = .chats; showWorkspace()
        case .settings: showSettings()
        case .conversation(let chat): iris.openConversation(chat); showWorkspace()
        case .quit: quit()
        case .dismiss: break
        }
    }
    private func startPresence() {
        if notch == nil {
            notch = NotchController(iris: iris)
            notch?.onWelcomeFrame = { [weak self] rect in
                guard let self, self.iris.welcome.active, self.iris.welcome.progress.stage != .floating else { return }
                self.welcomeCoach?.update(near: rect)
            }
        }
    }
    private func showOnboarding(startAt: Int = 0) {
        floating?.hide(); iris.welcome.pause()
        iris.onboardingPresented = true; iris.collapsePresence()
        startPresence(); iris.tab = .focus; hideWorkspace()
        if onboarding == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 740), styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.delegate = self
            window.isOpaque = false; window.backgroundColor = .clear
            window.title = "Meet Iris"; window.titlebarAppearsTransparent = true; window.titleVisibility = .hidden; window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: OnboardingView(iris: iris, startAt: startAt, finish: { [weak self] in
                guard let self else { return }
                self.iris.completeOnboarding(); self.onboarding?.close(); self.onboarding = nil
                self.startPresence(); self.iris.notchPinned = true; self.iris.expanded = true
            }))
            window.minSize = NSSize(width: 820, height: 640)
            if let available = NSScreen.main?.visibleFrame {
                window.setContentSize(NSSize(width: min(900, available.width - 32), height: min(740, available.height - 32)))
            }
            window.center(); onboarding = window
        }
        onboardingOpen = true; updateDockPresence()
        onboarding?.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    @objc func showFloating() { presentFloating(listen: true) }
    @objc func showFloatingTyping() { guard !iris.onboardingPresented && (!iris.needsOnboarding || iris.welcome.active) else { showOnboarding(); return }; presentFloating(listen: false); floating?.showTyping() }
    @objc func showFloatingQuiet() { presentFloating(listen: false) }
    private func presentFloating(listen: Bool) {
        guard !iris.onboardingPresented && (!iris.needsOnboarding || iris.welcome.active) else { showOnboarding(); return }
        hideWorkspace(); if !iris.welcome.active { iris.collapsePresence(); notch?.compactForOtherSurface() }
        if floating == nil { floating = FloatingIrisController(iris: iris); floating?.welcomeAnchor = { [weak self] rect in self?.welcomeCoach?.update(near: rect) } }
        let learningDrag = iris.welcome.active && iris.welcome.progress.stage == .floating && !iris.welcome.progress.floatingDragged
        floating?.show(listen: listen && !learningDrag)
        if learningDrag { iris.welcome.speak(iris.welcome.question) }
        if iris.welcome.active { iris.collapsePresence() }
    }
    @objc func hideFloating() { floating?.hide() }
    private func summonVoice() { floating?.hide(); if iris.onboardingPresented || (iris.needsOnboarding && !iris.welcome.active) { showOnboarding(); return }; startPresence(); iris.summon() }
    @objc func toggleNotch() { floating?.hide(); if iris.onboardingPresented || (iris.needsOnboarding && !iris.welcome.active) { showOnboarding(); return }; startPresence(); iris.togglePresence() }
    @objc func showSettings() { iris.workspaceSection = .settings; showWorkspace() }
    @objc func showWorkspace() {
        guard !iris.onboardingPresented && (!iris.needsOnboarding || iris.welcome.active) else { showOnboarding(); return }
        floating?.hide()
        iris.collapsePresence(); notch?.compactForOtherSurface()
        if workspace == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.delegate = self
            window.title = "Iris"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true; window.titlebarSeparatorStyle = .none
            window.minSize = NSSize(width: 900, height: 680)
            window.contentView = NSHostingView(rootView: ContentView(iris: iris).modifier(IrisAccessibility())); window.center(); workspace = window
        }
        workspaceOpen = true; updateDockPresence()
        if workspace?.isMiniaturized == true { workspace?.deminiaturize(nil) }
        workspace?.makeKeyAndOrderFront(nil); NSApp.activate()
    }
    private func hideWorkspace() {
        workspace?.orderOut(nil)
        workspaceOpen = false
        updateDockPresence()
    }
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        if window === workspace { workspaceOpen = false }
        if window === onboarding { onboardingOpen = false }
        updateDockPresence()
    }
    // Transient notch, floating, drafting and menu panels never opt into the Dock.
    // Track open desktop windows explicitly: willClose arrives before isVisible changes,
    // and a minimized desktop window must still be recoverable from its Dock icon.
    private func updateDockPresence() {
        let policy: NSApplication.ActivationPolicy = workspaceOpen || onboardingOpen ? .regular : .accessory
        if policy == .regular { IrisAppIcons.shared.refreshDockIcon() }
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
        if policy == .regular {
            // AppKit creates the Dock tile asynchronously when leaving accessory mode.
            DispatchQueue.main.async {
                guard NSApp.activationPolicy() == .regular else { return }
                IrisAppIcons.shared.refreshDockIcon()
            }
        }
    }
    @objc func quit() { NSApp.terminate(nil) }
    private func performShortcut(_ action: IrisShortcutAction) {
        let now = ProcessInfo.processInfo.systemUptime
        if let lastShortcut, lastShortcut.0 == action, now - lastShortcut.1 < (iris.welcome.active ? 0.6 : 0.18) { return }
        lastShortcut = (action, now)
        iris.welcome.noteShortcut(action)
        switch action {
        case .notch: summonVoice()
        case .floatingVoice: showFloating()
        case .floatingText: showFloatingTyping()
        case .dismiss: break
        }
    }
    private func registerHotkey() {
        iris.shortcuts.activate { [weak self] action in self?.performShortcut(action) }
        iris.welcome.keys.onMatched = { [weak self] chord in
            guard let self, self.iris.welcome.active, !self.iris.shortcuts.isRecording,
                  let action = IrisShortcutAction.allCases.first(where: { $0.global && self.iris.shortcuts.bindings[$0]?.sameKeys(as: chord) == true }) else { return }
            self.performShortcut(action)
        }
    }
    func applicationDidBecomeActive(_ notification: Notification) { InlineDraftController.shared.reconcileMonitors(); IrisAppIcons.shared.refreshDockIcon() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        guard runtimeStarted else { return }
        welcomeCoach?.close(); agentCorner?.close(); InlineDraftController.shared.shutdown(); iris.shortcuts.shutdown(); iris.shutdown(); notch?.close(); floating?.shutdown()
    }
}

@MainActor
final class NotchController {
    private let iris: IrisOrchestrator
    private let panel: IrisPanel
    private var screen: NSScreen?
    private var surfaceSize = NotchSizing.compact(housing: NotchSizing.referenceHousing)
    private var hoverTask: Task<Void, Never>?
    private var pointerInside = false
    private var subscriptions = Set<AnyCancellable>()
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var globalMouse: Any?
    private var localMouse: Any?
    private var clickMonitor: Any?
    var isFullScreen: Bool { guard let screen else { return false }; return screen.visibleFrame.maxY >= screen.frame.maxY - 1 }
    init(iris: IrisOrchestrator) {
        self.iris = iris
        panel = IrisPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .statusBar; panel.becomesKeyOnlyIfNeeded = true; panel.hidesOnDeactivate = false; panel.canHide = false; panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false; panel.isReleasedWhenClosed = false; panel.animationBehavior = .none
        panel.acceptsMouseMovedEvents = true
        reposition()
        iris.$expanded.removeDuplicates().dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                // Collapsing folds the surface; it must never remove the notch avatar.
                self.panel.orderFrontRegardless()
            }
        }.store(in: &subscriptions)
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.reposition() } }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in
            guard let self else { return }
            self.panel.orderFrontRegardless()
        } }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reposition() }
        }
        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in Task { @MainActor [weak self] in self?.updatePointer() } }
        localMouse = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.updatePointer() }; return event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in Task { @MainActor [weak self] in
            guard let self, self.iris.expanded, !self.containsPointer(NSEvent.mouseLocation), !self.iris.voice.listening else { return }
            self.iris.collapsePresence()
        } }
    }
    var onWelcomeFrame: ((CGRect) -> Void)?
    var welcomeAnchor: CGRect { visibleRect }
    private var visibleRect: NSRect { NSRect(x: panel.frame.midX - surfaceSize.width / 2, y: panel.frame.maxY - surfaceSize.height, width: surfaceSize.width, height: surfaceSize.height) }
    func reposition() {
        let all = NSScreen.screens
        screen = all.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == iris.preferences.displayID } ?? all.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? all.first
        guard let screen else { return }
        let hasNotch = screen.safeAreaInsets.top > 0
        let physicalWidth: CGFloat?
        if hasNotch, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            physicalWidth = max(0, right.minX - left.maxX)
        } else { physicalWidth = nil }
        let housing = NotchSizing.housing(safeTop: screen.safeAreaInsets.top, physicalWidth: physicalWidth)
        let width = housing.width, height = housing.height
        let frame = SurfaceGeometry.notchFrame(in: screen.frame, visible: screen.visibleFrame,
                                               safeTop: screen.safeAreaInsets.top, desired: CGSize(width: 1000, height: 760))
        let canvas = frame.size
        surfaceSize = NotchSizing.compact(housing: housing)
        // Anchor to the physical display edge. Hover never makes this panel key.
        panel.setFrame(frame, display: true)
        panel.contentView = NSHostingView(rootView: NotchSurface(iris: iris, notchWidth: width, notchHeight: height, hasNotch: hasNotch, expandedWidth: min(580, canvas.width), canvasSize: canvas, onSize: { [weak self] size in
            guard let self else { return }; self.surfaceSize = size; self.updatePointer(); self.onWelcomeFrame?(self.visibleRect)
        }, onHover: { _ in }, onDrag: { [weak self] _ in self?.moveToPointerDisplay() }).modifier(IrisAccessibility()))
        panel.orderFrontRegardless()
    }
    private func containsPointer(_ pointer: CGPoint) -> Bool {
        let rect = visibleRect
        let local = CGPoint(x: pointer.x - rect.minX, y: rect.maxY - pointer.y)
        return IrisNotchShape(bottomRadius: iris.expanded ? 26 : 14).path(in: CGRect(origin: .zero, size: rect.size)).contains(local)
    }
    private func updatePointer() {
        let inside = containsPointer(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        guard inside != pointerInside else { return }; pointerInside = inside; hoverTask?.cancel()
        if inside {
            guard !iris.expanded, !iris.floatingActive else { return }
            hoverTask = Task { [weak self] in try? await Task.sleep(for: .milliseconds(180)); guard !Task.isCancelled, let self else { return }; self.iris.expanded = true }
        } else {
            guard !iris.notchPinned, !iris.voice.listening, iris.draft.isEmpty, iris.noteDraft.isEmpty else { return }
            hoverTask = Task { [weak self] in try? await Task.sleep(for: .milliseconds(650)); guard !Task.isCancelled, let self else { return }; self.iris.collapsePresence() }
        }
    }
    private func moveToPointerDisplay() {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }), let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return }
        iris.setPreference { $0.displayID = id }; reposition()
    }
    func showFromWorkspace() { panel.orderFrontRegardless() }
    func compactForOtherSurface() {
        hoverTask?.cancel()
        iris.collapsePresence()
        panel.orderFrontRegardless()
    }
    func close() {
        hoverTask?.cancel(); subscriptions.removeAll(); panel.close()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let spaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        for monitor in [globalMouse, localMouse, clickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
    }
}
