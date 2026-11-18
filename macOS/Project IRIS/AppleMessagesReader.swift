import Foundation
import SQLite3

/// Reads the macOS Messages database in place. Chat discovery only reads metadata.
final class AppleMessagesReader {
    static var databaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db")
    }

    private let db: OpaquePointer
    init(url: URL = AppleMessagesReader.databaseURL) throws {
        var handle: OpaquePointer?
        let status = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard status == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw IrisFailure.message("Iris can’t open Messages history. Open Messages and sign in if needed. Then allow Iris in System Settings → Privacy & Security → Full Disk Access and restart Iris.")
        }
        db = handle
        sqlite3_busy_timeout(db, 1500)
        sqlite3_exec(db, "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF;", nil, nil, nil)
    }
    deinit { sqlite3_close(db) }

    private func statement(_ sql: String) throws -> OpaquePointer {
        var result: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &result, nil) == SQLITE_OK, let result else {
            throw IrisFailure.message("Messages history couldn’t be read on this Mac. Check Full Disk Access, then reopen Iris and retry.")
        }
        return result
    }
    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }
    private func read(_ statement: OpaquePointer, row: () -> Void) throws {
        var status = sqlite3_step(statement)
        while status == SQLITE_ROW { try Task.checkCancellation(); row(); status = sqlite3_step(statement) }
        guard status == SQLITE_DONE else { throw IrisFailure.message("Messages history is unavailable or busy. Check access and try again.") }
    }

    func choices() throws -> [AppleKnowledgeSelection] {
        let s = try statement("""
            SELECT c.guid, COALESCE(NULLIF(c.display_name,''), NULLIF(
                (SELECT group_concat(participant, ', ') FROM
                    (SELECT DISTINCT h.id AS participant FROM chat_handle_join j JOIN handle h ON h.ROWID=j.handle_id WHERE j.chat_id=c.ROWID LIMIT 4)), ''),
                NULLIF(c.chat_identifier,''), 'Conversation'), c.service_name
            FROM chat c
            WHERE length(c.guid)>0 AND EXISTS(SELECT 1 FROM chat_message_join j WHERE j.chat_id=c.ROWID)
            ORDER BY (SELECT MAX(j.message_id) FROM chat_message_join j WHERE j.chat_id=c.ROWID) DESC LIMIT 1000
            """)
        defer { sqlite3_finalize(s) }
        var results: [AppleKnowledgeSelection] = []
        try read(s) {
            results.append(.init(id: text(s, 0), title: text(s, 1), detail: text(s, 2)))
        }
        return results
    }

    func documents(selected: [AppleKnowledgeSelection]) throws -> [KnowledgeDocument] {
        guard !selected.isEmpty, selected.count <= 10 else { return [] }
        let s = try statement("""
            SELECT m.text, m.date, m.is_from_me,
                   CASE WHEN length(m.attributedBody) <= 131072 THEN m.attributedBody END, h.id
            FROM chat_message_join j
            JOIN message m ON m.ROWID=j.message_id LEFT JOIN handle h ON h.ROWID=m.handle_id
            WHERE j.chat_id=(SELECT ROWID FROM chat WHERE guid=?)
              AND COALESCE(m.is_system_message,0)=0 AND COALESCE(m.associated_message_type,0)=0
              AND (length(m.text)>0 OR m.attributedBody IS NOT NULL)
            ORDER BY m.date DESC LIMIT 150
            """)
        defer { sqlite3_finalize(s) }
        var documents: [KnowledgeDocument] = []
        for chat in selected {
            try Task.checkCancellation()
            sqlite3_reset(s)
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            guard sqlite3_bind_text(s, 1, chat.id, -1, transient) == SQLITE_OK else {
                throw IrisFailure.message("Iris couldn’t select this Messages conversation.")
            }
            var lines: [String] = [], latest: Date?, remaining = 28_000
            try read(s) {
                guard remaining > 50 else { return }
                var content = text(s, 0)
                if content.isEmpty, let blob = sqlite3_column_blob(s, 3) {
                    content = Self.attributedText(Data(bytes: blob, count: Int(sqlite3_column_bytes(s, 3)))) ?? ""
                }
                content = content.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !content.isEmpty else { return }
                let timestamp = sqlite3_column_double(s, 1)
                let date = Date(timeIntervalSinceReferenceDate: abs(timestamp) > 10_000_000_000 ? timestamp / 1_000_000_000 : timestamp)
                let handle = text(s, 4)
                let sender = sqlite3_column_int(s, 2) == 1 ? "Me" : handle.isEmpty ? "Participant" : handle
                let line = "[\(date.formatted(date: .abbreviated, time: .shortened))] \(sender): \(content.prefix(2_500))"
                guard line.count + 1 <= remaining else { return }
                remaining -= line.count + 1
                lines.append(line)
                if latest == nil { latest = date }
            }
            if let latest {
                documents.append(.init(externalID: chat.id, source: .appleMessages, title: chat.title, body: lines.reversed().joined(separator: "\n"), updatedAt: latest))
            }
        }
        return documents
    }

    /// Read only the first NSString payload of a known attributed-string typedstream.
    /// Never unarchive or instantiate classes from a private message database.
    static func attributedText(_ data: Data) -> String? {
        let signature = Data([4, 11] + Array("streamtyped".utf8))
        guard data.count <= 131072, data.starts(with: signature),
              let root = data.range(of: Data("NSAttributedString".utf8), in: 0..<min(90, data.count)),
              let string = data.range(of: Data("NSString".utf8), in: root.upperBound..<min(180, data.count)),
              let marker = data.range(of: Data([0x84, 0x01, 0x2b]), in: string.upperBound..<min(string.upperBound + 16, data.count)) else { return nil }
        var offset = marker.upperBound
        guard offset < data.count else { return nil }
        let size = data[offset]
        offset += 1
        let length: Int
        switch size {
        case 0...127: length = Int(size)
        case 0x81:
            guard offset + 2 <= data.count else { return nil }
            length = Int(data[offset]) | Int(data[offset + 1]) << 8
            offset += 2
        case 0x82:
            guard offset + 4 <= data.count else { return nil }
            length = Int(data[offset]) | Int(data[offset + 1]) << 8 | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
            offset += 4
        default: return nil
        }
        guard length > 0, length <= data.count - offset else { return nil }
        return String(data: data[offset..<(offset + length)], encoding: .utf8)
    }
}
