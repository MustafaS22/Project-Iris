import XCTest
import AppKit
import PDFKit
@testable import IrisCore

final class AttachmentTests: XCTestCase {
    private func fixture(_ name: String, bytes: Data) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(name); try bytes.write(to: url); return url
    }
    private func picture(format: NSBitmapImageRep.FileType = .png) throws -> Data {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 60, bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        try XCTUnwrap(bitmap.bitmapData).initialize(repeating: 128, count: bitmap.bytesPerRow * bitmap.pixelsHigh)
        return try XCTUnwrap(bitmap.representation(using: format, properties: [:]))
    }
    func testImageWithoutTextIsAcceptedAndNormalizedForVision() throws {
        let item = try AttachmentReader.read(url: fixture("photo.png", bytes: picture()))
        let image = try XCTUnwrap(item.image)
        XCTAssertEqual(image.mimeType, "image/jpeg")
        XCTAssertNotNil(NSBitmapImageRep(data: image.data))
        XCTAssertLessThanOrEqual(image.data.count, 2_000_000)
        XCTAssertTrue(item.note?.contains("vision-capable") == true)
    }
    func testGIFAndTIFFHaveSameImagePathAsPNG() throws {
        for (name, format) in [("photo.gif", NSBitmapImageRep.FileType.gif), ("photo.tiff", .tiff)] {
            XCTAssertNotNil(try AttachmentReader.read(url: fixture(name, bytes: picture(format: format))).image)
        }
    }
    func testTextAndSourceFormatsAndUTF16() throws {
        for name in ["notes.md", "component.tsx", "config.yaml", "table.csv", "code.py"] {
            let item = try AttachmentReader.read(url: fixture(name, bytes: Data("Hello α β".utf8)))
            XCTAssertEqual(item.text, "Hello α β"); XCTAssertNil(item.image)
        }
        let utf16 = try XCTUnwrap("Hello Ω".data(using: .utf16))
        XCTAssertEqual(try AttachmentReader.read(url: fixture("unicode.txt", bytes: utf16)).text, "Hello Ω")
    }
    @MainActor func testPDFAndRichDocumentsExtractRealContents() throws {
        let pdf = try DocumentWriter.data(content: "Attachment test with a useful paragraph.", format: "pdf")
        let item = try AttachmentReader.read(url: fixture("notes.pdf", bytes: pdf))
        XCTAssertTrue(item.text.contains("useful paragraph")); XCTAssertTrue(item.note?.contains("1 of 1 pages") == true)
        let rich = NSAttributedString(string: "Rich document contents")
        for (name, type) in [("notes.rtf", NSAttributedString.DocumentType.rtf), ("notes.docx", .officeOpenXML)] {
            let bytes = try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: type])
            XCTAssertTrue(try AttachmentReader.read(url: fixture(name, bytes: bytes)).text.contains("Rich document contents"))
        }
    }
    func testInvalidEmptyOversizedAndBinaryFilesFailClearly() throws {
        for (name, bytes) in [("empty.txt", Data()), ("photo.png", Data("bad image".utf8)), ("binary.txt", Data([1, 0, 3])), ("archive.zip", Data("not text input".utf8)), ("huge.txt", Data(repeating: 65, count: 20_000_001))] {
            XCTAssertThrowsError(try AttachmentReader.read(url: fixture(name, bytes: bytes)), name)
        }
    }
    func testLongTextHasVisibleTruncationAndFairPerFileBudget() throws {
        let item = try AttachmentReader.read(url: fixture("long.md", bytes: Data(String(repeating: "a", count: 19000).utf8)))
        XCTAssertEqual(item.text.count, 18000); XCTAssertTrue(item.note?.contains("18,000") == true)
        let text = AttachmentPayload.text([item, .init(name: "second.md", text: "Important second document")])
        XCTAssertLessThanOrEqual(text.count, 18000)
        XCTAssertTrue(text.contains("Important second document")); XCTAssertTrue(text.contains("shortened"))
    }
    func testImagesAreInLatestUserTurnForEachProvider() throws {
        let bytes = Data([0xFF, 0xD8, 0xFF])
        let images = [ModelImage(data: bytes), ModelImage(data: Data([1, 2, 3]))]
        let messages: [ChatMessage] = [.init(role: "user", text: "Old"), .init(role: "assistant", text: "Earlier response"), .init(role: "user", text: "Compare these")]
        for provider in ["openai", "gemini", "local"] {
            let payload = AttachmentPayload.messages(messages, images: images, provider: provider)
            let encoded = try JSONSerialization.data(withJSONObject: payload)
            XCTAssertFalse(encoded.isEmpty)
            if provider == "gemini" {
                XCTAssertEqual((payload[0]["parts"] as? [[String: Any]])?.count, 1)
                let parts = try XCTUnwrap(payload[2]["parts"] as? [[String: Any]])
                XCTAssertEqual(parts.count, 3)
                XCTAssertEqual((parts[1]["inlineData"] as? [String: String])?["data"], bytes.base64EncodedString())
            } else {
                XCTAssertEqual(payload[0]["content"] as? String, "Old")
                let content = try XCTUnwrap(payload[2]["content"] as? [[String: Any]])
                XCTAssertEqual(content.count, 3)
                if provider == "openai" {
                    XCTAssertEqual(content[1]["type"] as? String, "input_image")
                    XCTAssertEqual(content[1]["image_url"] as? String, images[0].dataURL)
                } else {
                    XCTAssertEqual(content[1]["type"] as? String, "image_url")
                    XCTAssertEqual((content[1]["image_url"] as? [String: String])?["url"], images[0].dataURL)
                }
            }
        }
    }
    func testTextOnlyRequestsKeepExistingWireFormat() {
        let payload = AttachmentPayload.messages([.init(role: "user", text: "Hello")], images: [], provider: "openai")
        XCTAssertEqual(payload[0]["content"] as? String, "Hello")
    }
}
