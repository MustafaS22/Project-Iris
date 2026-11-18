import SwiftUI
import WebKit
import AppKit

/// Renders model output offline. Raw user messages and reference previews stay verbatim.
struct FormattedResponse: View {
    let text: String
    var fontSize: CGFloat = 15
    @AppStorage("IrisChatTextSize") private var readingSize = 15.0
    @State private var height: CGFloat = 40
    var body: some View {
        ResponseWebView(text: text, fontSize: max(fontSize, min(23, max(15, readingSize))), height: $height)
            .frame(maxWidth: .infinity, alignment: .leading).frame(height: height)
    }
}

private struct ResponseWebView: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    @Binding var height: CGFloat
    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "irisSize")
        let view = ResponseWKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        if context.coordinator.fontSize != fontSize {
            context.coordinator.fontSize = fontSize
            context.coordinator.loaded = false; context.coordinator.ready = false
        }
        let key = text + "|" + String(Double(fontSize))
        guard context.coordinator.key != key else { return }
        context.coordinator.key = key
        let payload = Data(text.utf8).base64EncodedString()
        context.coordinator.pendingPayload = payload
        if context.coordinator.loaded {
            if context.coordinator.ready { view.evaluateJavaScript("window.irisUpdate('" + payload + "')", completionHandler: nil) }
            return
        }
        guard let template = ResponseAssets.template else {
            view.loadHTMLString("<body style='color:#f5f5f7'>" + text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;") + "</body>", baseURL: nil); return
        }
        context.coordinator.loaded = true
        let html = template.replacingOccurrences(of: "__IRIS_PAYLOAD__", with: payload)
            .replacingOccurrences(of: "__IRIS_FONT_SIZE__", with: String(Double(fontSize)))
        view.loadHTMLString(html, baseURL: nil)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "irisSize")
        view.stopLoading(); view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var fontSize: CGFloat = 0
        var key = ""
        var loaded = false
        var ready = false
        var pendingPayload = ""
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            ready = true
            webView.evaluateJavaScript("window.irisUpdate('" + pendingPayload + "')", completionHandler: nil)
        }
        init(height: Binding<CGFloat>) { self.height = height }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let number = message.body as? NSNumber else { return }
            let value = max(24, min(CGFloat(number.doubleValue), 100000))
            if abs(height.wrappedValue - value) > 1 { height.wrappedValue = value }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if navigationAction.navigationType == .linkActivated {
                if ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else { decisionHandler(url.absoluteString == "about:blank" ? .allow : .cancel) }
        }
    }
}

struct MessageContent: View {
    @ObservedObject var iris: IrisOrchestrator
    let message: ChatMessage
    var fontSize: CGFloat = 15
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if message.role == "assistant" {
                let clean = ResponsePresentation.visibleText(message.text).components(separatedBy: "```iris-study")[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { FormattedResponse(text: clean, fontSize: fontSize) }
                else if StudioArtifact.parse(message.text) == nil && message.files?.isEmpty != false { Text("Review the prepared action below.").font(.caption).foregroundStyle(IrisDesign.secondary) }
            } else {
                // Selectable SwiftUI Text can render vertically inverted when macOS
                // recycles transcript rows. Keep prompts on the regular text renderer.
                Text(verbatim: message.text)
                    .font(.system(size: fontSize)).lineSpacing(4)
                    .textSelection(.disabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .contextMenu {
                        Button("Copy message") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(message.text, forType: .string)
                        }
                    }
            }
            if message.role == "assistant", let artifact = StudioArtifact.parse(message.text) { StudioArtifactView(iris: iris, artifact: artifact, messageID: message.id) }
            if message.role == "assistant", !message.text.isEmpty, message.files?.isEmpty != false {
                Menu {
                    Button("PDF") { iris.exportReply(message, format: "pdf") }
                    Button("Rich text · RTF") { iris.exportReply(message, format: "rtf") }
                    Button("HTML · typeset equations") { iris.exportReply(message, format: "html") }
                    Button("Markdown") { iris.exportReply(message, format: "md") }
                    Button("Plain text") { iris.exportReply(message, format: "txt") }
                } label: { Label("Export", systemImage: "square.and.arrow.up").font(.system(size: 11)) }.menuStyle(.borderlessButton).fixedSize().disabled(iris.busy)
            }
            ForEach(message.files ?? []) { file in ChatFileCard(iris: iris, file: file) }
        }
    }
}

/// Let the surrounding transcript own vertical scrolling; equations and code can pan horizontally.
private final class ResponseWKWebView: WKWebView {
    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) { super.scrollWheel(with: event) }
        else { nextResponder?.scrollWheel(with: event) }
    }
}

private enum ResponseAssets {
    static let template: String? = Bundle.main.url(forResource: "iris-response", withExtension: "html").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
}
