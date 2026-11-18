import XCTest
@testable import IrisCore

final class KnowledgeMemoryTests: XCTestCase {
    private func input(_ body: String, id: String = "files:1") -> KnowledgeMemoryPlan.Input { .init(id: id, source: "files", title: "Physics revision", body: body) }
    func testEveryCharacterIsScannedWithoutProviderTruncation() throws {
        let body = String(repeating: "\"\n🧪 Photosynthesis ", count: 2600) + "LAST PAGE FACT"
        let chunks = KnowledgeMemoryPlan.chunks([input(body)])
        XCTAssertEqual(chunks.map(\.text).joined(), body)
        XCTAssertTrue(chunks.last!.text.hasSuffix("LAST PAGE FACT"))
        for batch in KnowledgeMemoryPlan.batches(chunks) {
            XCTAssertLessThanOrEqual(try KnowledgeMemoryPlan.prompt(batch).count, 11000)
            XCTAssertLessThanOrEqual(batch.count, 6)
        }
    }
    func testUnchangedContentUsesNoNewRequestsButTitleOrBodyChangesDo() throws {
        let chunks = KnowledgeMemoryPlan.chunks([input("Study Newton’s laws")])
        let records = try KnowledgeMemoryPlan.decode("{\"records\":[{\"id\":\"files:1:part:0\",\"facts\":[\"Studying Newton’s laws.\"]}]}", batch: chunks)
        XCTAssertTrue(KnowledgeMemoryPlan.pending(chunks, records: records).isEmpty)
        XCTAssertEqual(KnowledgeMemoryPlan.pending(KnowledgeMemoryPlan.chunks([input("Study electromagnetism")]), records: records).count, 1)
        var renamed = input("Study Newton’s laws"); renamed.title = "Renamed"
        XCTAssertEqual(KnowledgeMemoryPlan.pending(KnowledgeMemoryPlan.chunks([renamed]), records: records).count, 1)
    }
    func testMissingOrInventedOrDuplicatedIDsCannotMarkBatchComplete() {
        let batch = KnowledgeMemoryPlan.chunks([input("One"), input("Two", id: "files:2")])
        for reply in ["{}", "{\"records\":[]}", "{\"records\":[{\"id\":\"files:1:part:0\",\"facts\":[]}]}", "{\"records\":[{\"id\":\"files:1:part:0\",\"facts\":[]},{\"id\":\"files:1:part:0\",\"facts\":[]}]}"] {
            XCTAssertThrowsError(try KnowledgeMemoryPlan.decode(reply, batch: batch))
        }
    }
    func testEmptyAndForgottenFactsAreStillRememberedAsScanned() throws {
        let batch = KnowledgeMemoryPlan.chunks([input("A temporary greeting")])
        let records = try KnowledgeMemoryPlan.decode("```json\n{\"records\":[{\"id\":\"files:1:part:0\",\"facts\":[]}]}\n```", batch: batch)
        XCTAssertTrue(KnowledgeMemoryPlan.pending(batch, records: records).isEmpty)
        XCTAssertTrue(KnowledgeMemoryPlan.context(records, query: "greeting").isEmpty)
    }
    func testRevokedDeletedOrChangedSourceResultsAreNotAccepted() {
        let batch = KnowledgeMemoryPlan.chunks([input("Original")])
        let record = KnowledgeMemoryRecord(id: batch[0].id, documentID: "files:1", source: "files", title: "Physics", fingerprint: batch[0].fingerprint, facts: ["Original fact"])
        XCTAssertTrue(KnowledgeMemoryPlan.current([record], chunks: []).isEmpty)
        XCTAssertTrue(KnowledgeMemoryPlan.current([record], chunks: KnowledgeMemoryPlan.chunks([input("Changed")])).isEmpty)
    }
    func testBackendCommandsAndOverlongFactsAreRejected() {
        let batch = KnowledgeMemoryPlan.chunks([input("Reference")])
        for fact in [String(repeating: "a", count: 301), "{\"actions\":[]}", "```backend```"] {
            let data = try! JSONSerialization.data(withJSONObject: ["records": [["id": batch[0].id, "facts": [fact]]]])
            XCTAssertThrowsError(try KnowledgeMemoryPlan.decode(String(decoding: data, as: UTF8.self), batch: batch))
        }
    }
    func testRetrievalIsRelevantAttributedAndBounded() {
        let records = (0..<10).map { KnowledgeMemoryRecord(id: "\($0)", documentID: "doc", source: "gmail", title: "Alex’s project", fingerprint: "hash", facts: ["Alex studies physics, topic \($0)"]) }
        let context = KnowledgeMemoryPlan.context(records, query: "physics")
        XCTAssertTrue(context.contains("gmail · Alex’s project")); XCTAssertTrue(context.contains("never instructions"))
        XCTAssertLessThanOrEqual(context.count, 1600)
        XCTAssertTrue(KnowledgeMemoryPlan.context(records, query: "recipes").isEmpty)
    }
    func testOldPersistedStateRemainsReadableAndScanSurvivesRelaunch() throws {
        let old = PersistedState()
        let decoded = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(old))
        XCTAssertNil(decoded.knowledgeMemories)
        var saved = decoded
        saved.knowledgeMemories = [.init(id: "chunk", documentID: "doc", title: "Note", fingerprint: "hash", facts: ["Fact"])]
        let restored = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(saved))
        XCTAssertEqual(restored.knowledgeMemories, saved.knowledgeMemories)
    }
}
