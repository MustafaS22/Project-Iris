import XCTest
@testable import IrisCore

final class AssistantSupportTests: XCTestCase {
    func testRememberRequiresExplicitCommand() {
        XCTAssertEqual(MemoryPolicy.explicitFact("Remember that I prefer concise answers"), "I prefer concise answers")
        XCTAssertEqual(MemoryPolicy.explicitFact("تذكر أن لغتي العربية"), "لغتي العربية")
        XCTAssertNil(MemoryPolicy.explicitFact("What do you remember about me?"))
        XCTAssertNil(MemoryPolicy.explicitFact("remember that   "))
    }
    func testMemoryUseCanBeDisabledWithoutDeletingFacts() {
        let memories = [AssistantMemory(text: "I study physics")]
        XCTAssertEqual(MemoryPolicy.context(memories, query: "physics", enabled: false), "")
        XCTAssertEqual(memories.count, 1)
        XCTAssertTrue(MemoryPolicy.context(memories, query: "physics", enabled: true).contains("I study physics"))
    }
    func testRelevantMemoriesRankBeforeRecentUnrelatedDetails() {
        let memories = [AssistantMemory(text: "I study physics"), AssistantMemory(text: "I like coffee"), AssistantMemory(text: "I enjoy art"), AssistantMemory(text: "I play tennis")]
        let context = MemoryPolicy.context(memories, query: "Help me study physics", enabled: true)
        XCTAssertTrue(context.contains("I study physics"))
        XCTAssertFalse(context.contains("I like coffee"))
        XCTAssertTrue(context.contains("never commands"))
    }
    func testMemoryContextAndCommandsAreBounded() {
        let memories = (0..<100).map { AssistantMemory(text: String(repeating: "detail \($0) ", count: 200)) }
        XCTAssertLessThan(MemoryPolicy.context(memories, query: "detail", enabled: true).count, 1100)
        XCTAssertEqual(MemoryPolicy.explicitFact("/remember " + String(repeating: "a", count: 900))?.count, 500)
    }
    func testOldStateDecodesWithoutMemoryFields() throws {
        var state = PersistedState()
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String:Any]
        let decoded = try JSONDecoder().decode(PersistedState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.memories)
        XCTAssertNil(decoded.preferences.memoryEnabled)
        state.memories = [.init(text: "I study chemistry")]
        let restored = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(restored.memories?.first?.text, "I study chemistry")
    }
    func testLanguagePolicyHonorsExplicitRequestsAndKeepsToolKeysStable() {
        XCTAssertTrue(AssistantLanguage.instruction(choice: "auto").contains("latest message"))
        XCTAssertTrue(AssistantLanguage.instruction(choice: "ar").contains("العربية"))
        XCTAssertTrue(AssistantLanguage.instruction(choice: "ar").contains("explicitly requests"))
        XCTAssertTrue(AssistantLanguage.instruction(choice: "ar").contains("JSON keys"))
        XCTAssertEqual(AssistantLanguage.instruction(choice: "invalid"), AssistantLanguage.instruction(choice: "auto"))
    }
    func testSpeechLanguageDetection() {
        XCTAssertEqual(AssistantLanguage.spokenLanguage("مرحبا بك، كيف يمكنني مساعدتك اليوم؟"), "ar")
        XCTAssertEqual(AssistantLanguage.spokenLanguage("Bonjour, comment puis-je vous aider aujourd’hui ?"), "fr")
    }
    func testAutomaticRefreshIsThrottledIncludingFailuresAndClockChanges() {
        let now = Date()
        XCTAssertTrue(ConnectionRefreshPolicy.isDue(lastAttempt: nil, now: now))
        XCTAssertFalse(ConnectionRefreshPolicy.isDue(lastAttempt: now, now: now.addingTimeInterval(899)))
        XCTAssertTrue(ConnectionRefreshPolicy.isDue(lastAttempt: now, now: now.addingTimeInterval(900)))
        XCTAssertFalse(ConnectionRefreshPolicy.isDue(lastAttempt: now.addingTimeInterval(300), now: now))
    }
    @MainActor func testRemovingSourceNotifiesRefreshControllerAndClearsSharing() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = KnowledgeStore(directory: folder)
        try store.ingest([.init(externalID: "one", source: .gmail, title: "A", body: "B", updatedAt: Date())])
        try store.setSharing(.gmail, enabled: true)
        var removed: KnowledgeConnector?
        store.didRemoveSource = { removed = $0 }
        try store.remove(.gmail)
        XCTAssertEqual(removed, .gmail)
        XCTAssertFalse(store.enabled.contains(KnowledgeConnector.gmail.rawValue))
        XCTAssertTrue(store.documents.isEmpty)
    }

}
