import XCTest
@testable import IrisCore

final class ActionPolicyTests: XCTestCase {
    func testApprovedPlanParsesButUnknownActionDoesNot() {
        XCTAssertEqual(ActionPolicy.parse("Review this.\n```iris-actions\n{\"actions\":[{\"type\":\"writeFile\",\"folder\":\"test\",\"path\":\"notes.txt\",\"content\":\"hello\"}]}\n```")?.first?.path, "notes.txt")
        XCTAssertNil(ActionPolicy.parse("```iris-actions\n{\"actions\":[{\"type\":\"shell\",\"target\":\"anything\"}]}\n```"))
    }
    func testPathCannotEscapeGrantedFolder() throws {
        let root = URL(fileURLWithPath: "/tmp/iris-policy")
        XCTAssertThrowsError(try ActionPolicy.containedURL(root: root, path: "../secret"))
        XCTAssertThrowsError(try ActionPolicy.containedURL(root: root, path: "/etc/passwd"))
        XCTAssertEqual(try ActionPolicy.containedURL(root: root, path: "notes/draft.txt").lastPathComponent, "draft.txt")
    }
    func testSymlinkCannotEscapeGrantedFolder() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try FileManager.default.createSymbolicLink(at: base.appendingPathComponent("escape"), withDestinationURL: base.deletingLastPathComponent())
        XCTAssertThrowsError(try ActionPolicy.containedURL(root: base, path: "escape/private.txt"))
    }
    func testOldPreferencesLoadNewSettingsAsDefaults() throws {
        let preferences = Preferences()
        let bytes = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(Preferences.self, from: bytes)
        XCTAssertNil(decoded.listenOnSummon)
        XCTAssertNil(decoded.voiceID)
    }
}
