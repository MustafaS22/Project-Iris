import XCTest
@testable import IrisCore
final class CreationPolicyTests: XCTestCase {
    func testExportNamesAreValidatedAndExtensionsAreNotRepeated() throws {
        XCTAssertEqual(try CreationPolicy.filename(" Report.PDF ", format: "pdf"), "Report.PDF")
        XCTAssertEqual(try CreationPolicy.filename("Image", format: "png"), "Image.png")
        for name in ["", "..", "a/b", "a\\b", "a\0b"] { XCTAssertThrowsError(try CreationPolicy.filename(name, format: "pdf")) }
        XCTAssertThrowsError(try CreationPolicy.filename("Document", format: "exe"))
    }
    func testSingleDocumentFenceIsUnwrappedButEmbeddedCodeIsKept() {
        XCTAssertEqual(CreationPolicy.editableText("```json\n{\"ok\":true}\n```"), "{\"ok\":true}")
        XCTAssertEqual(CreationPolicy.editableText("# Title\n\n```swift\nlet x = 1\n```"), "# Title\n\n```swift\nlet x = 1\n```")
    }
    func testBackendActionsAreNotPresentedAsEditableContent() {
        let reply = "# A draft\n\n```iris-actions\n{\"actions\":[{\"type\":\"writeFile\",\"path\":\"x\"}]}\n```"
        XCTAssertEqual(CreationPolicy.editableText(reply), "# A draft")
        XCTAssertTrue(CreationPolicy.instruction(format: "csv", tone: "Academic", length: "Short").contains("Never emit computer actions"))
    }
}
