import XCTest
import Foundation
import AVFoundation
@testable import IrisCore

final class VoiceBoxTests: XCTestCase {
    private var session: URLSession!
    override func setUp() { let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureProtocol.self]; session = URLSession(configuration: configuration) }
    override func tearDown() { session.invalidateAndCancel(); FixtureProtocol.handler = nil }
    func testOnlyLoopbackServersAreAccepted() throws {
        for server in ["http://127.0.0.1:17493", "http://localhost:17493/", "http://[::1]:17493"] { XCTAssertNoThrow(try VoiceBoxClient.baseURL(server)) }
        for server in ["https://voicebox.sh", "http://192.168.1.5:17493", "http://localhost.attacker.test", "file:///tmp/voice", "http://user:pass@localhost:17493", "http://localhost:17493/path", "http://localhost:17493?url=x"] { XCTAssertThrowsError(try VoiceBoxClient.baseURL(server)) }
    }
    func testLoadsAndSortsProfilesFromLocalServer() async throws {
        FixtureProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:17493/profiles")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, Data(#"[{"id":"2","name":"Zara","language":"en","description":null},{"id":"1","name":"Alex","language":"en","description":"Warm voice"}]"#.utf8))
        }
        let profiles = try await VoiceBoxClient.profiles(server: VoiceBoxClient.defaultServer, session: session)
        XCTAssertEqual(profiles.map(\.name), ["Alex", "Zara"])
    }
    func testRequestUsesLocalVoiceProfileAndPreservesExactWords() throws {
        let request = try VoiceBoxClient.request(server: VoiceBoxClient.defaultServer, profile: "voice-id", text: "Hello **Mustafa**.\n```iris-actions\n{\"actions\":[]}\n```", speed: 50)
        XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:17493/v1/audio/speech")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "tts-1")
        XCTAssertEqual(body["voice"] as? String, "voice-id")
        XCTAssertEqual(body["response_format"] as? String, "wav")
        XCTAssertEqual(body["speed"] as? Double, 1.4)
        XCTAssertEqual(body["input"] as? String, "Hello Mustafa.")
        XCTAssertNil(body["personality"])
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertThrowsError(try VoiceBoxClient.request(server: VoiceBoxClient.defaultServer, profile: "", text: "Hello", speed: 1))
    }
    func testSpeechSkipsCodeAndLimitsLongReplies() {
        XCTAssertEqual(VoiceBoxClient.speechText("# Welcome\nUse [this link](https://example.com).\n```swift\nprint(123)\n```"), "Welcome\nUse this link.")
        XCTAssertEqual(VoiceBoxClient.speechText(String(repeating: "a", count: 3000)).count, 2000)
    }
    func testRealWAVResponseCanBeDecodedForPlayback() async throws {
        let wav = Self.wav()
        FixtureProtocol.handler = { _ in (200, wav) }
        let data = try await VoiceBoxClient.audio(server: VoiceBoxClient.defaultServer, profile: "voice-id", text: "Hi", speed: 1, session: session)
        XCTAssertEqual(data, wav)
        let player = try AVAudioPlayer(data: data)
        XCTAssertGreaterThan(player.duration, 0)
    }
    func testBadResponsesNeverBecomePlaybackData() async throws {
        for status in [200, 400, 404, 500] {
            FixtureProtocol.handler = { _ in (status, Data("not audio".utf8)) }
            do { _ = try await VoiceBoxClient.audio(server: VoiceBoxClient.defaultServer, profile: "id", text: "Hi", speed: 1, session: session); XCTFail("Expected error for \(status)") }
            catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
    }
    func testOfflineServerGivesSetupInstructions() async {
        FixtureProtocol.handler = { _ in throw URLError(.cannotConnectToHost) }
        do { _ = try await VoiceBoxClient.profiles(server: VoiceBoxClient.defaultServer, session: session); XCTFail("Expected offline error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Open VoiceBox")) }
    }
    func testCancelledTaskDoesNotReturnAudio() async throws {
        FixtureProtocol.handler = { _ in (200, Self.wav()) }
        let task = Task { try await VoiceBoxClient.audio(server: VoiceBoxClient.defaultServer, profile: "id", text: "Hi", speed: 1, session: session) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") } catch { }
    }
    func testLegacyServerUsesAudioOnlyWithoutHistoryOrAutoplay() async throws {
        var generations=0
        FixtureProtocol.handler={request in
            switch request.url!.path {
            case "/v1/audio/speech":return(404,Data())
            case "/openapi.json":return(200,Data(#"{"paths":{"/generate/stream":{}}}"#.utf8))
            case "/profiles":return(200,Data(#"[{"id":"voice-id","name":"Alex","language":"en","default_engine":"kokoro"}]"#.utf8))
            case "/generate/stream":generations += 1;return(200,Self.wav())
            default:XCTFail("Must never call the auto-play /generate or history routes");return(500,Data())
            }
        }
        let data=try await VoiceBoxClient.audio(server:VoiceBoxClient.defaultServer,profile:"voice-id",text:"Hello",speed:1,session:session)
        XCTAssertEqual(data,Self.wav());XCTAssertEqual(generations,1)
    }
    func testLocalTranscriptionStaysOnLoopbackAndDoesNotRetryModelDownload() async throws {
        let request=try VoiceBoxClient.transcriptionRequest(server:VoiceBoxClient.defaultServer,audio:Data([1,2,3]),language:"en")
        XCTAssertEqual(request.url?.path,"/transcribe");XCTAssertTrue(request.value(forHTTPHeaderField:"Content-Type")!.contains("multipart/form-data"))
        XCTAssertTrue(String(data:request.httpBody!,encoding:.utf8)!.contains("question.m4a"))
        XCTAssertThrowsError(try VoiceBoxClient.transcriptionRequest(server:"https://example.com",audio:Data([1])))
        var calls=0;FixtureProtocol.handler={_ in calls += 1;return(202,Data())}
        do{_=try await VoiceBoxClient.transcribe(server:VoiceBoxClient.defaultServer,audio:Data([1]),session:session);XCTFail("Should surface model download")}catch{XCTAssertTrue(error.localizedDescription.contains("preparing"))}
        XCTAssertEqual(calls,1)
    }
    func testMissingModernProfileNeverStartsLegacyGeneration() async throws {
        FixtureProtocol.handler = { request in
            switch request.url!.path {
            case "/v1/audio/speech": return (404, Data(#"{"detail":"Profile not found"}"#.utf8))
            case "/openapi.json": return (200, Data(#"{"paths":{"/v1/audio/speech":{},"/generate":{}}}"#.utf8))
            default: XCTFail("Must not generate twice"); return (500, Data())
            }
        }
        do { _ = try await VoiceBoxClient.audio(server: VoiceBoxClient.defaultServer, profile: "missing", text: "Hello", speed: 1, session: session); XCTFail("Expected missing profile error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Refresh voices")) }
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
