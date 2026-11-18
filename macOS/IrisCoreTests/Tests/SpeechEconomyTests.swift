import XCTest
@testable import IrisCore

final class SpeechEconomyTests: XCTestCase {
    func testLongStreamMakesAtMostOneSpeechRequest() {
        var chunker = ReplySpeechChunker(economy: true)
        let text = String(repeating: "This is a clear sentence explaining the answer in detail. ", count: 45)
        var output: [String] = []
        for length in stride(from: 1, through: text.count, by: 17) {
            output += chunker.update(String(text.prefix(length)))
        }
        output += chunker.update(text, final: true)
        XCTAssertEqual(output.count, 1)
        XCTAssertLessThanOrEqual(output.joined().count, 360)
        XCTAssertTrue(text.hasPrefix(output[0]))
    }
    func testShortAnswerWaitsForFinalThenSpeaksOnce() {
        var chunker = ReplySpeechChunker(economy: true)
        XCTAssertEqual(chunker.update("The answer is four."), [])
        XCTAssertEqual(chunker.update("The answer is four.", final: true), ["The answer is four."])
        XCTAssertEqual(chunker.update("The answer is four.", final: true), [])
    }
    func testEconomyCanBeginBeforeResponseFinishes() {
        var chunker = ReplySpeechChunker(economy: true)
        let first = String(repeating: "A useful explanation with enough detail. ", count: 4)
        XCTAssertEqual(chunker.update(first).count, 1)
        XCTAssertEqual(chunker.update(first + "More text follows.", final: true), [])
    }
    func testUnpunctuatedAnswersStayBounded() {
        var chunker = ReplySpeechChunker(economy: true)
        let result = chunker.update(String(repeating: "word ", count: 200))
        XCTAssertEqual(result.count, 1)
        XCTAssertLessThanOrEqual(result[0].count, 360)
    }
    func testTypedChatsDoNotGenerateUnrequestedSpeech() {
        XCTAssertFalse(SpeechReplyPolicy.shouldSpeak(floating: false, spoken: false, speakVoice: true, speakTyped: false))
        XCTAssertTrue(SpeechReplyPolicy.shouldSpeak(floating: false, spoken: true, speakVoice: true, speakTyped: false))
        XCTAssertFalse(SpeechReplyPolicy.shouldSpeak(floating: false, spoken: true, speakVoice: false, speakTyped: true))
        XCTAssertTrue(SpeechReplyPolicy.shouldSpeak(floating: false, spoken: false, speakVoice: false, speakTyped: true))
        XCTAssertTrue(SpeechReplyPolicy.shouldSpeak(floating: true, spoken: false, speakVoice: false, speakTyped: false))
    }
    func testHiddenActionsAndCodeAreNotReadInEconomyMode() {
        var chunker = ReplySpeechChunker(economy: true)
        XCTAssertEqual(chunker.update("```iris-actions\n{\"actions\":[]}", final: true), [])
    }
}
