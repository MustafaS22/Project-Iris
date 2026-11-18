import XCTest
import SQLite3
@testable import IrisCore

final class WhatsAppReaderTests: XCTestCase {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let sql = """
        CREATE TABLE ZWACHATSESSION(Z_PK INTEGER,ZCONTACTJID TEXT,ZPARTNERNAME TEXT,ZREMOVED INTEGER,ZHIDDEN INTEGER,ZISLOCKED INTEGER,ZSESSIONTYPE INTEGER);
        CREATE TABLE ZWAMESSAGE(ZCHATSESSION INTEGER,ZTEXT TEXT,ZMESSAGEDATE REAL,ZISFROMME INTEGER,ZMESSAGETYPE INTEGER);
        INSERT INTO ZWACHATSESSION VALUES(1,'a@test','Chosen chat',0,0,0,0),(2,'b@test','Other chat',0,0,0,1),(3,'c@test','Hidden chat',0,1,0,0),(4,'d@test','Locked chat',0,0,1,0);
        INSERT INTO ZWAMESSAGE VALUES(1,'Older message',700000000,1,0),(1,'Newer message',700000100,0,0),(2,'Unselected secret',700000200,0,0),(1,'Media caption',700000300,0,1);
        """
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        return url
    }
    func testOnlySelectedChatTextIsImportedInChronologicalOrder() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let documents = try WhatsAppReader(url: url).documents(selected: ["a@test"])
        XCTAssertEqual(documents.count, 1); XCTAssertEqual(documents[0].externalID, "a@test")
        XCTAssertTrue(documents[0].body.contains("Older message")); XCTAssertTrue(documents[0].body.contains("Newer message"))
        XCTAssertFalse(documents[0].body.contains("Unselected secret")); XCTAssertFalse(documents[0].body.contains("Media caption"))
        XCTAssertLessThan(documents[0].body.range(of: "Older message")!.lowerBound, documents[0].body.range(of: "Newer message")!.lowerBound)
        XCTAssertEqual(documents[0].updatedAt, Date(timeIntervalSinceReferenceDate: 700000100))
    }
    func testMetadataExcludesHiddenAndLockedChats() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(Set(try WhatsAppReader(url: url).chats().map(\.id)), ["a@test", "b@test"])
    }
    func testEmptySelectionReadsNoMessagesAndSourceIsUnmodified() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let before = try Data(contentsOf: url)
        XCTAssertTrue(try WhatsAppReader(url: url).documents(selected: []).isEmpty)
        _ = try WhatsAppReader(url: url).documents(selected: ["a@test"])
        XCTAssertEqual(try Data(contentsOf: url), before)
    }
    func testUnavailableOrTooManyChatsCannotBeImported() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let reader = try WhatsAppReader(url: url)
        XCTAssertThrowsError(try reader.documents(selected: ["missing"]))
        XCTAssertThrowsError(try reader.documents(selected: Set((0..<21).map(String.init))))
    }
    func testBadSchemaAndMissingStoreFailWithoutCreatingFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertThrowsError(try WhatsAppReader(url: url))
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try Data("unsupported".utf8).write(to: url); defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertThrowsError(try WhatsAppReader(url: url))
    }
}
