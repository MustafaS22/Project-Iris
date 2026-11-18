import XCTest
@testable import IrisCore

final class ChatMentionsTests: XCTestCase {
    func testCreationAndMultipleSourcesAreExplicit() throws {
        let request = try ChatMentions.parse("@gmail @notes @website Build a page for the retreat")
        XCTAssertEqual(request.creation, .website)
        XCTAssertEqual(request.connectors, [.gmail, .appleNotes])
        XCTAssertEqual(request.text, "Build a page for the retreat")
    }
    func testLiteralEmailCodeAndUnknownHandlesDoNotBecomeTools() throws {
        for value in ["Email me@example.com", "`@image` is an example", "```swift\n@website\n```", "\\@image", "https://host/@website", "@gmail.com", "@someone hello"] {
            let request = try ChatMentions.parse(value)
            XCTAssertTrue(request.tokens.isEmpty, value)
            XCTAssertEqual(request.text, value)
        }
    }
    func testOneToolWithSourcesAndAliases() throws {
        XCTAssertEqual(try ChatMentions.parse("@pdf @drive write a guide").creation, .document)
        XCTAssertEqual(try ChatMentions.parse("@flashcards @files biology").skill, .flashcards)
        XCTAssertThrowsError(try ChatMentions.parse("@website @image a page"))
        XCTAssertThrowsError(try ChatMentions.parse("@summary @document a guide"))
        XCTAssertEqual(try ChatMentions.parse("@image @image a tree").creation, .image)
    }
    func testCompletionPreservesPromptAndDoesNotTriggerInEmailOrCode() {
        XCTAssertEqual(ChatMentions.query(in: "Use @goo"), "goo")
        XCTAssertEqual(ChatMentions.completing("googlechat", in: "Use @goo"), "Use @googlechat ")
        XCTAssertNil(ChatMentions.query(in: "test@gma"))
        XCTAssertNil(ChatMentions.query(in: "`@ima"))
        XCTAssertNil(ChatMentions.query(in: "```\n@ima"))
    }
    func testHighlightRangesUseUTF16AndRespectLiteralText() {
        let text = "🙂 @gmail and @pdf, test@gmail.com `@image` @unknown https://x/@website"
        let ranges = ChatMentions.highlightedRanges(in: text)
        XCTAssertEqual(ranges.map { (text as NSString).substring(with: $0) }, ["@gmail", "@pdf"])
        XCTAssertEqual(ranges.first?.location, 3)
        XCTAssertTrue(ChatMentions.highlightedRanges(in: "```\n@gmail\n``` @gmail.com").isEmpty)
        XCTAssertEqual(ChatMentions.highlightedRanges(in: "@website @image").count, 2)
    }
    @MainActor func testSourceMentionCannotLeakOtherEnabledOrDisabledData() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KnowledgeStore(directory: directory)
        try store.ingest([
            .init(externalID: "mail", source: .gmail, title: "Retreat", body: "Mail-only details", updatedAt: Date()),
            .init(externalID: "private", source: .appleNotes, title: "Retreat", body: "Private notes details", updatedAt: Date()),
            .init(externalID: "file", source: .files, title: "Retreat", body: "Other enabled source", updatedAt: Date())])
        try store.setSharing(.gmail, enabled: true); try store.setSharing(.files, enabled: true)
        let gmail = store.context(for: "retreat", only: [.gmail])
        XCTAssertTrue(gmail.contains("Mail-only details"))
        XCTAssertFalse(gmail.contains("Other enabled source")); XCTAssertFalse(gmail.contains("Private notes details"))
        XCTAssertTrue(store.context(for: "retreat", only: [.appleNotes]).isEmpty)
        XCTAssertTrue(store.context(for: "recent messages", only: [.gmail]).contains("Mail-only details"))
    }
}

final class ChatCreationFilesTests: XCTestCase {
    func testGeneratedNamesCannotBecomePaths() {
        let path = ChatCreationFiles.filename(prompt: "../../a site / private: secrets", kind: .website)
        XCTAssertFalse(path.contains("/")); XCTAssertFalse(path.contains("..")); XCTAssertTrue(path.hasSuffix(".html"))
    }
    func testGeneratedLibraryRejectsTraversal() {
        XCTAssertThrowsError(try ActionPolicy.containedURL(root: ChatCreationFiles.root, path: "../outside.pdf"))
    }
}
