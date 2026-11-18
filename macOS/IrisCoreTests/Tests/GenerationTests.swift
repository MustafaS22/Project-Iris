import XCTest
import PDFKit
import AppKit
@testable import IrisCore

final class GenerationTests: XCTestCase {
    @MainActor func testRealPDFPaginationAndRichTextEncoding() throws {
        let source = "# Generated study guide\n\n**Important**: α + β ≤ π.\n\n" + String(repeating: "A complete paragraph with enough text to exercise native pagination and keep the content readable on each page.\n\n", count: 95)
        let bytes = try DocumentWriter.data(content: source, format: "pdf")
        let pdf = try XCTUnwrap(PDFDocument(data: bytes))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        XCTAssertTrue(pdf.string?.contains("Generated study guide") == true)
        XCTAssertTrue(pdf.string?.contains("Important") == true)
        let rtf = try DocumentWriter.data(content: "# Title\nA **bold** paragraph.", format: "rtf")
        let decoded = try NSAttributedString(data: rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
        XCTAssertTrue(decoded.string.contains("bold")); XCTAssertFalse(decoded.string.contains("**"))
    }
    @MainActor func testTextFormatsValidateRatherThanFakeBinaryFiles() throws {
        XCTAssertEqual(String(data: try DocumentWriter.data(content: "a,b\n1,2", format: "csv"), encoding: .utf8), "a,b\n1,2")
        XCTAssertNoThrow(try DocumentWriter.data(content: "{\"ok\":true}", format: "json"))
        XCTAssertThrowsError(try DocumentWriter.data(content: "{bad}", format: "json"))
        XCTAssertThrowsError(try DocumentWriter.data(content: "text", format: "docx"))
        XCTAssertThrowsError(try DocumentWriter.data(content: String(repeating: "x", count: 100001), format: "pdf"))
    }
    @MainActor func testImageDecoderRequiresAnActualImage() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let response = try JSONSerialization.data(withJSONObject: ["data": [["b64_json": png.base64EncodedString()]]])
        let decoded = try ImageGenerationService.decode(response)
        XCTAssertNotNil(NSBitmapImageRep(data: decoded))
        let bad = try JSONSerialization.data(withJSONObject: ["data": [["b64_json": Data("not an image".utf8).base64EncodedString()]]])
        XCTAssertThrowsError(try ImageGenerationService.decode(bad))
    }
}
