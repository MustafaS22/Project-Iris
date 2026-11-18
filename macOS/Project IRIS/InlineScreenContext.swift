import AppKit
import ScreenCaptureKit
import Vision

/// Optional local OCR of the focused app only. No screen image is uploaded or retained.
@MainActor enum InlineScreenContext {
    nonisolated static func region(window: CGRect, content: CGRect?, caret: CGPoint) -> CGRect {
        let fallback = CGRect(x: window.minX, y: window.minY + min(95, window.height / 4), width: window.width, height: window.height - min(95, window.height / 4))
        let allowed = content.map { $0.intersection(window) }.flatMap { $0.isNull || $0.isEmpty ? nil : $0 } ?? fallback
        return CGRect(x: caret.x - 350, y: caret.y - 480, width: 1000, height: 620).intersection(allowed)
    }
    static func text(around target: InlineDraftTarget) async -> String {
        guard CGPreflightScreenCaptureAccess(), target.isStillFocused() else { return "" }
        do {
            let contentBounds = target.visibleContentBounds()
            let shareable = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            try Task.checkCancellation()
            guard target.isStillFocused() else { return "" }
            let order = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { $0[kCGWindowNumber as String] as? UInt32 }
            guard let window = shareable.windows.filter({ $0.owningApplication?.processID == target.app.processIdentifier && $0.windowLayer == 0 && $0.frame.width > 100 && $0.frame.height > 100 }).min(by: { (order.firstIndex(of: $0.windowID) ?? Int.max) < (order.firstIndex(of: $1.windowID) ?? Int.max) }) else { return "" }
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let display = NSScreen.screens.first(where: { $0.frame.contains(target.caret) })
            let displayBounds = display.map { CGRect(x: $0.frame.minX, y: top-$0.frame.maxY, width: $0.frame.width, height: $0.frame.height) } ?? window.frame
            let nearby = region(window: window.frame, content: contentBounds, caret: CGPoint(x: target.caret.x, y: top-target.caret.y)).intersection(displayBounds)
            guard !nearby.isNull, nearby.width > 20, nearby.height > 20 else { return "" }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()
            config.width = min(2200, max(1, Int(window.frame.width * CGFloat(filter.pointPixelScale))))
            config.height = max(1, Int(CGFloat(config.width) * window.frame.height / window.frame.width))
            config.showsCursor = false; config.ignoreShadowsSingleWindow = true; config.scalesToFit = true
            let raw = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            try Task.checkCancellation()
            let crop = CGRect(x: (nearby.minX-window.frame.minX)/window.frame.width*CGFloat(raw.width), y: (nearby.minY-window.frame.minY)/window.frame.height*CGFloat(raw.height), width: nearby.width/window.frame.width*CGFloat(raw.width), height: nearby.height/window.frame.height*CGFloat(raw.height)).integral
            guard let image = raw.cropping(to: crop) else { return "" }
            let task = Task.detached(priority: .userInitiated) {
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true
                try VNImageRequestHandler(cgImage: image).perform([request])
                return String((request.results ?? []).sorted {
                    abs($0.boundingBox.midY-$1.boundingBox.midY) > 0.015 ? $0.boundingBox.midY > $1.boundingBox.midY : $0.boundingBox.minX < $1.boundingBox.minX
                }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n").prefix(2400))
            }
            let text = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled, target.isStillFocused() else { return "" }
            return text.isEmpty ? "" : "Locally read text near the focused field:\n" + text
        } catch { return "" } // Existing AX context still works; never open permission settings here.
    }
}
