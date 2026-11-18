import XCTest
@testable import IrisCore

final class KnowledgeTests: XCTestCase {
    func testRetrievalNeverIncludesUnapprovedSources() {
        let docs = [KnowledgeDocument(externalID: "1", source: .gmail, title: "Exam deadline", body: "Your physics exam is Monday", updatedAt: Date()), KnowledgeDocument(externalID: "2", source: .files, title: "Exam notes", body: "Physics notes", updatedAt: Date())]
        XCTAssertTrue(KnowledgeRetrieval.relevant(to: "exam", documents: docs, enabled: []).isEmpty)
        XCTAssertEqual(KnowledgeRetrieval.relevant(to: "exam", documents: docs, enabled: ["files"]).map(\.id), ["files:2"])
    }
    func testRetrievalRejectsEmptyQueryAndRanksTitleMatch() {
        let docs = [KnowledgeDocument(externalID: "1", source: .files, title: "General notes", body: "recursion is a technique", updatedAt: Date()), KnowledgeDocument(externalID: "2", source: .files, title: "Recursion", body: "base case", updatedAt: Date())]
        XCTAssertTrue(KnowledgeRetrieval.relevant(to: "the and", documents: docs, enabled: ["files"]).isEmpty)
        XCTAssertEqual(KnowledgeRetrieval.relevant(to: "recursion", documents: docs, enabled: ["files"]).first?.externalID, "2")
    }
    @MainActor func testDatabasePersistsDocumentsAndSharingAndRemovesSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KnowledgeStore(directory: directory)
        XCTAssertNil(store.error)
        let doc = KnowledgeDocument(externalID: "id'quote", source: .files, title: "O'Brien", body: "Personal recursion notes", updatedAt: Date())
        try store.ingest([doc]); XCTAssertEqual(store.documents.count, 1)
        XCTAssertTrue(store.context(for: "recursion").isEmpty)
        try store.setSharing(.files, enabled: true)
        XCTAssertTrue(store.context(for: "recursion").contains("O'Brien"))
        let restored = KnowledgeStore(directory: directory)
        XCTAssertEqual(restored.documents.first?.body, doc.body); XCTAssertTrue(restored.enabled.contains("files"))
        try store.remove(.files)
        XCTAssertTrue(store.documents.isEmpty); XCTAssertFalse(store.enabled.contains("files"))
    }
    @MainActor func testSourceRefreshAtomicallyReplacesOnlyThatSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = KnowledgeStore(directory: directory)
        try store.ingest([.init(externalID: "old", source: .gmail, title: "Old", body: "Body", updatedAt: Date()), .init(externalID: "local", source: .files, title: "Keep", body: "Body", updatedAt: Date())])
        try store.ingest([.init(externalID: "new", source: .gmail, title: "New", body: "Body", updatedAt: Date())], replacing: .gmail)
        XCTAssertEqual(Set(store.documents.map(\.externalID)), ["new", "local"])
    }
}
