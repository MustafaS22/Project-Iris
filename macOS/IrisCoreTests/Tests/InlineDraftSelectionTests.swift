import XCTest
import CoreFoundation
@testable import IrisCore

final class InlineDraftSelectionTests: XCTestCase {
    func testEmptyEditorWithoutCaretCanStillBeTargeted() {
        let capture = InlineDraftSelection.capture(original: "", range: nil, selected: nil)
        XCTAssertEqual(capture?.range.location, 0)
        XCTAssertEqual(capture?.range.length, 0)
        XCTAssertEqual(capture?.exposed, false)
    }
    func testMissingCaretNeverGuessesWhereToOverwriteNonemptyText() {
        XCTAssertNil(InlineDraftSelection.capture(original: "Existing draft", range: nil, selected: ""))
        XCTAssertNil(InlineDraftSelection.capture(original: nil, range: nil, selected: nil))
        XCTAssertNil(InlineDraftSelection.capture(original: "yes and yes", range: nil, selected: "yes"))
        XCTAssertNil(InlineDraftSelection.capture(original: "aaaa", range: nil, selected: "aaa"))
    }
    func testUniqueSelectedTextRecoversUnicodeUTF16Range() {
        let capture = InlineDraftSelection.capture(original: "🙂 hello world", range: nil, selected: "hello")
        XCTAssertEqual(capture?.range.location, 3)
        XCTAssertEqual(capture?.range.length, 5)
        XCTAssertEqual(capture?.exposed, false)
    }
    func testInvalidAndStaleRangesCannotBecomeFallbackInsertion() {
        for range in [CFRange(location: -1, length: 0), CFRange(location: 4, length: 0), CFRange(location: 2, length: 2), CFRange(location: Int.max, length: 1)] {
            XCTAssertNil(InlineDraftSelection.capture(original: "abc", range: range, selected: nil))
        }
        XCTAssertTrue(InlineDraftSelection.capture(original: "abc", range: CFRange(location: 3, length: 0), selected: nil)?.exposed == true)
    }
}
