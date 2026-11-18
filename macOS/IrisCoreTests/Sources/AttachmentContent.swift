import AppKit
import PDFKit
import Vision
import UniformTypeIdentifiers
import ImageIO

struct AttachedContext: Identifiable {
    var id = UUID()
    var name: String
    var text: String
    var file: ChatFileReference?
    var image: ModelImage?
    var note: String?
}

struct ModelImage: Sendable {
    var data: Data
    var mimeType = "image/jpeg"
    var dataURL: String { "data:\(mimeType);base64,\(data.base64EncodedString())" }
}

enum AttachmentReader {
    static let maximumCount = 6
    static let maximumText = 18000
    static let contentTypes: [UTType] = [.pdf, .image, .text, .sourceCode, .json, .commaSeparatedText, .rtf, .init(filenameExtension: "docx")!]
    static func read(url: URL) throws -> AttachedContext {
        guard url.isFileURL else { throw IrisFailure.message("Drop a local file from Finder. Paste website links into your message instead.") }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .contentTypeKey])
        guard values.isRegularFile == true else { throw IrisFailure.message("Choose a file, not a folder.") }
        guard (values.fileSize ?? 0) <= 20_000_000 else { throw IrisFailure.message("Choose a file smaller than 20 MB.") }
        let ext = url.pathExtension.lowercased()
        var text = "", note: String?, image: ModelImage?
        if values.contentType?.conforms(to: .image) == true || ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "webp", "gif", "bmp"].contains(ext) {
            // Decode with ImageIO, apply EXIF rotation and bound memory before OCR or upload.
            guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 2048] as CFDictionary) else {
                throw IrisFailure.message("This image could not be decoded. Try exporting it as PNG or JPEG.")
            }
            let bitmap = NSBitmapImageRep(cgImage: thumbnail)
            guard let bytes = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]), bytes.count <= 2_000_000 else { throw IrisFailure.message("This image is too complex. Export a smaller JPEG and try again.") }
            image = ModelImage(data: bytes)
            text = (try? recognize(thumbnail)) ?? ""
            note = "Image included · requires a vision-capable model"
            if CGImageSourceGetCount(source) > 1 { note = "First frame included · requires a vision-capable model" }
        } else if ext == "pdf" {
            guard let pdf = PDFDocument(url: url), !pdf.isLocked else { throw IrisFailure.message("This PDF is unreadable or password-protected. Unlock it and attach it again.") }
            let count = min(pdf.pageCount, 40)
            var pages: [String] = []
            var foundText = false
            for index in 0..<count {
                try Task.checkCancellation()
                guard let page = pdf.page(at: index) else { continue }
                var pageText = page.string ?? ""
                if pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let preview = page.thumbnail(of: NSSize(width: 1600, height: 2000), for: .mediaBox)
                    if let cg = preview.cgImage(forProposedRect: nil, context: nil, hints: nil) { pageText = (try? recognize(cg)) ?? "" }
                }
                if !pageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { foundText = true }
                pages.append("Page \(index + 1):\n\(pageText)")
                if pages.joined(separator: "\n").count > maximumText { break }
            }
            text = pages.joined(separator: "\n\n")
            guard foundText else { throw IrisFailure.message("No readable text was found in this PDF. Attach page images to discuss diagrams or scans.") }
            note = "Extracted text · \(min(pages.count, count)) of \(pdf.pageCount) pages"
        } else if ext == "rtf" || ext == "docx" {
            text = try NSAttributedString(url: url, options: [.documentType: ext == "rtf" ? NSAttributedString.DocumentType.rtf : .officeOpenXML], documentAttributes: nil).string
        } else {
            let bytes = try Data(contentsOf: url)
            let typeIsText = values.contentType?.conforms(to: .text) == true
            let codeExtensions = ["txt", "md", "markdown", "swift", "py", "js", "jsx", "ts", "tsx", "json", "csv", "tsv", "html", "css", "log", "yaml", "yml", "xml", "sql", "sh", "c", "cpp", "h", "java", "rs", "go", "toml"]
            guard typeIsText || codeExtensions.contains(ext) else { throw IrisFailure.message("This file type isn't supported. Attach an image, PDF, Word document, RTF, text or code file.") }
            guard !bytes.contains(0) || bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]) else { throw IrisFailure.message("This file contains binary data. Export it as text or PDF first.") }
            guard let decoded = String(data: bytes, encoding: .utf8) ?? ((bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF])) ? String(data: bytes, encoding: .utf16) : nil) else { throw IrisFailure.message("This text encoding isn't supported. Save the file as UTF-8 or UTF-16 and try again.") }
            text = decoded
        }
        guard image != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw IrisFailure.message("This file is empty or contains no readable text.") }
        if text.count > maximumText { note = (note.map { $0 + " · " } ?? "") + "First 18,000 characters included" }
        return AttachedContext(name: url.lastPathComponent, text: String(text.prefix(maximumText)), image: image, note: note)
    }
    private static func recognize(_ image: CGImage) throws -> String {
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}

/// Provider-specific wire formats. Images belong to the latest user turn, never to system instructions.
enum AttachmentPayload {
    static func messages(_ messages: [ChatMessage], images: [ModelImage], provider: String) -> [[String: Any]] {
        let history = Array(messages.suffix(16))
        let lastUser = history.lastIndex { $0.role == "user" }
        return history.enumerated().map { index, message in
            let text = String((message.role == "assistant" ? ResponsePresentation.visibleText(message.text) : message.text).prefix(12000))
            let currentImages = index == lastUser ? images : []
            if provider == "gemini" {
                var parts: [[String: Any]] = [["text": text]]
                parts += currentImages.map { ["inlineData": ["mimeType": $0.mimeType, "data": $0.data.base64EncodedString()]] }
                return ["role": message.role == "assistant" ? "model" : "user", "parts": parts]
            }
            guard !currentImages.isEmpty else { return ["role": message.role, "content": text] }
            let responses = provider == "openai"
            var content: [[String: Any]] = [["type": responses ? "input_text" : "text", "text": text]]
            content += currentImages.map { responses ? ["type": "input_image", "image_url": $0.dataURL] : ["type": "image_url", "image_url": ["url": $0.dataURL]] }
            return ["role": message.role, "content": content]
        }
    }
    static func text(_ attachments: [AttachedContext]) -> String {
        guard !attachments.isEmpty else { return "" }
        let allowance = max(1, 18000 / attachments.count - 250)
        return attachments.map { item in
            "Attachment: \(item.name)\n\(item.note ?? "Extracted text")\n" + String(item.text.prefix(allowance)) + (item.text.count > allowance ? "\n[Attachment text shortened to fit this request.]" : "")
        }.joined(separator: "\n\n")
    }
}
