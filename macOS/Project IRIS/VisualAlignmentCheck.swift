import AppKit

/// Explicit developer diagnostic: captures only its own synthetic window, never user content.
@MainActor enum VisualAlignmentCheck {
    static let argument = "--iris-check-alignment"
    private static var window: NSWindow?
    private static let markers = [CGPoint(x: 100, y: 90), CGPoint(x: 620, y: 90), CGPoint(x: 100, y: 390), CGPoint(x: 620, y: 390)]
    static func run() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("IrisAlignmentCheck", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let frame = CGRect(x: screen.visibleFrame.midX - 360, y: screen.visibleFrame.midY - 240, width: 720, height: 480)
            let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.title = "Iris alignment check"; window.backgroundColor = .white
            window.contentView = CalibrationView(frame: CGRect(origin: .zero, size: frame.size))
            self.window = window
            NSApp.activate(); window.makeKeyAndOrderFront(nil)
            try await Task.sleep(for: .milliseconds(650))
            let snapshot = try await ScreenGuidance.capture(app: NSRunningApplication.current)
            let firstDisplayTop = NSScreen.screens[0].frame.maxY
            let expected = markers.map { point in [frame.minX + point.x, firstDisplayTop - frame.maxY + point.y] }
            func rect(_ r: CGRect) -> [CGFloat] { [r.minX, r.minY, r.width, r.height] }
            let report: [String: Any] = ["imageFrame": rect(snapshot.projection.imageFrame), "displayFrame": rect(snapshot.projection.displayFrame), "expectedGlobalPoints": expected, "windowFrame": rect(snapshot.windowFrame)]
            try snapshot.attachment.image!.data.write(to: directory.appendingPathComponent("capture.jpg"), options: .atomic)
            try JSONSerialization.data(withJSONObject: report, options: .prettyPrinted).write(to: directory.appendingPathComponent("result.json"), options: .atomic)
        } catch {
            try? JSONSerialization.data(withJSONObject: ["error": error.localizedDescription]).write(to: directory.appendingPathComponent("result.json"), options: .atomic)
        }
    }
    private final class CalibrationView: NSView {
        override var isFlipped: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.white.setFill(); bounds.fill()
            let colors = [NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1), NSColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)]
            ("Iris screen alignment · synthetic content only" as NSString).draw(at: CGPoint(x: 24, y: 20), withAttributes: [.font: NSFont.systemFont(ofSize: 20, weight: .semibold), .foregroundColor: NSColor.black])
            for (i, point) in markers.enumerated() {
                colors[i].setFill(); NSBezierPath(rect: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)).fill()
                ("Anchor \(i + 1)" as NSString).draw(at: CGPoint(x: point.x - 30, y: point.y + 18), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black])
            }
        }
    }
}
