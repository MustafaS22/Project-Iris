import XCTest
@testable import IrisCore

final class ConversationStudioTests: XCTestCase {
    func testOldStateStillDecodesWithoutNewHistoryFields() throws {
        var state = PersistedState()
        state.notes = [.init(text: "Keep this")]
        let data = try JSONEncoder().encode(state)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "conversations"); json.removeValue(forKey: "activeConversationID"); json.removeValue(forKey: "studyCards")
        let decoded = try JSONDecoder().decode(PersistedState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.conversations)
        XCTAssertEqual(decoded.notes.first?.text, "Keep this")
    }
    func testConversationAndDeckSurviveSave() throws {
        var state = PersistedState()
        let conversation = ChatConversation(messages: [.init(role: "user", text: "My first question"), .init(role: "assistant", text: "An answer")])
        state.conversations = [conversation]; state.activeConversationID = conversation.id
        state.studyCards = StudioTools.cards(from: "Q | A")
        let decoded = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(decoded.activeConversationID, conversation.id)
        XCTAssertEqual(decoded.conversations?.first?.title, "My first question")
        XCTAssertEqual(decoded.conversations?.first?.messages.count, 2)
        XCTAssertEqual(decoded.studyCards?.first?.answer, "A")
    }
    func testCardsSkipMalformedRowsAndKeepAnswerPipes() {
        let cards = StudioTools.cards(from: "Question | Answer | detail\ninvalid\n | missing\nNext | Yes")
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(cards[0].answer, "Answer | detail")
    }
    func testJSONFormattingPreservesValuesAndRejectsInvalidInput() throws {
        let formatted = try StudioTools.formatJSON("{\"z\":[1,true],\"a\":\"https://example.com\"}")
        XCTAssertTrue(formatted.contains("https://example.com"))
        XCTAssertEqual(try StudioTools.formatJSON("42"), "42")
        XCTAssertThrowsError(try StudioTools.formatJSON("{bad}"))
    }
}
