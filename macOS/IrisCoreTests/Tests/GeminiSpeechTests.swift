import XCTest
import Foundation
@testable import IrisCore

final class GeminiSpeechTests: XCTestCase {
    private var session: URLSession!
    override func setUp() { let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureProtocol.self]; session = URLSession(configuration: configuration) }
    override func tearDown() { session.invalidateAndCancel(); FixtureProtocol.handler = nil }
    func testRequestUsesGeminiSpeechNotChatAndDisablesStorage() throws {
        let request = try GeminiSpeechClient.request(text: "Hello **Mustafa**.", voice: "Sulafat", model: GeminiSpeechClient.defaultModel, style: "Warm", credential: .apiKey("fixture-key"))
        XCTAssertEqual(request.url?.absoluteString, "https://generativelanguage.googleapis.com/v1beta/interactions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-api-key"), "fixture-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["store"] as? Bool, false)
        XCTAssertEqual(body["model"] as? String, GeminiSpeechClient.defaultModel)
        XCTAssertNil(body["tools"])
        let input = try XCTUnwrap(body["input"] as? [[String: Any]])
        let parts = try XCTUnwrap(input[0]["content"] as? [[String: Any]])
        XCTAssertEqual(parts[0]["text"] as? String, "Hello Mustafa.")
        let annotations = try XCTUnwrap(parts[0]["annotations"] as? [[String: String]])
        XCTAssertEqual(annotations[0]["type"], "speech_metadata")
        XCTAssertTrue(annotations[0]["style"]?.contains("Warm") == true)
        let format = try XCTUnwrap(body["response_format"] as? [String: String])
        XCTAssertEqual(format["mime_type"], "audio/wav")
    }
    func testQuotaErrorHasDefaultCooldownWithoutRetrying() async throws {
        var requests = 0
        FixtureProtocol.handler = { request in
            requests += 1
            return (429, Data())
        }
        do {
            _ = try await GeminiSpeechClient.audio(text: "Hello", voice: "Sulafat", model: GeminiSpeechClient.defaultModel, style: "Natural", credential: .apiKey("fixture-key"), session: session)
            XCTFail("Expected a quota cooldown")
        } catch let error as GeminiSpeechQuotaError {
            XCTAssertEqual(error.retryAfter, 60)
        }
        XCTAssertEqual(requests, 1)
    }
    func testAccountAuthorizationStaysSeparateFromAPIKey() throws {
        let request = try GeminiSpeechClient.request(text: "Hello", voice: "Kore", model: GeminiSpeechClient.defaultModel, style: "Natural", credential: .bearer("fixture-token", project: "fixture-project"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "x-goog-user-project"), "fixture-project")
        XCTAssertNil(request.value(forHTTPHeaderField: "x-goog-api-key"))
    }
    func testUnsupportedSettingsAndMissingCredentialsFailBeforeSending() {
        XCTAssertThrowsError(try GeminiSpeechClient.request(text: "Hi", voice: "Unknown", model: GeminiSpeechClient.defaultModel, style: "Natural", credential: .apiKey("key")))
        XCTAssertThrowsError(try GeminiSpeechClient.request(text: "Hi", voice: "Kore", model: "chat-model", style: "Natural", credential: .apiKey("key")))
        XCTAssertThrowsError(try GeminiSpeechClient.request(text: "Hi", voice: "Kore", model: GeminiSpeechClient.defaultModel, style: "Unknown", credential: .apiKey("key")))
        XCTAssertThrowsError(try GeminiSpeechClient.request(text: "Hi", voice: "Kore", model: GeminiSpeechClient.defaultModel, style: "Natural", credential: .apiKey("")))
    }
    func testThirtyDistinctVoicesAndExpressiveDefault() {
        XCTAssertEqual(GeminiSpeechClient.voices.count, 30)
        XCTAssertEqual(Set(GeminiSpeechClient.voices.map(\.id)).count, 30)
        XCTAssertTrue(GeminiSpeechClient.voices.contains { $0.name == GeminiSpeechClient.defaultVoice && $0.tone == "Warm" })
    }
    func testDecodesOnlyCompletedModelAudio() throws {
        let bytes = Self.wav()
        let data = try Self.response(audio: bytes)
        XCTAssertEqual(try GeminiSpeechClient.decode(data), bytes)
        for status in ["incomplete", "failed", "in_progress"] { XCTAssertThrowsError(try GeminiSpeechClient.decode(Self.response(audio: bytes, status: status))) }
        XCTAssertThrowsError(try GeminiSpeechClient.decode(Self.response(audio: Data("not WAV".utf8))))
        XCTAssertThrowsError(try GeminiSpeechClient.decode(Self.response(audio: bytes, mime: "audio/l16")))
        let injected = try JSONSerialization.data(withJSONObject: ["status": "completed", "steps": [["type": "user_input", "content": [["type": "audio", "mime_type": "audio/wav", "data": bytes.base64EncodedString()]]]]])
        XCTAssertThrowsError(try GeminiSpeechClient.decode(injected))
    }
    func testRealClientReturnsAudioWithoutPlayingIt() async throws {
        let bytes = Self.wav()
        FixtureProtocol.handler = { _ in (200, try Self.response(audio: bytes)) }
        let output = try await GeminiSpeechClient.audio(text: "Hello", voice: "Sulafat", model: GeminiSpeechClient.defaultModel, style: "Natural", credential: .apiKey("fixture-key"), session: session)
        XCTAssertEqual(output, bytes)
    }
    func testQuotaFailureIsActionableAndNotRetried() async {
        var requests = 0
        FixtureProtocol.handler = { _ in requests += 1; return (429, Data()) }
        do { _ = try await GeminiSpeechClient.audio(text: "Hello", voice: "Sulafat", model: GeminiSpeechClient.defaultModel, style: "Natural", credential: .apiKey("fixture-key"), session: session); XCTFail("Expected quota error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("quota")) }
        XCTAssertEqual(requests, 1)
    }
    func testCancellationDoesNotReturnAudio() async {
        FixtureProtocol.handler = { _ in (200, try Self.response(audio: Self.wav())) }
        let task = Task { try await GeminiSpeechClient.audio(text: "Hello", voice: "Sulafat", model: GeminiSpeechClient.defaultModel, style: "Natural", credential: .apiKey("fixture-key"), session: session) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { }
    }
    private static func response(audio: Data, status: String = "completed", mime: String = "audio/wav") throws -> Data {
        try JSONSerialization.data(withJSONObject: ["status": status, "steps": [["type": "model_output", "content": [["type": "audio", "mime_type": mime, "data": audio.base64EncodedString()]]]]])
    }
    private static func wav() -> Data {
        var data = Data()
        func string(_ value: String) { data.append(Data(value.utf8)) }
        func u16(_ value: UInt16) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var value = value.littleEndian; withUnsafeBytes(of: &value) { data.append(contentsOf: $0) } }
        string("RIFF"); u32(36 + 4800); string("WAVEfmt "); u32(16); u16(1); u16(1); u32(24000); u32(48000); u16(2); u16(16); string("data"); u32(4800); data.append(Data(repeating: 0, count: 4800))
        return data
    }
}
