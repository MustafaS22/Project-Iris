import Foundation
import CoreGraphics

/// Screen coordinates throughout: AppKit points, bottom-left origin. One owner moves the avatar window.
struct FloatingFlight {
    var start: CGPoint
    var end: CGPoint
    var started: TimeInterval
    var duration: TimeInterval
    func position(at time: TimeInterval) -> CGPoint {
        let t = min(1, max(0, (time - started) / max(0.01, duration)))
        let eased = t * t * t * (t * (t * 6 - 15) + 10)
        return CGPoint(x: start.x + (end.x - start.x) * eased, y: start.y + (end.y - start.y) * eased)
    }
    /// Convert AppKit's upward-positive travel into the avatar's downward-positive gaze.
    /// Fade near departure and arrival; the eye renderer supplies frame-rate-independent smoothing.
    func travelGaze(at time: TimeInterval) -> CGSize? {
        let t = (time - started) / max(0.01, duration)
        let dx = end.x - start.x, dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard t > 0, t < 1, distance > 1 else { return nil }
        func ease(_ value: Double) -> Double {
            let x = min(1, max(0, value))
            return x * x * x * (x * (x * 6 - 15) + 10)
        }
        let strength = min(ease(t / 0.12), ease((1 - t) / 0.15))
        return CGSize(width: dx / distance * 180 * strength, height: -dy / distance * 180 * strength)
    }
    func finished(at time: TimeInterval) -> Bool { time >= started + duration }
}
/// Tracks actual clamped window movement, so dragging against an edge does not fake travel.
struct FloatingDragGaze {
    private var direction = CGSize.zero
    private var lastMovement: TimeInterval?
    mutating func record(from start: CGPoint, to end: CGPoint, at time: TimeInterval) {
        let dx = end.x - start.x, dy = end.y - start.y
        let distance = hypot(dx, dy)
        guard distance.isFinite, distance > 0.35, time.isFinite else { return }
        direction = CGSize(width: dx / distance * 180, height: -dy / distance * 180)
        lastMovement = time
    }
    func gaze(at time: TimeInterval) -> CGSize? {
        guard let lastMovement, time >= lastMovement else { return nil }
        let elapsed = time - lastMovement
        guard elapsed < 0.32 else { return nil }
        let t = min(1, max(0, (elapsed - 0.08) / 0.24))
        let strength = 1 - t * t * t * (t * (t * 6 - 15) + 10)
        return CGSize(width: direction.width * strength, height: direction.height * strength)
    }
}

enum FloatingPlacement {
    static func dragged(origin: CGPoint, startPointer: CGPoint, pointer: CGPoint, size: CGSize, bounds: CGRect) -> CGPoint {
        FloatingGeometry.clamped(CGPoint(x: origin.x + pointer.x - startPointer.x, y: origin.y + pointer.y - startPointer.y), size: size, bounds: bounds)
    }
    static func companion(avatar: CGRect, size: CGSize, bounds: CGRect) -> CGRect {
        let candidates = [
            CGPoint(x: avatar.midX - size.width / 2, y: avatar.minY - size.height - 4),
            CGPoint(x: avatar.midX - size.width / 2, y: avatar.maxY + 4),
            CGPoint(x: avatar.maxX + 4, y: avatar.midY - size.height / 2),
            CGPoint(x: avatar.minX - size.width - 4, y: avatar.midY - size.height / 2)
        ].map { CGRect(origin: FloatingGeometry.clamped($0, size: size, bounds: bounds), size: size) }
        return candidates.first { !$0.intersects(avatar) } ?? candidates.min { a, b in
            let x = a.intersection(avatar), y = b.intersection(avatar)
            return (x.isNull ? 0 : x.width * x.height) < (y.isNull ? 0 : y.width * y.height)
        }!
    }

    static func near(_ target: CGRect, size: CGSize, bounds: CGRect) -> CGPoint {
        let candidates = [CGPoint(x: target.maxX + 32, y: target.midY - size.height / 2), CGPoint(x: target.minX - size.width - 32, y: target.midY - size.height / 2), CGPoint(x: target.midX - size.width / 2, y: target.minY - size.height - 32), CGPoint(x: target.midX - size.width / 2, y: target.maxY + 32)]
            .map { FloatingGeometry.clamped($0, size: size, bounds: bounds) }
        return candidates.first { !CGRect(origin: $0, size: size).intersects(target.insetBy(dx: -12, dy: -12)) } ?? candidates[0]
    }
    static func appKitRect(normalized rect: CGRect, screen: CGRect) -> CGRect {
        CGRect(x: screen.minX + rect.minX * screen.width, y: screen.maxY - rect.maxY * screen.height, width: rect.width * screen.width, height: rect.height * screen.height)
    }
}
struct GuidanceTarget: Codable, Identifiable {
    var id: String
    var label: String
    var role: String
    var rect: CGRect // Normalized top-left display coordinates, matching the screenshot and canvas.
}
enum GuidancePolicy {
    static func normalized(_ rect: CGRect, in display: CGRect) -> CGRect? {
        let clipped = rect.intersection(display)
        guard !clipped.isNull, clipped.width >= 2, clipped.height >= 2, display.width > 0, display.height > 0 else { return nil }
        return CGRect(x: (clipped.minX - display.minX) / display.width, y: (clipped.minY - display.minY) / display.height, width: clipped.width / display.width, height: clipped.height / display.height)
    }
    static func fresh(captured: TimeInterval, now: TimeInterval, targetPID: Int32, foregroundPID: Int32, originalWindow: CGRect, currentWindow: CGRect?) -> Bool {
        guard now >= captured, now - captured <= 120, targetPID == foregroundPID, let currentWindow else { return false }
        return abs(originalWindow.minX - currentWindow.minX) < 3 && abs(originalWindow.minY - currentWindow.minY) < 3 && abs(originalWindow.width - currentWindow.width) < 3 && abs(originalWindow.height - currentWindow.height) < 3
    }
    static func drawing(for target: GuidanceTarget) -> ScreenDrawing {
        let rect = target.rect.insetBy(dx: -0.005, dy: -0.008).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        return ScreenDrawing(marks: [.init(kind: "circle", x: rect.minX, y: rect.minY, width: rect.width, height: rect.height), .init(kind: "label", x: rect.minX, y: min(0.94, rect.maxY + 0.012), text: String(target.label.prefix(100)))])
    }
}

/// Capture only for visual requests, never for greetings or unrelated questions.
enum ScreenQuestionPolicy {
    static func forbidsSnapshot(_ prompt: String) -> Bool {
        let text = prompt.lowercased().replacingOccurrences(of: "’", with: "'")
        return ["don't look at", "do not look at", "don't capture", "do not capture", "without looking at", "stop sharing", "stop looking"].contains(where: text.contains)
    }
    /// A new illustration is independent of whatever app happens to be behind Iris.
    static func wantsNewDrawing(_ prompt: String) -> Bool {
        if wantsSolution(prompt){return false}
        let text = prompt.lowercased()
        let words = Set(text.split { !$0.isLetter }.map(String.init))
        let existing = ["on my screen", "on the screen", "this diagram", "that diagram", "this graph", "this chart", "attached", "screenshot", "label this", "annotate this"].contains(where: text.contains)
        if existing || !words.isDisjoint(with: ["button", "toolbar", "menu", "control"]) { return false }
        if !words.isDisjoint(with: ["explain", "teach"]), words.isDisjoint(with: ["this", "that", "these", "those", "here", "screen", "button", "window", "page"]) { return true }
        let create = !words.isDisjoint(with: ["draw", "sketch", "illustrate", "visualize", "visualise", "create", "make", "generate"])
        let visual = !words.isDisjoint(with: ["diagram", "diagrams", "chart", "flowchart", "mindmap", "graph", "drawing", "sketch", "visually"])
        return (create || !words.isDisjoint(with: ["explain", "teach", "show"])) && visual || words.contains("draw") || words.contains("illustrate") || words.contains("visualize") || words.contains("visualise")
    }
    static func wantsSolution(_ prompt:String)->Bool {
        guard !forbidsSnapshot(prompt) else{return false}
        let t=prompt.lowercased(),words=Set(t.split{!$0.isLetter}.map(String.init))
        return !words.isDisjoint(with:["solve","answer","calculate","work"]) && (!words.isDisjoint(with:["screen","onscreen","this","question","problem","equation"]) || t.contains("work out"))
    }
    static func wantsSnapshot(_ prompt: String) -> Bool {
        let text = prompt.lowercased().replacingOccurrences(of: "’", with: "'")
        if forbidsSnapshot(prompt) {return false}
        if wantsSolution(prompt){return true}
        if wantsNewDrawing(prompt) { return false }
        let words = Set(text.split { !$0.isLetter }.map(String.init))
        if !words.isDisjoint(with: ["screen", "onscreen", "screenshot", "diagram", "diagrams", "chart", "graph"]) { return true }
        let visualAction = !words.isDisjoint(with: ["label", "annotate", "circle", "highlight", "point", "click", "seeing"])
        let visibleReference = !words.isDisjoint(with: ["this", "these", "here", "visible", "looking", "parts", "button", "window", "page"])
        return visualAction && visibleReference || text.contains("what am i looking at") || text.contains("what can you see") || text.contains("look at this")
    }
}
