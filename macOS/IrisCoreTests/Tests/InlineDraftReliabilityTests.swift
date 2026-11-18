import XCTest
import AppKit
import ApplicationServices
import CoreFoundation
@testable import IrisCore

final class InlineDraftLifetimeTests: XCTestCase {
    func testOldDismissalCannotOwnNextInvocation() {
        var life = InlineDraftLifetime(); life.begin(); let first = life.id
        life.finish(); let oldDismissal = life.id
        life.begin()
        XCTAssertFalse(life.accepts(first)); XCTAssertFalse(life.accepts(oldDismissal))
        XCTAssertTrue(life.accepts(life.id)); XCTAssertTrue(life.mayAutoInsert)
    }
    func testReturningFromPromptDoesNotDismissItself() {
        var life = InlineDraftLifetime(); life.begin(); life.stage = .prompt
        XCTAssertEqual(life.activation(frontIsIris: false, frontIsTarget: true), .dismissPrompt)
        life.restoreForWriting()
        XCTAssertEqual(life.activation(frontIsIris: false, frontIsTarget: true), .keep)
        XCTAssertEqual(life.activation(frontIsIris: true, frontIsTarget: false), .keep)
        life.restoredFocus()
        XCTAssertEqual(life.activation(frontIsIris: false, frontIsTarget: true), .keep)
    }
    func testUserEditingDetachesInsertionWithoutInvalidatingDraft() {
        var life = InlineDraftLifetime(); life.begin(); life.stage = .writing; let id = life.id
        XCTAssertEqual(life.activation(frontIsIris: false, frontIsTarget: false), .previewOnly)
        life.detach()
        XCTAssertTrue(life.accepts(id)); XCTAssertFalse(life.mayAutoInsert)
        life.finish(); XCTAssertFalse(life.accepts(id))
    }
    func testInsertingIsNotTreatedAsUserEditing() {
        var life = InlineDraftLifetime(); life.begin(); life.stage = .inserting
        XCTAssertEqual(life.activation(frontIsIris: false, frontIsTarget: false), .keep)
    }
}
final class InlineDraftGestureTests: XCTestCase {
    func testFastAndSlowerDeliberateDoubleTaps() {
        for gap in [0.02, 0.1, 0.35, 0.49] {
            var g = InlineDraftGesture()
            XCTAssertFalse(g.update(down: true, at: 0)); XCTAssertFalse(g.update(down: false, at: 0.08))
            XCTAssertFalse(g.update(down: true, at: 0.08+gap)); XCTAssertTrue(g.update(down: false, at: 0.16+gap))
        }
    }
    func testDuplicateReleaseDoesNotEraseFirstTap() {
        var g = InlineDraftGesture()
        _ = g.update(down: true, at: 0); _ = g.update(down: false, at: 0.07)
        XCTAssertFalse(g.update(down: false, at: 0.08))
        _ = g.update(down: true, at: 0.2); XCTAssertTrue(g.update(down: false, at: 0.27))
    }
    func testShortcutHoldAndInterveningKeyResetDoNotTrigger() {
        var g = InlineDraftGesture()
        _ = g.update(down: true, at: 0); XCTAssertFalse(g.update(down: false, at: 1))
        _ = g.update(down: true, at: 1.1); XCTAssertFalse(g.update(down: false, at: 1.2))
        g.reset(); _ = g.update(down: true, at: 1.3); XCTAssertFalse(g.update(down: false, at: 1.4))
    }
    func testOnlyOneStructuralNewlineIsNormalized() {
        XCTAssertTrue(InlineDraftSelection.matchesInserted(expected: "Hello", actual: "Hello\n"))
        XCTAssertTrue(InlineDraftSelection.matchesInserted(expected: "Hi\nMira", actual: "Hi\r\nMira"))
        XCTAssertTrue(InlineDraftSelection.matchesInserted(expected: "café", actual: "cafe\u{301}"))
        XCTAssertFalse(InlineDraftSelection.matchesInserted(expected: "Hello", actual: "HelloHello"))
        XCTAssertFalse(InlineDraftSelection.matchesInserted(expected: "Hello", actual: "Wrong field Hello"))
        XCTAssertFalse(InlineDraftSelection.matchesInserted(expected: "Hello", actual: "Hello\n\n"))
    }
}

private final class InlineDraftProtocol: URLProtocol {
    static var response = ""
    static var requestBody: [String: Any]?
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "127.0.0.1" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var requestBytes = request.httpBody
        if requestBytes == nil, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var bytes = Data(), buffer = [UInt8](repeating: 0, count: 2048)
            while bytes.count < 100000 {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
            }
            requestBytes = bytes
        }
        if let bytes = requestBytes { Self.requestBody = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] }
        let bytes = try! JSONSerialization.data(withJSONObject: ["choices": [["message": ["content": Self.response]]]])
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
@MainActor final class InlineDraftModelReliabilityTests: XCTestCase {
    private func generate(_ response: String, original: String = "", at: Int = 0, instruction: String? = "Thank Maya for the notes", nearby: String = "Maya: Here are the notes.", knownContext: String = "", fieldLabel: String = "Message") async throws -> InlineWritingResult {
        InlineDraftProtocol.response = response; InlineDraftProtocol.requestBody = nil
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [InlineDraftProtocol.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        var preferences = Preferences(); preferences.source = .local; preferences.model = "offline-fixture"; preferences.server = "http://127.0.0.1:19999/v1"
        let target = InlineDraftTarget(app: .current, element: AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier), role: "AXTextArea", range: CFRange(location: at, length: 0), selectionExposed: true, original: original, selected: "", fieldLabel: fieldLabel, caret: .zero)
        return try await InlineDraftModel.generate(preferences: preferences, target: target, instruction: instruction, nearby: nearby, knownContext: knownContext, session: session)
    }
    func testDraftSurvivesReasoningEnvelopeAndGetsEnoughOutputBudget() async throws {
        let value = try await generate("<think>private reasoning</think>\n{\"kind\":\"draft\",\"text\":\"Thanks for the notes, Maya!\"}")
        XCTAssertEqual(value, .draft("Thanks for the notes, Maya!"))
        XCTAssertEqual(InlineDraftProtocol.requestBody?["max_tokens"] as? Int, 1400)
    }
    func testClarificationIsNeverInsertedAsDraft() async throws {
        let value = try await generate("{\"kind\":\"question\",\"text\":\"What time are you available?\"}")
        XCTAssertEqual(value, .question("What time are you available?"))
    }
    func testTruncatedDraftProducesRealFailureInsteadOfGenericQuestion() async {
        do { _ = try await generate("{\"kind\":\"draft\",\"text\":\"incomplete"); XCTFail("Invalid draft accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("incomplete or invalid")) }
    }
    func testParagraphsAndUnicodeAreKept() async throws {
        let result = try await generate("```json\n{\"kind\":\"draft\",\"text\":\"Hi Maya,\\n\\nشكرًا!\\nMira\"}\n```", original: "Existing text")
        XCTAssertEqual(result, .draft("Hi Maya,\n\nشكرًا!\nMira"))
    }

    func testEmptyMessageUsesVisibleThreadInsteadOfPolishingNothing() async throws {
        let result = try await generate("{\"kind\":\"draft\",\"text\":\"Thanks for the notes, Maya!\"}", instruction: nil, nearby: "Visible nearby text:\nMaya: Here are the notes from class.")
        XCTAssertEqual(result, .draft("Thanks for the notes, Maya!"))
        let messages = InlineDraftProtocol.requestBody?["messages"] as? [[String: Any]]
        let body = messages?.description ?? ""
        XCTAssertTrue(body.contains("EMPTY FIELD")); XCTAssertTrue(body.contains("notes from class"))
        XCTAssertFalse(body.contains("Polish the selected text"))
    }
    func testEmptySurveyGetsQuestionAndAttributedKnownFacts() async throws {
        let facts = "User-entered interests: Cycling and photography.\nUser's saved note: I work as a software developer."
        let result = try await generate("{\"kind\":\"draft\",\"text\":\"I enjoy cycling and photography.\"}", instruction: nil, nearby: "Visible nearby text:\nWhat do you enjoy doing outside work?", knownContext: facts, fieldLabel: "Your answer")
        XCTAssertEqual(result, .draft("I enjoy cycling and photography."))
        let body = (InlineDraftProtocol.requestBody?["messages"] as? [[String: Any]])?.description ?? ""
        XCTAssertTrue(body.contains("Known user facts")); XCTAssertTrue(body.contains("Cycling and photography")); XCTAssertTrue(body.contains("outside work"))
    }
    func testZeroWidthEmptyEditorStillUsesEmptyFieldIntent() async throws {
        _ = try await generate("{\"kind\":\"draft\",\"text\":\"Thank you!\"}", original: "\u{200B}", at: 1, instruction: nil)
        let body = (InlineDraftProtocol.requestBody?["messages"] as? [[String: Any]])?.description ?? ""
        XCTAssertTrue(body.contains("EMPTY FIELD")); XCTAssertFalse(body.contains("Continue the existing draft"))
        XCTAssertTrue(InlineDraftSelection.matchesInserted(expected: "\u{200B}Thank you!", actual: "Thank you!"))
    }
    func testSavedFactsAreNotAddedToAnExistingDraft() async throws {
        _ = try await generate("{\"kind\":\"draft\",\"text\":\"new words\"}", original: "Hello", at: 5, instruction: nil, knownContext: "UNRELATED_PERSONAL_FACT")
        let body = (InlineDraftProtocol.requestBody?["messages"] as? [[String: Any]])?.description ?? ""
        XCTAssertFalse(body.contains("UNRELATED_PERSONAL_FACT")); XCTAssertTrue(body.contains("Continue the existing draft"))
    }
}
