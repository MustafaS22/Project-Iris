import XCTest
@testable import IrisCore

final class StreamingTests: XCTestCase {
    func testResponseEventsProducePartialTextBeforeCompletion() throws {
        var stream = ProviderStream(kind: .openAI)
        try stream.consume("data: {\"type\":\"response.reasoning_text.delta\",\"delta\":\"private\"}")
        XCTAssertEqual(stream.text, "")
        try stream.consume("data: {\"type\":\"response.output_text.delta\",\"delta\":\"First line.\\n\"}")
        XCTAssertEqual(stream.text, "First line.\n"); XCTAssertFalse(stream.completed)
        try stream.consume("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Second line.\"}")
        try stream.consume("data: {\"type\":\"response.completed\"}")
        XCTAssertTrue(stream.completed); XCTAssertEqual(stream.text, "First line.\nSecond line.")
    }
    func testGeminiAndLocalExcludeReasoningFields() throws {
        var gemini = ProviderStream(kind: .gemini)
        try gemini.consume("data: {\"candidates\":[{\"content\":{\"parts\":[{\"thought\":true,\"text\":\"private\"},{\"text\":\"Public answer\"}]},\"finishReason\":\"STOP\"}]}")
        XCTAssertEqual(gemini.text, "Public answer"); XCTAssertTrue(gemini.completed)
        var local = ProviderStream(kind: .local)
        try local.consume("data: {\"choices\":[{\"delta\":{\"reasoning_content\":\"private\",\"content\":\"Hello\"}}]}")
        XCTAssertEqual(local.text, "Hello"); XCTAssertFalse(local.completed)
        try local.consume("data: [DONE]"); XCTAssertTrue(local.completed)
    }
    func testEveryStreamPrefixKeepsReasoningAndActionsHidden() {
        let raw = "<think>SECRET reasoning</think>Here is the answer.\n```iris-actions\n{\"actions\":[{\"type\":\"openApplication\",\"target\":\"Safari\"}]}\n```"
        for count in 1...raw.count {
            let visible = StreamingPresentation.visibleText(String(raw.prefix(count)))
            XCTAssertFalse(visible.contains("SECRET")); XCTAssertFalse(visible.contains("actions")); XCTAssertFalse(visible.contains("openApplication"))
        }
        XCTAssertEqual(StreamingPresentation.visibleText(raw), "Here is the answer.")
    }
    func testBarePartialActionAndCodeBoundaries() {
        let prefix = "Preparing. {\"actions\":[{\"type\":\"writeFile\""
        XCTAssertEqual(StreamingPresentation.visibleText(prefix), "Preparing.")
        XCTAssertEqual(StreamingPresentation.visibleText("Hello world"), "Hello world")
        XCTAssertEqual(StreamingPresentation.visibleText("Code:\n```swift\nlet x = 1"), "Code:")
        XCTAssertTrue(StreamingPresentation.visibleText("Code:\n```swift\nlet x = 1\n```").contains("let x = 1"))
    }
    func testInterruptedStreamDoesNotBecomeCompleted() throws {
        var stream = ProviderStream(kind: .openAI)
        try stream.consume("data: {\"type\":\"response.output_text.delta\",\"delta\":\"Partial\"}")
        XCTAssertThrowsError(try stream.consume("data: {\"type\":\"response.incomplete\"}"))
        XCTAssertFalse(stream.completed); XCTAssertEqual(stream.text, "Partial")
    }
}
