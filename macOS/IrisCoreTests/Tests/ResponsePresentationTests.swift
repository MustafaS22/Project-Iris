import XCTest
@testable import IrisCore

final class ResponsePresentationTests: XCTestCase {
    func testScreenshotStyleBackendExampleIsHiddenAndNotExecutable() {
        let reply = "I can help.\n\nHere's an example of creating a new action:\n```\n{\"actions\":[{\"type\":\"openApplication\",\"target\":\"Safari\"}]}\n```"
        XCTAssertEqual(ResponsePresentation.visibleText(reply), "I can help.")
        XCTAssertNil(ActionPolicy.parse(reply))
    }
    func testReservedMalformedBlocksAreHiddenButValidProtocolStillParses() {
        XCTAssertEqual(ResponsePresentation.visibleText("Ready.\n```iris-actions\nnot json"), "Ready.")
        let reply = "Ready.\n```iris-actions\n{\"actions\":[{\"type\":\"attachFile\",\"folder\":\"f\",\"path\":\"report.pdf\"}]}\n```\nOpen it below."
        XCTAssertEqual(ActionPolicy.parse(reply)?.first?.type, "attachFile")
        XCTAssertFalse(ResponsePresentation.visibleText(reply).contains("actions"))
        XCTAssertTrue(ResponsePresentation.visibleText(reply).contains("Open it below."))
    }
    func testBareBackendObjectsAreHiddenWithoutRemovingRequestedSourceCode() {
        let backend = "Result: {\"actions\":[{\"type\":\"writeFile\",\"content\":\"brace } and quote \\\"\"}]} Done."
        XCTAssertEqual(ResponsePresentation.visibleText(backend), "Result:  Done.")
        let code = "```swift\nlet value = [1, 2, 3]\n```\nMath: $x^2$."
        XCTAssertEqual(ResponsePresentation.visibleText(code), code)
        let data = "```json\n{\"actions\":[\"walk\",\"rest\"]}\n```"
        XCTAssertEqual(ResponsePresentation.visibleText(data), data)
    }
    func testFileCardsRoundTripAndOlderMessagesDecode() throws {
        let file = ChatFileReference(name: "report.pdf", folderID: "allowed", relativePath: "reports/report.pdf")
        let message = ChatMessage(role: "assistant", text: "Here it is.", files: [file])
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: JSONEncoder().encode(message))
        XCTAssertEqual(decoded.files?.first?.relativePath, "reports/report.pdf")
        let old = "{\"id\":\"00000000-0000-0000-0000-000000000001\",\"role\":\"assistant\",\"text\":\"old reply\"}"
        XCTAssertNil(try JSONDecoder().decode(ChatMessage.self, from: Data(old.utf8)).files)
    }
}
