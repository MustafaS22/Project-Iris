import SwiftUI
import AppKit
import Combine

@MainActor
final class FloatingIrisController: ObservableObject {
    var welcomeAnchor: ((CGRect) -> Void)?
    let iris: IrisOrchestrator
    @Published var drawing = ScreenDrawing(marks: [])
    @Published private(set) var drawingRevision = 0
    @Published private(set) var visibleMarkCount: Int?
    @Published private(set) var revealFromIndex = 0
    @Published private(set) var presentationComplete = false
    private var presentationTask: Task<Void, Never>?
    private var presentationID = UUID()
    @Published var roaming = true { didSet { if !roaming && !flightIsGuidance { flight = nil } } }
    @Published private(set) var controlsVisible = false
    @Published private(set) var controlsPresented = false
    private var controlsTask: Task<Void, Never>?
    @Published private(set) var composing = false
    @Published private(set) var morphing = false
    private var morphTask: Task<Void, Never>?
    @Published var typed = ""
    @Published var guideEnabled = true { didSet { captureID = UUID(); snapshot = nil; clear(); if visible { positionCompanions() }; guideStatus = guideEnabled ? "Screen available for visual questions" : "Screen sharing off" } }
    @Published var guideAppID = "" { didSet { captureID = UUID(); snapshot = nil; clear() } }
    @Published var guideStatus = "Screen available for visual questions"
    @Published private(set) var gaze: CGSize?
    @Published private(set) var movementGaze: CGSize?
    private let panel: IrisPanel
    private let controls: IrisPanel
    private let composer: IrisPanel
    private let canvas: NSPanel
    private var dragStart: (origin: CGPoint, pointer: CGPoint)?
    private var dragGaze = FloatingDragGaze()
    private var screen: NSScreen?
    private var flight: FloatingFlight?
    private var flightIsGuidance = false
    private var capturing = false
    private var guidanceDrawing = false
    private var screenAnnotationRequired = false
    private var hadScreenSession = false
    private var timer: Timer?
    private var nextRoam = 0.0
    private var lastInteraction = 0.0
    private var lastGaze = 0.0
    private var lastWindowCheck = 0.0
    private var important: CGPoint?
    private var snapshot: GuidanceSnapshot?
    private var captureID = UUID()
    private var screenObserver: NSObjectProtocol?
    private var activationObserver: NSObjectProtocol?
    private var clickMonitor: Any?
    var visible: Bool { panel.isVisible || composer.isVisible }
    var typingWidth: CGFloat { min(460, max(180, bounds.width)) }
    private var teachingLane: CGRect? {
        guard drawing.mode == "conceptual", !drawing.marks.isEmpty, let screen else { return nil }
        return DiagramPresentation.lane(screen:screen.frame,visible:screen.visibleFrame)
    }
    private let faceSize = CGSize(width: 148, height: 108)
    private var bounds: CGRect { screen?.visibleFrame.insetBy(dx: 12, dy: 12) ?? .zero }
    var runningApps: [NSRunningApplication] { NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier && $0.bundleIdentifier != nil }.sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") } }

    init(iris: IrisOrchestrator) {
        self.iris = iris
        panel = IrisPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        controls = IrisPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        composer = IrisPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        canvas = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        for window in [panel, controls, composer, canvas] {
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
            window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            window.isMovableByWindowBackground = false
            window.animationBehavior = .none
        }
        panel.title = "Floating Iris"; controls.title = "Floating Iris controls"; composer.title = "Type to Iris"; canvas.title = "Iris screen guidance"
        canvas.level = .floating; canvas.ignoresMouseEvents = true
        for window in [panel, controls, composer] { window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1) }
        panel.contentView = NSHostingView(rootView: FloatingIrisView(controller: self, iris: iris).modifier(IrisAccessibility()))
        controls.contentView = NSHostingView(rootView: FloatingControls(controller: self, iris: iris).modifier(IrisAccessibility()))
        composer.contentView = NSHostingView(rootView: FloatingComposer(controller: self, iris: iris).modifier(IrisAccessibility()))
        canvas.contentView = NSHostingView(rootView: IrisScreenCanvas(controller: self).modifier(IrisAccessibility()))
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.recoverDisplay() }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            Task { @MainActor [weak self] in
                guard let self, self.visible, app?.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                self.invalidateGuidance()
            }
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel]) { [weak self] event in
            let clicked = event.type == .leftMouseDown || event.type == .rightMouseDown
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.invalidateGuidance()
                let pointer = NSEvent.mouseLocation
                if clicked, !self.panel.frame.contains(pointer), !self.controls.frame.contains(pointer) { self.dismissControls() }
            }
        }
    }
    func show(listen: Bool) {
        if !visible {
            screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
            let origin = FloatingGeometry.clamped(CGPoint(x: bounds.maxX - faceSize.width - 30, y: bounds.minY + 130), size: faceSize, bounds: bounds)
            panel.setFrame(CGRect(origin: origin, size: faceSize), display: true)
            controlsVisible = false; composing = false

        }
        iris.floatingActive = true; panel.orderFrontRegardless(); if iris.welcome.active { welcomeAnchor?(panel.frame) }
        nextRoam = ProcessInfo.processInfo.systemUptime + 7; startTimer()
        if listen { dismissComposer(); iris.listenFromFloating() }
    }
    func showTyping() {
        stopPresentation()
        morphTask?.cancel(); morphTask = nil; morphing = false
        show(listen: false); iris.voice.stop(); iris.voice.stopSpeaking()
        composing = true; flight = nil; controlsVisible = false; lastInteraction = ProcessInfo.processInfo.systemUptime
        positionCompanions(); hideControlsImmediately(); panel.orderOut(nil)
        composer.makeKeyAndOrderFront(nil)
    }
    func dismissComposer() {
        guard composing else { return }
        morphTask?.cancel()
        composing = false; morphing = true; hideControlsImmediately()
        lastInteraction = ProcessInfo.processInfo.systemUptime
        morphTask = Task { [weak self] in
            guard let self else { return }
            if !IrisMotion.reduced {
                do { try await Task.sleep(for: .milliseconds(360)) } catch { return }
            }
            guard !Task.isCancelled, self.iris.floatingActive else { return }
            let origin = CGPoint(x: self.composer.frame.minX, y: self.composer.frame.midY - self.faceSize.height / 2)
            self.panel.setFrame(CGRect(origin: FloatingGeometry.clamped(origin, size: self.faceSize, bounds: self.teachingLane ?? self.bounds), size: self.faceSize), display: true)
            self.panel.orderFrontRegardless(); self.composer.orderOut(nil)
            self.morphing = false; self.morphTask = nil
            self.nextRoam = ProcessInfo.processInfo.systemUptime + 3
            self.positionCompanions()
        }
    }
    func sendTyped() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !iris.busy, !iris.contextBusy else { return }
        iris.draft = text; typed = ""; dismissComposer(); iris.ask()
    }
    func hide() {
        stopPresentation()
        morphTask?.cancel(); morphTask = nil; morphing = false
        hideControlsImmediately()
        captureID = UUID(); iris.voice.stop(); iris.voice.stopSpeaking()
        hadScreenSession = false
        iris.floatingActive = false; timer?.invalidate(); timer = nil
        flight = nil; dragStart = nil; controlsVisible = false; composing = false; gaze = nil; movementGaze = nil
        for window in [panel, controls, composer, canvas] { window.orderOut(nil) }
    }
    func toggleControls() {
        if iris.computer.needsAttention { iris.computer.revealPermission(); return }
        guard visible, !composing, !morphing else { return }
        flight = nil; movementGaze = nil
        lastInteraction = ProcessInfo.processInfo.systemUptime
        setControlsVisible(!controlsVisible)
    }
    private func dismissControls() {
        setControlsVisible(false)
        lastInteraction = ProcessInfo.processInfo.systemUptime
    }
    private func hideControlsImmediately() {
        controlsTask?.cancel(); controlsTask = nil
        controlsVisible = false; controlsPresented = false
        controls.ignoresMouseEvents = true; controls.orderOut(nil)
    }
    private func setControlsVisible(_ show: Bool) {
        controlsTask?.cancel(); controlsTask = nil
        controlsVisible = show
        if IrisMotion.reduced {
            controlsPresented = show; controls.ignoresMouseEvents = !show
            positionCompanions()
            if show { controls.orderFrontRegardless() } else { controls.orderOut(nil) }
            return
        }
        if show {
            positionCompanions(); controls.ignoresMouseEvents = true
            controls.orderFrontRegardless()
            controlsTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard let self, !Task.isCancelled, self.controlsVisible, self.visible, !self.composing, !self.morphing else { return }
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) { self.controlsPresented = true }
                self.controls.ignoresMouseEvents = false; self.controlsTask = nil
            }
        } else {
            controls.ignoresMouseEvents = true
            withAnimation(.easeOut(duration: 0.16)) { controlsPresented = false }
            controlsTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                guard let self, !Task.isCancelled, !self.controlsVisible else { return }
                self.controls.orderOut(nil); self.controlsTask = nil
            }
        }
    }
    func beginDrag(at pointer: CGPoint) {
        flight = nil; movementGaze = .zero; dragGaze = FloatingDragGaze(); dragStart = (panel.frame.origin, pointer)
        lastInteraction = ProcessInfo.processInfo.systemUptime; hideControlsImmediately()
    }
    func drag(to pointer: CGPoint) {
        guard let start = dragStart else { return }
        let targetScreen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? screen
        if targetScreen != screen { screen = targetScreen; invalidateGuidance(); updateCanvasFrame() }
        let previous = panel.frame.origin
        let next = FloatingPlacement.dragged(origin: start.origin, startPointer: start.pointer, pointer: pointer, size: faceSize, bounds: teachingLane ?? bounds)
        panel.setFrameOrigin(next)
        if hypot(next.x - start.origin.x, next.y - start.origin.y) > 8 { iris.welcome.noteDrag() }
        let now = ProcessInfo.processInfo.systemUptime
        dragGaze.record(from: previous, to: next, at: now)
        movementGaze = dragGaze.gaze(at: now) ?? .zero
        lastInteraction = ProcessInfo.processInfo.systemUptime; positionCompanions()
    }
    func endDrag() { dragStart = nil; dragGaze = FloatingDragGaze(); movementGaze = nil; gaze = nil; lastInteraction = ProcessInfo.processInfo.systemUptime; nextRoam = lastInteraction + 9 }
    func clear() { stopPresentation(); presentationComplete = false; visibleMarkCount = nil; revealFromIndex = 0; drawingRevision &+= 1; guidanceDrawing = false; drawing = .init(marks: []); canvas.orderOut(nil); important = nil; gaze = nil }
    func invalidateGuidance() {
        guard snapshot != nil || guidanceDrawing || capturing else { return }
        captureID = UUID(); snapshot = nil; clear(); guideStatus = guideEnabled ? "Screen changed · ask again to refresh" : "Screen sharing off"
    }
    func draw(_ content: String) throws {
        guard visible else { throw IrisFailure.message("Open floating Iris before drawing an explanation.") }
        let proposed = try ScreenDrawing.decode(content)
        if let figure=proposed.figure, DiagramReferenceStore.image(figure)==nil {throw IrisFailure.message("That reference figure is unavailable. Choose another diagram or search online.")}
        if proposed.mode == "solution", !screenAnnotationRequired || snapshot == nil {throw IrisFailure.message("Share the question's app screen first, then ask Iris to solve it.")}
        if proposed.mode == "solution",let q=proposed.question,let snapshot {
            let region=snapshot.projection.displayRect(q.rect)
            let box=ScreenSolution.frame(question:CGRect(x:region.minX*(screen?.frame.width ?? 0),y:region.minY*(screen?.frame.height ?? 0),width:region.width*(screen?.frame.width ?? 0),height:region.height*(screen?.frame.height ?? 0)),canvas:screen?.frame.size ?? .zero)
            guard box.width>0 else{throw IrisFailure.message("Move or scroll the question higher so there is room for its solution panel, then ask again.")}
        }
        let annotate = screenAnnotationRequired && proposed.mode != "conceptual"
        if annotate {
            guard let snapshot, GuidancePolicy.fresh(captured: snapshot.captured, now: ProcessInfo.processInfo.systemUptime, targetPID: snapshot.pid, foregroundPID: ScreenGuidance.foregroundPID, originalWindow: snapshot.windowFrame, currentWindow: ScreenGuidance.windowFrame(pid: snapshot.pid, windowID: snapshot.windowID)) else {
                invalidateGuidance(); throw IrisFailure.message("The diagram moved or changed before its labels were ready. Keep it visible and ask again.")
            }
        }
        if proposed.mode == "conceptual" { snapshot = nil; hadScreenSession = false; screenAnnotationRequired = false }
        stopPresentation()
        presentationComplete = false
        drawing = try annotate ? snapshot!.projection.resolve(proposed, targets: snapshot!.targets) : proposed
        guidanceDrawing = annotate; visibleMarkCount = nil; revealFromIndex = 0; drawingRevision &+= 1; updateCanvasFrame()
        if let mark = drawing.marks.first { important = FloatingPlacement.appKitRect(normalized: CGRect(x: mark.x, y: mark.y, width: abs(mark.width ?? 0), height: abs(mark.height ?? 0)), screen: screen?.frame ?? .zero).center }
        if drawing.marks.isEmpty { clear() } else {
            flight = nil
            if let lane=teachingLane { panel.setFrameOrigin(FloatingGeometry.clamped(panel.frame.origin,size:faceSize,bounds:lane));hideControlsImmediately() }
            canvas.orderFrontRegardless(); panel.orderFrontRegardless(); avoidAnnotationLabels(); startPresentation() }
    }
    func stopPresentation() {
        let ownedSpeech = presentationTask != nil && drawing.narrate == true
        presentationID = UUID(); presentationTask?.cancel(); presentationTask = nil
        if ownedSpeech { iris.voice.stopSpeaking() }
    }
    private func focus(_ mark: ScreenDrawing.Mark) {
        guard let screen else {return}
        let stage=drawing.mode == "conceptual" ? DiagramPresentation.stageSize(screen.frame.size) : screen.frame.size
        var rect=CGRect(x:mark.x*stage.width,y:mark.y*stage.height,width:(mark.width ?? 0)*stage.width,height:(mark.height ?? 0)*stage.height)
        if mark.kind == "focus",let figure=drawing.figure,let image=DiagramReferenceStore.image(figure) {
            let visible=visibleMarkCount ?? drawing.marks.count
            let imageFrame=DiagramPresentation.imageFrame(image:image.size,canvas:stage,drawing:drawing,visible:visible,revealFrom:revealFromIndex,elapsed:100)
            rect=DiagramPresentation.focusRect(mark,imageFrame:imageFrame)
        }
        if drawing.mode == "solution",let question=drawing.question {
            rect=ScreenSolution.frame(question:CGRect(x:question.x*stage.width,y:question.y*stage.height,width:question.width*stage.width,height:question.height*stage.height),canvas:stage)
        }
        important=CGPoint(x:screen.frame.minX+rect.midX,y:screen.frame.maxY-rect.midY)
        movementGaze=nil
        if let important {
            gaze=CGSize(width:important.x-panel.frame.midX,height:panel.frame.midY-important.y)
            if drawing.mode == "solution",let question=drawing.question,dragStart == nil {
                let q=FloatingPlacement.appKitRect(normalized:question.rect,screen:screen.frame)
                let box=CGRect(x:screen.frame.minX+rect.minX,y:screen.frame.maxY-rect.maxY,width:rect.width,height:rect.height)
                let destination=FloatingPlacement.near(q.union(box),size:faceSize,bounds:bounds)
                if IrisMotion.reduced{panel.setFrameOrigin(destination);positionCompanions()}
                else{flightIsGuidance=true;flight = .init(start:panel.frame.origin,end:destination,started:ProcessInfo.processInfo.systemUptime,duration:0.85)}
            } else if let lane=teachingLane,dragStart == nil,!controlsVisible {
                let destination=DiagramPresentation.companion(target:important,avatar:faceSize,lane:lane)
                if IrisMotion.reduced { panel.setFrameOrigin(destination);positionCompanions() }
                else {flightIsGuidance=true;flight = .init(start:panel.frame.origin,end:destination,started:ProcessInfo.processInfo.systemUptime,duration:0.85)}
            }
        }
    }
    private func startPresentation() {
        guard !drawing.marks.isEmpty else {
            if let first = drawing.marks.first { focus(first) }; return
        }
        let original = drawing, id = UUID(); presentationID = id
        visibleMarkCount = 0
        presentationTask = Task { [weak self] in
            guard let self else { return }
            do {
                var spokenCount = 0
                for (stepIndex, range) in original.presentationSteps.enumerated() {
                    let index = range.lowerBound
                    let mark = original.marks[range].first(where: { $0.speech != nil }) ?? original.marks[index]
                    try Task.checkCancellation()
                    guard self.visible, self.presentationID == id, !self.iris.voice.listening, !self.iris.voice.requesting else { throw CancellationError() }
                    if self.guidanceDrawing {
                        guard let snapshot = self.snapshot, GuidancePolicy.fresh(captured: snapshot.captured, now: ProcessInfo.processInfo.systemUptime, targetPID: snapshot.pid, foregroundPID: ScreenGuidance.foregroundPID, originalWindow: snapshot.windowFrame, currentWindow: ScreenGuidance.windowFrame(pid: snapshot.pid, windowID: snapshot.windowID)) else {
                            self.invalidateGuidance(); return
                        }
                    }
                    self.revealFromIndex = index; self.visibleMarkCount = range.upperBound; self.focus(mark); self.drawingRevision &+= 1
                    self.guideStatus = "Step \(stepIndex + 1) of \(original.presentationSteps.count) · \(mark.text ?? "Connection")"
                    let revealStarted = Date()
                    try await Task.sleep(for: .milliseconds(mark.kind == "object" ? 120 : 550))
                    if original.narrate == true, spokenCount < 8, mark.speech != nil || mark.text != nil {
                        spokenCount += 1
                        let sentence = String((mark.speech ?? mark.text ?? "This is the highlighted part.").prefix(260))
                        self.iris.speakFloatingReply(sentence)
                        try await self.waitForNarration(id: id)

                    } else { try await Task.sleep(for: .milliseconds(500)) }
                    let hasObject = original.marks[range].contains { $0.kind == "object" }
                    let minimumReveal = (hasObject ? 1.15 : 0.60) + Double(range.count - 1) * 0.095
                    let remaining = minimumReveal - Date().timeIntervalSince(revealStarted)
                    if remaining > 0 { try await Task.sleep(for: .seconds(remaining)) }
                }
                guard self.presentationID == id else { return }
                if original.mode == "conceptual" || original.mode == "solution" {
                    self.presentationComplete = true
                    self.revealFromIndex = original.marks.count
                    self.drawingRevision &+= 1
                }
                self.presentationTask = nil; self.guideStatus = original.mode == "conceptual" ? "Explanation complete · ask a follow-up" : "Guide complete · ask again after changing the screen"
            } catch {
                guard self.presentationID == id else { return }
                self.presentationTask = nil; self.guideStatus = "Guide paused · ask again to continue"
            }
        }
    }
    private func waitForNarration(id: UUID) async throws {
        let deadline = Date().addingTimeInterval(60)
        while iris.voice.preparingSpeech || iris.voice.speaking {
            try Task.checkCancellation()
            guard visible, presentationID == id, !iris.voice.listening, Date() < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(80))
        }
    }
    private func avoidAnnotationLabels() {
        guard drawing.mode != "conceptual", let screen, dragStart == nil, !composing else { return }
        let layout = AnnotationLayout.make(drawing, size: screen.frame.size) { text in
            let rect = (text as NSString).boundingRect(with: CGSize(width: 190, height: 36), options: .usesLineFragmentOrigin, attributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium)])
            return rect.size
        }
        let cards = layout.callouts.map { item in
            CGRect(x: screen.frame.minX + item.rect.minX, y: screen.frame.maxY - item.rect.maxY, width: item.rect.width, height: item.rect.height).insetBy(dx: -18, dy: -18)
        }
        guard cards.contains(where: { $0.intersects(panel.frame) }) else { return }
        let candidates = [CGPoint(x: bounds.minX, y: bounds.minY), CGPoint(x: bounds.maxX - faceSize.width, y: bounds.minY), CGPoint(x: bounds.minX, y: bounds.maxY - faceSize.height), CGPoint(x: bounds.maxX - faceSize.width, y: bounds.maxY - faceSize.height)]
        func overlap(_ point: CGPoint) -> CGFloat {
            let frame = CGRect(origin: point, size: faceSize)
            return cards.reduce(0) { total, card in let intersection = frame.intersection(card); return total + (intersection.isNull ? 0 : intersection.width * intersection.height) }
        }
        let destination = candidates.min { a, b in
            let x = overlap(a), y = overlap(b)
            return x == y ? hypot(a.x - panel.frame.minX, a.y - panel.frame.minY) < hypot(b.x - panel.frame.minX, b.y - panel.frame.minY) : x < y
        }!
        if IrisMotion.reduced { panel.setFrameOrigin(destination); positionCompanions() }
        else { flightIsGuidance = true; flight = .init(start: panel.frame.origin, end: destination, started: ProcessInfo.processInfo.systemUptime, duration: 1.1) }
    }
    func guide(_ targetID: String, highlight: Bool) throws {
        guard visible, let snapshot, let target = snapshot.targets.first(where: { $0.id == targetID }),
              GuidancePolicy.fresh(captured: snapshot.captured, now: ProcessInfo.processInfo.systemUptime, targetPID: snapshot.pid, foregroundPID: ScreenGuidance.foregroundPID, originalWindow: snapshot.windowFrame, currentWindow: ScreenGuidance.windowFrame(pid: snapshot.pid, windowID: snapshot.windowID)) else {
            invalidateGuidance(); throw IrisFailure.message("That screen target is no longer current. Keep the chosen app in front and ask again for a fresh guide.")
        }
        let rect = FloatingPlacement.appKitRect(normalized: target.rect, screen: screen?.frame ?? .zero)
        important = rect.center; flight = nil
        if highlight { guidanceDrawing = true; drawing = GuidancePolicy.drawing(for: target); drawingRevision &+= 1; updateCanvasFrame(); canvas.orderFrontRegardless() }
        if !IrisMotion.reduced, dragStart == nil, !composing {
            flightIsGuidance = true
            flight = .init(start: panel.frame.origin, end: FloatingPlacement.near(rect, size: faceSize, bounds: bounds), started: ProcessInfo.processInfo.systemUptime, duration: 1.5)
        }
        guideStatus = "Showing \(target.label)"; panel.orderFrontRegardless()
    }
    func prepareGuidance(prompt: String) async throws -> AttachedContext? {
        if ScreenQuestionPolicy.wantsNewDrawing(prompt), !ScreenQuestionPolicy.wantsSolution(prompt) {
            snapshot = nil; hadScreenSession = false; screenAnnotationRequired = false; clear(); guideStatus = "Creating a new visual explanation…"; return nil
        }
        if ScreenQuestionPolicy.forbidsSnapshot(prompt) {
            snapshot = nil; hadScreenSession = false; screenAnnotationRequired = false; clear(); return nil
        }
        let visualQuestion = ScreenQuestionPolicy.wantsSnapshot(prompt)
        // Remember visual context for follow-ups within a session, but refresh the image each time.
        let references = Set(prompt.lowercased().split { !$0.isLetter }.map(String.init))
        let followUp = hadScreenSession && !references.isDisjoint(with: ["this", "that", "it", "these", "those", "next", "here", "continue", "done", "now"])
        screenAnnotationRequired = false
        guard visible, guideEnabled, visualQuestion || followUp || !guideAppID.isEmpty else {
            if visible, visualQuestion, !guideEnabled { throw IrisFailure.message("Screen sharing is off in floating Iris. Click the avatar → eye → enable screen sharing, then ask again.") }
            return nil
        }
        guard let app = guideAppID.isEmpty ? ScreenGuidance.currentApp : runningApps.first(where: { $0.bundleIdentifier == guideAppID }) else { throw IrisFailure.message("Open the app containing your diagram or page, then ask again.") }
        guard ScreenGuidance.foregroundPID == app.processIdentifier else { throw IrisFailure.message("Bring \(app.localizedName ?? "the chosen app") to the front, then ask again. Screen sharing stays limited to that app.") }
        let id = UUID(); captureID = id; snapshot = nil; clear(); guideStatus = "Reading \(app.localizedName ?? "app") for this question…"
        screenAnnotationRequired = true
        capturing = true; defer { capturing = false }
        let result = try await ScreenGuidance.capture(app: app)
        try Task.checkCancellation()
        guard visible, guideEnabled, captureID == id, ScreenGuidance.foregroundPID == app.processIdentifier else { throw IrisFailure.message("The shared screen changed while capturing. Keep the diagram visible and ask again.") }
        guard let capturedScreen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == result.displayID }) else { throw IrisFailure.message("The captured display disconnected. Ask again on your current display.") }
        screen = capturedScreen; updateCanvasFrame()
        hadScreenSession = true
        snapshot = result; guideStatus = "Screen shared · \(app.localizedName ?? "app") · this question"
        var attachment=result.attachment
        if ScreenQuestionPolicy.wantsSolution(prompt){attachment.text=ScreenSolution.instruction+"\n"+attachment.text}
        return attachment
    }
    private func recoverDisplay() {
        guard visible else { return }
        flight = nil; dragStart = nil; screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main
        invalidateGuidance(); panel.setFrameOrigin(FloatingGeometry.clamped(panel.frame.origin, size: faceSize, bounds: teachingLane ?? bounds)); updateCanvasFrame(); positionCompanions()
    }
    private func updateCanvasFrame() { if let screen { canvas.setFrame(screen.frame, display: true) } }
    func welcomeLook(at rect: CGRect) {
        guard visible, iris.welcome.active, iris.welcome.progress.stage == .floating else { return }
        important = rect.center; flight = nil; movementGaze = nil
        gaze = CGSize(width: rect.midX - panel.frame.midX, height: panel.frame.midY - rect.midY)
    }
    private func positionCompanions() {
        if iris.welcome.active { welcomeAnchor?(panel.frame) }
        guard !morphing else { return }
        controls.setFrame(FloatingPlacement.companion(avatar: panel.frame, size: CGSize(width: 270, height: 60), bounds: bounds), display: true)
        let size = CGSize(width: typingWidth, height: 112)
        let origin = CGPoint(x: panel.frame.minX, y: panel.frame.midY - size.height / 2)
        composer.setFrame(CGRect(origin: FloatingGeometry.clamped(origin, size: size, bounds: bounds), size: size), display: true)
    }
    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in MainActor.assumeIsolated { self?.tick() } }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
    }
    private func tick() {
        guard visible, !composing, !morphing else { return }
        let now = ProcessInfo.processInfo.systemUptime, pointer = NSEvent.mouseLocation
        let nearby = panel.frame.insetBy(dx: -85, dy: -65).contains(pointer)
        if nearby || controlsVisible { lastInteraction = now }
        let interrupted = (presentationTask != nil && !flightIsGuidance) || IrisMotion.reduced || dragStart != nil || nearby || controlsVisible || composing || NSEvent.pressedMouseButtons != 0 || iris.voice.listening || iris.voice.requesting
        if interrupted { flight = nil }
        if let current = flight {
            let point=current.position(at:now)
            panel.setFrameOrigin(teachingLane.map {FloatingGeometry.clamped(point,size:faceSize,bounds:$0)} ?? point); positionCompanions()
            if current.finished(at: now) { flight = nil; nextRoam = now + Double.random(in: 8...14) }
        } else if now >= nextRoam && now - lastInteraction > 4 && !interrupted && !iris.busy && !iris.voice.speaking && !iris.voice.preparingSpeech && important == nil && roaming && !IrisMotion.reduced {
            let wander = Int.random(in: 0...2) == 0
                ? CGPoint(x: CGFloat.random(in: bounds.minX...max(bounds.minX, bounds.maxX - faceSize.width)), y: CGFloat.random(in: bounds.minY...max(bounds.minY, bounds.maxY - faceSize.height)))
                : CGPoint(x: panel.frame.minX + CGFloat.random(in: -240...240), y: panel.frame.minY + CGFloat.random(in: -120...120))
            let origin = FloatingGeometry.clamped(wander, size: faceSize, bounds: bounds)
            flightIsGuidance = false
            flight = .init(start: panel.frame.origin, end: origin, started: now, duration: max(2.4, min(6, hypot(origin.x - panel.frame.minX, origin.y - panel.frame.minY) / 230)))
        }
        let travel = dragStart != nil ? (dragGaze.gaze(at: now) ?? .zero) : (important == nil ? flight?.travelGaze(at: now) : nil)
        if movementGaze != travel { movementGaze = travel }
        if now - lastGaze > 0.1 {
            lastGaze = now
            let next: CGSize? = important.map {
                CGSize(width: $0.x - panel.frame.midX, height: panel.frame.midY - $0.y)
            }
            if next != gaze { gaze = next }
        }
        if now - lastWindowCheck > 0.75, let snapshot {
            lastWindowCheck = now
            if !GuidancePolicy.fresh(captured: snapshot.captured, now: now, targetPID: snapshot.pid, foregroundPID: ScreenGuidance.foregroundPID, originalWindow: snapshot.windowFrame, currentWindow: ScreenGuidance.windowFrame(pid: snapshot.pid, windowID: snapshot.windowID)) { invalidateGuidance() }
        }
    }
    func shutdown() {
        hide()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        panel.close(); controls.close(); composer.close(); canvas.close()
    }
}
private extension CGRect { var center: CGPoint { CGPoint(x: midX, y: midY) } }

private struct FloatingIrisView: View {
    @ObservedObject var controller: FloatingIrisController
    @ObservedObject var iris: IrisOrchestrator
    var body: some View {
        IrisAvatar(state: iris.state == .sleeping ? .idle : iris.state, color: iris.accent, size: 64, animated: true, desktop: true, isWriting: iris.busy, guidance: controller.gaze, movement: controller.movementGaze)
            .modifier(ComputerAvatarGlow(phase: iris.computer.presentation, accent: iris.accent))
            .modifier(FloatingAvatarShadow(accent: iris.accent))
            .frame(width: 148, height: 108)
            .overlay(FloatingDragSurface(controller: controller))
            .accessibilityHint("Drag to move. Click for controls. \(iris.shortcuts.label(.floatingVoice)) to speak; \(iris.shortcuts.label(.floatingText)) to type.")
            .preferredColorScheme(.dark)
            .onReceive(iris.voice.$speechError) { error in
                if error != nil, controller.visible, !iris.busy { iris.reportFloatingSpeechFailure() }
            }
    }
}
private struct FloatingControls: View {
    @ObservedObject var controller: FloatingIrisController
    @ObservedObject var iris: IrisOrchestrator
    @State private var showGuidance = false
    @State private var showDiagrams = false
    @Environment(\.irisReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 2) {
            control(iris.busy ? "stop.fill" : (iris.voice.listening ? "stop.circle.fill" : "mic.fill"), iris.busy ? "Stop the current task" : "Speak or stop listening") { if iris.busy { iris.cancelModel() } else { controller.stopPresentation(); iris.listenFromFloating() } }
            control("keyboard", "Type to Iris · \(iris.shortcuts.label(.floatingText))") { controller.showTyping() }
            control("eye", "Screen guidance setup") { showGuidance.toggle() }
                .popover(isPresented: $showGuidance) { FloatingGuidanceSettings(controller: controller, iris: iris) }
            control(controller.roaming ? "pause" : "play", controller.roaming ? "Pause roaming" : "Resume roaming") { controller.roaming.toggle() }
            control("books.vertical.fill", "Premade diagram library") { showDiagrams.toggle() }
                .popover(isPresented: $showDiagrams) {
                    DiagramLibraryBrowser(accent: iris.accent, choose: { entry, narrate in
                        showDiagrams = false
                        iris.playDiagram(entry, narrate: narrate)
                    }, chooseReference: { reference, narrate in
                        showDiagrams=false
                        do {
                            let data=try JSONEncoder().encode(reference.drawing);try controller.draw(String(decoding:data,as:UTF8.self))
                            if narrate {
                                iris.attachments.append(.init(name:reference.title,text:"Reference source: "+reference.sourceURL+"\nCredit: "+reference.credit,image:try DiagramReferenceStore.modelImage(reference.id),note:"diagram-reference:"+reference.id))
                                iris.draft="Explain the supplied reference diagram in three short steps, highlighting each part while you explain it."
                                iris.ask()
                            }
                        } catch { iris.error=error.localizedDescription }
                    })
                }
            control("eraser", "Clear guidance") { controller.clear() }
            control("bubble.left", "Open full chat") { iris.showWorkspace() }
            control("xmark", "Hide floating Iris") { controller.hide() }
        }.padding(6).background(.black.opacity(0.95), in: Capsule()).frame(width: 270, height: 44)
            .scaleEffect(controller.controlsPresented ? 1 : 0.96, anchor: .top)
            .offset(y: reduceMotion || controller.controlsPresented ? 0 : -6)
            .opacity(controller.controlsPresented ? 1 : 0)
            .allowsHitTesting(controller.controlsPresented)
            .frame(width: 270, height: 60).preferredColorScheme(.dark)
            .onChange(of: controller.controlsVisible) { _, shown in if !shown { showGuidance = false; showDiagrams = false } }
    }
    private func control(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).irisSymbolStyle().font(.system(size: 12)).frame(width: 28, height: 28) }.buttonStyle(.plain).foregroundStyle(IrisDesign.text).help(label).accessibilityLabel(label)
    }
}
private struct FloatingComposer: View {
    @ObservedObject var controller: FloatingIrisController
    @ObservedObject var iris: IrisOrchestrator
    var body: some View {
        FloatingTypingBar(text: $controller.typed, expanded: controller.composing, width: controller.typingWidth,
                          state: iris.state, accent: iris.accent, shortcuts: iris.shortcuts, enabled: !iris.busy && !iris.contextBusy,
                          submit: { controller.sendTyped() }, dismiss: { controller.dismissComposer() })
    }
}
private struct FloatingGuidanceSettings: View {
    @ObservedObject var controller: FloatingIrisController
    @ObservedObject var iris: IrisOrchestrator
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("App guidance").font(.system(size: 16, weight: .semibold))
            Toggle("Screen sharing for visual questions", isOn: $controller.guideEnabled).toggleStyle(.switch).controlSize(.small)
            if controller.guideEnabled {
                IrisPicker("Shared app", selection: $controller.guideAppID, options: [.init(value: "", title: "Current app (automatic)")] + controller.runningApps.compactMap { app in app.bundleIdentifier.map { .init(value: $0, title: app.localizedName ?? $0) } })
                Text("Visual questions share one fresh image of the front window with your AI provider. Other apps and Iris are excluded. No continuous recording.").font(.caption).foregroundStyle(IrisDesign.secondary)
            }
            Text(controller.guideStatus).font(.caption).foregroundStyle(IrisDesign.secondary)
        }.padding(20).frame(width: 320).background(IrisDesign.surface).foregroundStyle(IrisDesign.text)
            .preferredColorScheme(.dark).environment(\.irisControlAccent, iris.accent)
    }
}
private struct FloatingDragSurface: NSViewRepresentable {
    let controller: FloatingIrisController
    func makeNSView(context: Context) -> DragView { DragView(controller: controller) }
    func updateNSView(_ view: DragView, context: Context) { view.controller = controller }
    final class DragView: NSView {
        weak var controller: FloatingIrisController?
        private var pressPoint: CGPoint?
        private var dragging = false
        init(controller: FloatingIrisController) { self.controller = controller; super.init(frame: .zero); setAccessibilityElement(true); setAccessibilityLabel("Floating Iris. Drag to move; press to show or hide controls."); setAccessibilityRole(.button) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func mouseDown(with event: NSEvent) { pressPoint = NSEvent.mouseLocation; dragging = false }
        override func mouseDragged(with event: NSEvent) {
            guard let pressPoint else { return }
            let pointer = NSEvent.mouseLocation
            if !dragging {
                guard hypot(pointer.x - pressPoint.x, pointer.y - pressPoint.y) >= 4 else { return }
                dragging = true; controller?.beginDrag(at: pressPoint)
            }
            controller?.drag(to: pointer)
        }
        override func mouseUp(with event: NSEvent) {
            if dragging { controller?.endDrag() } else if pressPoint != nil { controller?.toggleControls() }
            pressPoint = nil; dragging = false
        }
        override func accessibilityPerformPress() -> Bool { controller?.toggleControls(); return true }
    }
}
private struct IrisScreenCanvas: View {
    @ObservedObject var controller: FloatingIrisController
    var body: some View {
        GeometryReader { geometry in
            let stage=controller.drawing.mode == "conceptual" ? DiagramPresentation.stageSize(geometry.size) : geometry.size
            if controller.drawing.mode == "solution",let question=controller.drawing.question {
                let q=CGRect(x:question.x*geometry.size.width,y:question.y*geometry.size.height,width:question.width*geometry.size.width,height:question.height*geometry.size.height)
                let rect=ScreenSolution.frame(question:q,canvas:geometry.size)
                FloatingSolutionView(drawing:controller.drawing,visibleCount:controller.visibleMarkCount ?? 0,complete:controller.presentationComplete,accent:controller.iris.accent)
                    .frame(width:rect.width,height:rect.height).position(x:rect.midX,y:rect.midY)
            } else {
                IrisDrawingView(drawing:controller.drawing,accent:controller.iris.accent,revision:controller.drawingRevision,visibleMarkCount:controller.visibleMarkCount,revealFromIndex:controller.revealFromIndex,presentationComplete:controller.presentationComplete)
                    .frame(width:stage.width,height:stage.height,alignment:.topLeading)
            }
        }.ignoresSafeArea()
    }
}
