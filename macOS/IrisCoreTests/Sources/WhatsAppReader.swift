import Foundation
import SQLite3

struct WhatsAppChat: Identifiable, Equatable {
    let id: String
    let row: Int64
    let name: String
}

/// Opens only the granted local store, in read-only WAL-aware mode. Never queries unselected message bodies.
final class WhatsAppReader {
    private var db: OpaquePointer?
    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }; db = nil
            throw Failure.access
        }
        sqlite3_busy_timeout(db, 1500)
        _ = sqlite3_exec(db, "PRAGMA query_only=ON; PRAGMA trusted_schema=OFF;", nil, nil, nil)
        do {
            guard try columns("ZWACHATSESSION").isSuperset(of: ["Z_PK", "ZCONTACTJID", "ZPARTNERNAME"]),
                  try columns("ZWAMESSAGE").isSuperset(of: ["ZCHATSESSION", "ZTEXT", "ZMESSAGEDATE", "ZISFROMME"]) else { throw Failure.schema }
        } catch { if let db { sqlite3_close(db) }; db = nil; throw error }
    }
    deinit { if let db { sqlite3_close(db) } }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var s: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &s, nil) == SQLITE_OK, let s else { throw Failure.schema }
        return s
    }
    private func columns(_ table: String) throws -> Set<String> {
        let s = try statement("PRAGMA table_info(\(table))"); defer { sqlite3_finalize(s) }
        var result: Set<String> = []
        while sqlite3_step(s) == SQLITE_ROW { result.insert(text(s, 1)) }
        return result
    }
    private func text(_ s: OpaquePointer, _ index: Int32) -> String { sqlite3_column_text(s, index).map { String(cString: $0) } ?? "" }
    func chats() throws -> [WhatsAppChat] {
        let fields = try columns("ZWACHATSESSION")
        var filters = ["ZCONTACTJID IS NOT NULL", "ZCONTACTJID != ''"]
        for flag in ["ZREMOVED", "ZHIDDEN", "ZISLOCKED"] where fields.contains(flag) { filters.append("COALESCE(\(flag),0)=0") }
        if fields.contains("ZSESSIONTYPE") { filters.append("ZSESSIONTYPE IN (0,1)") }
        let s = try statement("SELECT Z_PK,ZCONTACTJID,ZPARTNERNAME FROM ZWACHATSESSION WHERE \(filters.joined(separator: " AND ")) ORDER BY ZPARTNERNAME COLLATE NOCASE LIMIT 2000")
        defer { sqlite3_finalize(s) }
        var result: [WhatsAppChat] = []
        var status = sqlite3_step(s)
        while status == SQLITE_ROW {
            let id = text(s, 1), name = text(s, 2)
            result.append(.init(id: id, row: sqlite3_column_int64(s, 0), name: name.isEmpty ? id.components(separatedBy: "@")[0] : name))
            status = sqlite3_step(s)
        }
        guard status == SQLITE_DONE else { throw Failure.busy }
        return result
    }
    func documents(selected: Set<String>) throws -> [KnowledgeDocument] {
        guard selected.count <= 20 else { throw Failure.limit }
        let chosen = try chats().filter { selected.contains($0.id) }
        guard Set(chosen.map(\.id)) == selected else { throw Failure.missing }
        let fields = try columns("ZWAMESSAGE")
        let typeFilter = fields.contains("ZMESSAGETYPE") ? " AND ZMESSAGETYPE IN (0,7)" : ""
        let s = try statement("SELECT ZTEXT,ZMESSAGEDATE,ZISFROMME FROM ZWAMESSAGE WHERE ZCHATSESSION=? AND ZTEXT IS NOT NULL AND ZTEXT != ''\(typeFilter) ORDER BY ZMESSAGEDATE DESC LIMIT 400")
        defer { sqlite3_finalize(s) }
        return try chosen.map { chat in
            sqlite3_reset(s); sqlite3_clear_bindings(s); sqlite3_bind_int64(s, 1, chat.row)
            var lines: [(Double, String)] = []
            var status = sqlite3_step(s)
            while status == SQLITE_ROW {
                let timestamp = sqlite3_column_double(s, 1)
                let date = Date(timeIntervalSinceReferenceDate: timestamp).formatted(date: .numeric, time: .shortened)
                let sender = sqlite3_column_int(s, 2) == 1 ? "Me" : "Participant"
                lines.append((timestamp, "[\(date)] \(sender): \(text(s, 0).prefix(4000))"))
                status = sqlite3_step(s)
            }
            guard status == SQLITE_DONE else { throw Failure.busy }
            // Keep the newest material within the existing per-document knowledge budget.
            var recent: [String] = [], length = 0
            for (_, line) in lines { guard length + line.count + 1 <= 29500 else { break }; recent.append(line); length += line.count + 1 }
            return KnowledgeDocument(externalID: chat.id, source: .whatsapp, title: chat.name, body: "WhatsApp chat: \(chat.name)\nText only · recent messages synced to this Mac\n" + recent.reversed().joined(separator: "\n"), updatedAt: lines.first.map { Date(timeIntervalSinceReferenceDate: $0.0) } ?? Date())
        }
    }
    enum Failure: LocalizedError {
        case access, schema, busy, limit, missing
        var errorDescription: String? {
            switch self {
            case .access: "WhatsApp data isn't accessible. Open and sign in to WhatsApp for Mac, then grant its shared folder. macOS may require Iris to have Full Disk Access; restart Iris after changing that permission."
            case .schema: "This WhatsApp database format isn't supported. Update WhatsApp and Iris, then reconnect. Existing imported chats were kept."
            case .busy: "WhatsApp's database is busy. Try again after WhatsApp finishes syncing."
            case .limit: "Choose up to 20 chats."
            case .missing: "A selected chat is no longer available. Reload the chat list and choose again."
            }
        }
    }
}
