import Foundation
import AppKit
import CoreText

/// Native document serialization; no shell commands or user code are executed.
enum DocumentWriter {
    static let formats: Set<String> = ["pdf", "rtf", "html", "txt", "md", "csv", "json"]
    static func data(content: String, format: String) throws -> Data {
        guard formats.contains(format), content.utf8.count <= 100000 else { throw IrisFailure.message("Choose a supported document format with up to 100 KB of content.") }
        switch format {
        case "pdf": return try pdf(attributed(content))
        case "rtf":
            let text = attributed(content)
            return try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        case "html":
            guard let url = Bundle.main.url(forResource: "iris-response", withExtension: "html"), let template = try? String(contentsOf: url, encoding: .utf8) else { throw IrisFailure.message("The document renderer is missing from this build.") }
            let printStyle = "<style>html,body{background:white!important;color:#171717!important}body{max-width:780px;margin:40px auto;padding:0 28px}pre{background:#f0f0f2}code{background:#eeeeef}th{background:#eeeeef}a{color:#255a9b}@media print{body{margin:0;max-width:none}pre,blockquote,tr{break-inside:avoid}}</style>"
            let html = template.replacingOccurrences(of: "__IRIS_PAYLOAD__", with: Data(content.utf8).base64EncodedString()).replacingOccurrences(of: "__IRIS_FONT_SIZE__", with: "15").replacingOccurrences(of: "</head>", with: printStyle + "</head>")
            return Data(html.utf8)
        case "json":
            _ = try JSONSerialization.jsonObject(with: Data(content.utf8), options: [.fragmentsAllowed])
            return Data(content.utf8)
        default: return Data(content.utf8)
        }
    }
    static func attributed(_ markdown: String) -> NSAttributedString {
        let output = NSMutableAttributedString(string: "")
        var code = false
        for line in markdown.components(separatedBy: .newlines) {
            if line.hasPrefix("```") { code.toggle(); continue }
            var text = line, size: CGFloat = 12, heading = false
            if !code {
                for level in 1...6 {
                    let prefix = String(repeating: "#", count: level) + " "
                    if text.hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)); size = max(13, 26 - CGFloat(level) * 2); heading = true; break }
                }
                if text.hasPrefix("- ") || text.hasPrefix("* ") { text = "• " + text.dropFirst(2) }
            }
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 3; paragraph.paragraphSpacing = heading ? 10 : 6
            let parsed = code ? AttributedString(text) : ((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
            for run in parsed.runs {
                let intent = run.inlinePresentationIntent ?? []
                let mono = code || intent.contains(.code)
                var font = mono ? NSFont.monospacedSystemFont(ofSize: 11, weight: .regular) : NSFont.systemFont(ofSize: size, weight: heading || intent.contains(.stronglyEmphasized) ? .semibold : .regular)
                if intent.contains(.emphasized) { font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) }
                output.append(NSAttributedString(string: String(parsed[run.range].characters), attributes: [.font: font, .foregroundColor: NSColor.black, .paragraphStyle: paragraph]))
            }
            output.append(NSAttributedString(string: "\n", attributes: [.font: NSFont.systemFont(ofSize: size), .paragraphStyle: paragraph]))
        }
        return output
    }
    private static func pdf(_ text: NSAttributedString) throws -> Data {
        let bytes = NSMutableData()
        var paper = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let consumer = CGDataConsumer(data: bytes as CFMutableData), let context = CGContext(consumer: consumer, mediaBox: &paper, nil) else { throw IrisFailure.message("The PDF writer couldn't start.") }
        let setter = CTFramesetterCreateWithAttributedString(text)
        let path = CGPath(rect: CGRect(x: 48, y: 48, width: 516, height: 696), transform: nil)
        var offset = 0, pages = 0
        repeat {
            guard pages < 100 else { throw IrisFailure.message("This document exceeds the 100-page export limit.") }
            context.beginPDFPage(nil); context.textMatrix = .identity
            let frame = CTFramesetterCreateFrame(setter, CFRange(location: offset, length: 0), path, nil)
            CTFrameDraw(frame, context); context.endPDFPage()
            let length = CTFrameGetVisibleStringRange(frame).length
            if text.length > offset, length == 0 { throw IrisFailure.message("The document contains text that couldn't be paginated.") }
            offset += length; pages += 1
        } while offset < text.length
        context.closePDF()
        return bytes as Data
    }
}
