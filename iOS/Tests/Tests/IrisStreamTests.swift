import XCTest
@testable import IrisStream
final class IrisStreamTests: XCTestCase {
    func testReasoningAndOtherCandidatesAreNotDisplayed() throws {
        let fixture = #"data: {"candidates":[{"content":{"parts":[{"text":"private reasoning","thought":true},{"text":"Hi "},{"text":"there!"}]}},{"content":{"parts":[{"text":"another answer"}]}}]}"#
        XCTAssertEqual(try IrisStream.text(from: fixture), "Hi there!")
    }
    func testDeltasPreserveMarkdownAndUnicode() throws {
        let lines = [#"data: {"candidates":[{"content":{"parts":[{"text":"**Hello**\n"}]}}]}"#, #"data: {"candidates":[{"content":{"parts":[{"text":"مرحبا"}]}}]}"#]
        XCTAssertEqual(try lines.map(IrisStream.text(from:)).joined(), "**Hello**\nمرحبا")
    }
    func testMetadataAndMalformedLinesNeverLeakIntoChat() throws {
        for line in ["event: message", ": keepalive", "data: [DONE]", "data: {}", "data: broken"] {
            XCTAssertEqual(try IrisStream.text(from: line), "")
        }
    }
    func testProviderErrorCannotBeMistakenForSuccessfulAnswer() {
        XCTAssertThrowsError(try IrisStream.text(from: #"data: {"error":{"code":429,"message":"Quota"}}"#))
    }
}

final class IrisOpenAIStreamTests: XCTestCase {
    func testOnlyOutputTextIsDisplayed() throws {
        XCTAssertEqual(try IrisStream.openAI(#"data: {"type":"response.output_text.delta","delta":"Hello"}"#), .delta("Hello"))
        XCTAssertEqual(try IrisStream.openAI(#"data: {"type":"response.reasoning_text.delta","delta":"private"}"#), .ignore)
        XCTAssertEqual(try IrisStream.openAI(#"data: {"type":"response.completed"}"#), .completed)
    }
    func testFailedAndIncompleteEventsAreNotSuccess() {
        for type in ["error", "response.failed", "response.incomplete"] {
            XCTAssertThrowsError(try IrisStream.openAI("data: {\"type\":\"\(type)\"}"))
        }
    }
    func testNonSpeechPayloadCannotBePlayed() throws {
        for object: [String: Any] in [[:], ["status":"in_progress","steps":[]], ["status":"completed","steps":[["type":"model_output","content":[["type":"audio","mime_type":"audio/wav","data":"YWJj"]]]]]] {
            let data = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try IrisAudio.decode(data))
        }
    }
}
