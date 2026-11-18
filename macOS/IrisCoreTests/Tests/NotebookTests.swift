import XCTest
@testable import IrisCore
final class NotebookTests: XCTestCase {
    func testOnlySelectedSourcesAreSharedAndContextIsBounded() {
        let hidden = NotebookSource(name: "Private", text: "DO NOT SHARE", enabled: false)
        let sources = [hidden] + (0..<12).map { NotebookSource(name: "Source \($0)", text: String(repeating: "a", count: 18000)) }
        let evidence = NotebookPolicy.evidence(sources)
        XCTAssertEqual(evidence.count, 6)
        XCTAssertEqual(evidence.reduce(0) { $0 + $1.excerpt.count }, 48000)
        XCTAssertFalse(NotebookPolicy.context(evidence).contains("DO NOT SHARE"))
        XCTAssertTrue(evidence.allSatisfy { $0.excerpt.count <= 8000 })
    }
    func testCitationsOnlyLinkKnownEvidenceAndKeepSnapshots() throws {
        var source = NotebookSource(name: "Chapter", text: "Original")
        let evidence = NotebookPolicy.evidence([source])
        source.text = "Changed"
        let cited = NotebookPolicy.citedEvidence(in: "Answer [S1] with invalid [S99]", evidence: evidence)
        XCTAssertEqual(cited.count, 1); XCTAssertEqual(cited[0].excerpt, "Original")
        XCTAssertTrue(NotebookPolicy.citedEvidence(in: "No citations", evidence: evidence).isEmpty)
        let output = NotebookOutput(title: "Guide", kind: "guide", text: "Answer [S1]", evidence: evidence)
        let book = StudyNotebook(title: "Physics", sources: [source], outputs: [output])
        let decoded = try JSONDecoder().decode(StudyNotebook.self, from: JSONEncoder().encode(book))
        XCTAssertEqual(decoded.outputs[0].evidence[0].excerpt, "Original")
    }
    func testQuizRejectsInvalidAnswerIndexesAndEmptyQuestions() {
        let valid = #"""
        ```iris-quiz
        {"questions":[{"question":"Which?","options":["A","B"],"answer":1,"explanation":"B [S1]"}]}
        ```
        """#
        XCTAssertNotNil(NotebookPolicy.quiz(valid))
        XCTAssertNil(NotebookPolicy.quiz(valid.replacingOccurrences(of: "\"answer\":1", with: "\"answer\":9")))
        XCTAssertNil(NotebookPolicy.quiz("```iris-quiz\n{\"questions\":[]}\n```"))
    }
    func testOlderStateWithoutNotebooksAndLibraryStillLoads() throws {
        let state = PersistedState()
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as! [String: Any]
        object.removeValue(forKey: "notebooks"); object.removeValue(forKey: "createdItems")
        let loaded = try JSONDecoder().decode(PersistedState.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(loaded.notebooks); XCTAssertNil(loaded.createdItems)
    }
    func testLibraryDraftAndFileReferencesRoundTrip() throws {
        var state = PersistedState()
        let file = ChatFileReference(name: "site.html", folderID: "approved-folder", relativePath: "site/index.html")
        state.createdItems = [.init(title: "Website", kind: "file", file: file), .init(title: "Study guide", kind: "draft", text: "# Guide")]
        let loaded = try JSONDecoder().decode(PersistedState.self, from: JSONEncoder().encode(state))
        XCTAssertEqual(loaded.createdItems?[0].file?.relativePath, "site/index.html")
        XCTAssertEqual(loaded.createdItems?[1].text, "# Guide")
    }
}
