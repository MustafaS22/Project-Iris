import XCTest
@testable import IrisCore

final class InlineWritingTests: XCTestCase {
    func testKnownNameCanFillOnlyUnambiguousOwnNameField() {
        XCTAssertEqual(InlineWriting.profileValue(field: "Full name *", name: " Mira Shah "), "Mira Shah")
        for field in ["Recipient name", "Company name", "Email", "Phone", "Last name", "Username", "Search names"] {
            XCTAssertNil(InlineWriting.profileValue(field: field, name: "Mira Shah"))
        }
        XCTAssertNil(InlineWriting.profileValue(field: "Name", name: " "))
    }

    func testOtherProfileDetailsRequireExplicitSavedValuesAndMatchingLabels() {
        XCTAssertEqual(InlineWriting.profileValue(field: "Your email", name: "Mira", email: "mira@example.com"), "mira@example.com")
        XCTAssertEqual(InlineWriting.profileValue(field: "Phone number", name: "Mira", phone: "5550100"), "5550100")
        XCTAssertEqual(InlineWriting.profileValue(field: "Mailing address", name: "Mira", address: "12 Example Road"), "12 Example Road")
        XCTAssertNil(InlineWriting.profileValue(field: "To", name: "Mira", email: "mira@example.com"))
        XCTAssertNil(InlineWriting.profileValue(field: "Password", name: "Mira", email: "mira@example.com"))
    }

    func testClarificationIsNotInsertedAsDraft() {
        XCTAssertEqual(InlineWriting.parse(#"{"kind":"question","text":"Are you available on Tuesday?"}"#),
                       .question("Are you available on Tuesday?"))
    }

    func testEmailParagraphsAndMessageLanguageSurviveTransport() {
        XCTAssertEqual(InlineWriting.parse(#"{"kind":"draft","text":"Hi Maya,\n\nThanks for sharing the notes.\n\nMira"}"#),
                       .draft("Hi Maya,\n\nThanks for sharing the notes.\n\nMira"))
        XCTAssertEqual(InlineWriting.parse("```json\n{\"kind\":\"draft\",\"text\":\"شكرًا!\"}\n```"), .draft("شكرًا!"))
    }

    func testMalformedOrEmptyModelPayloadNeverBecomesFieldText() {
        for reply in ["IRIS_NEEDS_DIRECTION", "Here is your draft:", "{\"actions\":[]}",
                      "{\"kind\":\"draft\",\"text\":\" \"}", "{\"kind\":\"send\",\"text\":\"Hello\"}"] {
            XCTAssertEqual(InlineWriting.parse(reply), .question(InlineWriting.direction))
        }
        let long = String(repeating: "a", count: 4_801)
        XCTAssertEqual(InlineWriting.parse("{\"kind\":\"draft\",\"text\":\"\(long)\"}"), .question(InlineWriting.direction))
    }
}
