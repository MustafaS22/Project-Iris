import XCTest
import CoreGraphics
@testable import IrisCore

final class InlinePersonalContextTests: XCTestCase {
    func testOnlyExplicitPersonalFactsAreSelected() {
        var prefs = Preferences(); prefs.name = "Mira"; prefs.onboarded = true; prefs.role = .developer; prefs.interests = "Photography"
        let text = InlinePersonalContext.context(preferences: prefs,
            notes: ["I like hiking.", "Maya likes swimming.", "I am trying to write a message.", "I am storing my password here.", "My hobbies are painting and cycling."],
            statements: ["Please write a biography", "I work as a software developer.", "Imagine I am a doctor", "I like hiking."], query: "What are your hobbies?")
        XCTAssertTrue(text.contains("Saved user name: Mira")); XCTAssertTrue(text.contains("User-selected role: Developer"))
        XCTAssertTrue(text.contains("hiking")); XCTAssertTrue(text.contains("cycling")); XCTAssertTrue(text.contains("software developer"))
        XCTAssertFalse(text.contains("Maya")); XCTAssertFalse(text.contains("password")); XCTAssertFalse(text.contains("doctor")); XCTAssertFalse(text.contains("trying"))
        XCTAssertEqual(text.components(separatedBy: "I like hiking.").count, 2)
    }
    func testNoFabricatedDefaultRoleOrUnlimitedMemory() {
        let prefs = Preferences()
        let text = InlinePersonalContext.context(preferences: prefs, notes: Array(repeating: "I like " + String(repeating: "x", count: 600), count: 1000), statements: [], query: "hobbies")
        XCTAssertFalse(text.contains("Student")); XCTAssertLessThanOrEqual(text.count, 1800)
        XCTAssertFalse(InlinePersonalContext.isPersonalFact("My bank account is 1234"))
        XCTAssertFalse(InlinePersonalContext.isPersonalFact("I am quoting \"I like running\""))
    }
    func testUnrelatedConversationDoesNotPullPersonalHistory() {
        let context = InlinePersonalContext.context(preferences: Preferences(), notes: ["I enjoy hiking in the mountains."], statements: ["I work as a musician."], query: "Maya: Here are the class notes. Message")
        XCTAssertFalse(context.contains("mountains")); XCTAssertFalse(context.contains("musician"))
    }
    func testVisualFallbackIsReservedForMissingNearbyText() {
        XCTAssertTrue(InlinePersonalContext.needsVisualText("Window: Messages"))
        XCTAssertTrue(InlinePersonalContext.needsVisualText("Window: Survey\nVisible nearby text:\nNext"))
        XCTAssertFalse(InlinePersonalContext.needsVisualText("Window: Messages\nVisible nearby text:\nMaya: Here are the class notes I promised yesterday."))
    }
    func testScreenRegionStaysInsideVisibleContentAndExcludesToolbar() {
        let window = CGRect(x: 100, y: 50, width: 1200, height: 900)
        let content = CGRect(x: 100, y: 190, width: 1200, height: 760)
        let region = InlineScreenContext.region(window: window, content: content, caret: CGPoint(x: 500, y: 500))
        XCTAssertTrue(content.contains(region)); XCTAssertGreaterThanOrEqual(region.minY, 190)
        let fallback = InlineScreenContext.region(window: window, content: nil, caret: CGPoint(x: 300, y: 200))
        XCTAssertTrue(window.contains(fallback)); XCTAssertGreaterThanOrEqual(fallback.minY, window.minY+95)
    }
    func testPlaceholderIsNotTreatedAsAnExistingDraft() {
        XCTAssertEqual(InlineDraftSelection.exposedText(value: "Your answer", placeholder: "Your answer", characterCount: 0), "")
        XCTAssertEqual(InlineDraftSelection.exposedText(value: nil, placeholder: "Message", characterCount: 0), "")
        XCTAssertEqual(InlineDraftSelection.exposedText(value: "Your answer", placeholder: "Your answer", characterCount: 11), "Your answer")
        XCTAssertEqual(InlineDraftSelection.exposedText(value: "Your answer", placeholder: "Your answer", characterCount: nil), "Your answer")
        XCTAssertNil(InlineDraftSelection.exposedText(value: nil, placeholder: "Message", characterCount: nil))
        XCTAssertNil(InlineDraftSelection.exposedText(value: "", placeholder: nil, characterCount: 20))
    }
    func testSurveyQuestionLabelsCanUseLocalSavedValues() {
        XCTAssertEqual(InlineWriting.profileValue(field: "What is your name?", name: "Mira Shah"), "Mira Shah")
        XCTAssertEqual(InlineWriting.profileValue(field: "E-mail address", name: "Mira", email: "mira@example.com"), "mira@example.com")
        XCTAssertNil(InlineWriting.profileValue(field: "Your manager's name", name: "Mira"))
        XCTAssertTrue(InlineWriting.isEmptyField(" \u{200B}\u{FEFF}\n")); XCTAssertFalse(InlineWriting.isEmptyField("My draft"))
    }
}
