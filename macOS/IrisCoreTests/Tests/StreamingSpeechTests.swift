import XCTest
import Foundation
@testable import IrisCore

final class StreamingSpeechTests: XCTestCase {
    func testStartsWithStableSentenceBeforeTheAnswerFinishes() {
        var chunker = ReplySpeechChunker()
        XCTAssertTrue(chunker.update("This is the first sentence").isEmpty)
        let first = chunker.update("This is the first sentence. Here is the next")
        XCTAssertEqual(first, ["This is the first sentence."])
        XCTAssertTrue(chunker.update("This is the first sentence. Here is the next").isEmpty)
        let rest = chunker.update("This is the first sentence. Here is the next sentence.", final: true)
        XCTAssertEqual(rest, ["Here is the next sentence."])
        XCTAssertTrue(chunker.update("This is the first sentence. Here is the next sentence.", final: true).isEmpty)
    }
    func testStreamingCodeAndTransportAreNeverReadAloud() {
        var chunker = ReplySpeechChunker()
        let prefix = "I can help with your request. "
        XCTAssertEqual(chunker.update(prefix + "Here is how"), ["I can help with your request."])
        let raw = prefix + "```iris-actions\n{\"actions\":[{\"type\":\"openApplication\",\"target\":\"Safari\"}]}\n```\n```swift\nprint(123)\n```\nReview the action when ready."
        let rest = chunker.update(raw, final: true).joined(separator: " ")
        XCTAssertFalse(rest.contains("openApplication")); XCTAssertFalse(rest.contains("print")); XCTAssertTrue(rest.contains("Review the action"))
    }
    func testReasoningAndIncompleteActionJSONAreHeld() {
        var chunker = ReplySpeechChunker()
        XCTAssertTrue(chunker.update("<think>Private internal reasoning. More thoughts.</think>{\"actions\":[").isEmpty)
        XCTAssertEqual(chunker.update("<think>Private internal reasoning. More thoughts.</think>A useful public answer is ready.", final: true), ["A useful public answer is ready."])
    }
    func testLongUnpunctuatedTextIsBoundedAndNeverRepeated() {
        var chunker = ReplySpeechChunker()
        let text = Array(repeating: "word", count: 600).joined(separator: " ")
        let chunks = chunker.update(text, final: true)
        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertLessThanOrEqual(chunks[0].count, 180)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 360 })
        XCTAssertLessThanOrEqual(chunker.committed.count, 2000)
        XCTAssertTrue(chunker.update(text, final: true).isEmpty)
    }
    func testSpeechRequestCountStaysBounded() {
        var chunker = ReplySpeechChunker()
        var text = "", output: [String] = []
        for i in 0..<80 {
            text += "This is sentence number \(i), with enough clear words to read aloud. "
            output += chunker.update(text)
        }
        output += chunker.update(text, final: true)
        XCTAssertLessThanOrEqual(output.count, 8)
        XCTAssertLessThanOrEqual(chunker.committed.count, 2000)
    }
    func testRewrittenCommittedTextDoesNotSpeakDuplicates() {
        var chunker = ReplySpeechChunker()
        _ = chunker.update("This is a stable opening sentence. Next")
        XCTAssertTrue(chunker.update("A different opening has replaced everything.", final: true).isEmpty)
        XCTAssertTrue(chunker.invalidated)
    }
    func testPCMDecoderHandlesLittleEndianAndSplitSamples() {
        var decoder = PCM16Stream()
        XCTAssertTrue(decoder.append(Data([0])).isEmpty)
        XCTAssertEqual(decoder.append(Data([0, 0xFF, 0x7F, 0x00, 0x80])), [0, Float(32767) / 32768, -1])
    }
    func testStrictAudioStreamParsingAndCompletion() throws {
        var parser = GeminiAudioStream()
        XCTAssertNil(try parser.consume("event: step.delta"))
        XCTAssertNil(try parser.consume(#"data: {"event_type":"step.delta","delta":{"type":"text","text":"not spoken"}}"#))
        let data = try parser.consume(#"data: {"event_type":"step.delta","delta":{"type":"audio","mime_type":"audio/l16","data":"AAAAAA=="}}"#)
        XCTAssertEqual(data, Data(repeating: 0, count: 4)); XCTAssertFalse(parser.completed)
        _ = try parser.consume(#"data: {"event_type":"interaction.completed","interaction":{"status":"completed"}}"#)
        XCTAssertTrue(parser.completed)
    }
    func testAudioStreamRejectsWrongFormatsErrorsAndIncompleteSamples() {
        var parser = GeminiAudioStream()
        XCTAssertThrowsError(try parser.consume(#"data: {"event_type":"step.delta","delta":{"type":"audio","mime_type":"audio/wav","data":"AAAAAA=="}}"#))
        XCTAssertThrowsError(try parser.consume(#"data: {"event_type":"error"}"#))
        XCTAssertThrowsError(try parser.consume(#"data: {"event_type":"interaction.completed","interaction":{"status":"completed"}}"#))
    }
    func testStreamingRequestUsesPCMAndStatelessGemini() throws {
        let request = try GeminiSpeechClient.streamRequest(text: "A short answer.", voice: "Sulafat", model: GeminiSpeechClient.defaultModel, style: "Natural", credential: .apiKey("fixture"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["stream"] as? Bool, true); XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual((body["response_format"] as? [String: Any])?["mime_type"] as? String, "audio/l16")
        XCTAssertEqual(GeminiSpeechClient.defaultModel, "gemini-3.8-flash-lite-tts")
    }
    @MainActor func testAudioCallbackArrivesBeforeHTTPResponseCompletes() async throws {
        DelayedSpeechProtocol.reset()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DelayedSpeechProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var callbacks = 0
        try await GeminiSpeechClient.stream(text: "A short answer.", voice: "Sulafat", model: GeminiSpeechClient.defaultModel, style: "Natural", credential: .apiKey("fixture"), session: session) { data in
            XCTAssertFalse(DelayedSpeechProtocol.sentCompletion)
            XCTAssertEqual(data.count, 4); callbacks += 1
        }
        XCTAssertEqual(callbacks, 1); XCTAssertTrue(DelayedSpeechProtocol.sentCompletion)
    }
}

private final class DelayedSpeechProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var completion = false
    static var sentCompletion: Bool { lock.withLock { completion } }
    static func reset() { lock.withLock { completion = false } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data((#"data: {"event_type":"step.delta","delta":{"type":"audio","mime_type":"audio/l16","data":"AAAAAA=="}}"# + "\n\n").utf8))
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [self] in
            Self.lock.withLock { Self.completion = true }
            client?.urlProtocol(self, didLoad: Data((#"data: {"event_type":"interaction.completed","interaction":{"status":"completed"}}"# + "\n\n").utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
