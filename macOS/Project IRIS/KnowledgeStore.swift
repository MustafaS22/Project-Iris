import Foundation
import Combine
import SQLite3

@MainActor
final class KnowledgeStore: ObservableObject {
    @Published private(set) var documents: [KnowledgeDocument] = []
    @Published var error: String?
    @Published private(set) var enabled: Set<String> = []
    var didRemoveSource: ((KnowledgeConnector) -> Void)?
    private var database: OpaquePointer?
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    init(directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard sqlite3_open(directory.appendingPathComponent("knowledge.sqlite").path, &database) == SQLITE_OK else { throw IrisFailure.message("The local knowledge database couldn't be opened.") }
            try execute("PRAGMA journal_mode=WAL;")
            try execute("CREATE TABLE IF NOT EXISTS documents (source TEXT NOT NULL, externalID TEXT NOT NULL, title TEXT NOT NULL, body TEXT NOT NULL, updated REAL NOT NULL, PRIMARY KEY(source,externalID));")
            try execute("CREATE TABLE IF NOT EXISTS sharing (source TEXT PRIMARY KEY, enabled INTEGER NOT NULL);")
            try reload()
        } catch { self.error = error.localizedDescription }
    }
    deinit { sqlite3_close(database) }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw IrisFailure.message("The knowledge database couldn't save this change.") }
    }
    private func statement(_ sql: String) throws -> OpaquePointer {
        var value: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &value, nil) == SQLITE_OK, let value else { throw IrisFailure.message("The knowledge database is unavailable.") }
        return value
    }
    private func bind(_ text: String, _ index: Int32, to statement: OpaquePointer) { _ = sqlite3_bind_text(statement, index, text, -1, transient) }
    func ingest(_ items: [KnowledgeDocument], replacing source: KnowledgeConnector? = nil) throws {
        try execute("BEGIN IMMEDIATE;")
        do {
            if let source { try deleteRows(source) }
            let prepared = try statement("INSERT OR REPLACE INTO documents VALUES (?,?,?,?,?);"); defer { sqlite3_finalize(prepared) }
            for item in items.prefix(500) {
                sqlite3_reset(prepared); sqlite3_clear_bindings(prepared)
                bind(item.source.rawValue, 1, to: prepared); bind(item.externalID, 2, to: prepared); bind(String(item.title.prefix(500)), 3, to: prepared); bind(String(item.body.prefix(30000)), 4, to: prepared); sqlite3_bind_double(prepared, 5, item.updatedAt.timeIntervalSince1970)
                guard sqlite3_step(prepared) == SQLITE_DONE else { throw IrisFailure.message("A knowledge item couldn't be saved.") }
            }
            try execute("COMMIT;"); try reload()
        } catch { try? execute("ROLLBACK;"); throw error }
    }
    private func deleteRows(_ source: KnowledgeConnector) throws {
        let prepared = try statement("DELETE FROM documents WHERE source=?;"); defer { sqlite3_finalize(prepared) }; bind(source.rawValue, 1, to: prepared)
        guard sqlite3_step(prepared) == SQLITE_DONE else { throw IrisFailure.message("Source documents couldn't be removed.") }
    }
    func remove(_ source: KnowledgeConnector) throws { try deleteRows(source); try setSharing(source, enabled: false); try reload(); didRemoveSource?(source) }
    func setSharing(_ source: KnowledgeConnector, enabled: Bool) throws {
        let prepared = try statement("INSERT OR REPLACE INTO sharing VALUES (?,?);"); defer { sqlite3_finalize(prepared) }
        bind(source.rawValue, 1, to: prepared); sqlite3_bind_int(prepared, 2, enabled ? 1 : 0)
        guard sqlite3_step(prepared) == SQLITE_DONE else { throw IrisFailure.message("Source preferences couldn't be saved.") }
        if enabled { self.enabled.insert(source.rawValue) } else { self.enabled.remove(source.rawValue) }
    }
    private func reload() throws {
        let prepared = try statement("SELECT source,externalID,title,body,updated FROM documents ORDER BY updated DESC;"); defer { sqlite3_finalize(prepared) }
        var items: [KnowledgeDocument] = []
        while sqlite3_step(prepared) == SQLITE_ROW {
            func string(_ index: Int32) -> String { sqlite3_column_text(prepared, index).map { String(cString: $0) } ?? "" }
            if let source = KnowledgeConnector(rawValue: string(0)) { items.append(.init(externalID: string(1), source: source, title: string(2), body: string(3), updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(prepared, 4)))) }
        }
        documents = items
        let sharing = try statement("SELECT source FROM sharing WHERE enabled=1;"); defer { sqlite3_finalize(sharing) }
        var enabled: Set<String> = []
        while sqlite3_step(sharing) == SQLITE_ROW { if let value = sqlite3_column_text(sharing, 0) { enabled.insert(String(cString: value)) } }
        self.enabled = enabled
    }
    func context(for query: String, only sources: Set<KnowledgeConnector> = []) -> String {
        let allowed = sources.isEmpty ? enabled : enabled.intersection(Set(sources.map(\.rawValue)))
        let eligible = documents.filter { allowed.contains($0.source.rawValue) }
        var selected = KnowledgeRetrieval.relevant(to: query, documents: eligible, enabled: allowed)
        // An explicit source mention may ask about recent material without overlapping its words.
        // Fallback stays within the named, enabled sources, never unrelated background knowledge.
        if !sources.isEmpty {
            for source in sources.sorted(by: { $0.rawValue < $1.rawValue }) where !selected.contains(where: { $0.source == source }) {
                selected += eligible.filter { $0.source == source }.sorted { $0.updatedAt > $1.updatedAt }.prefix(1)
            }
        }
        let bounded = Array(selected.prefix(8))
        let excerptLimit = max(200, min(2200, (4000 - bounded.count * 140) / max(1, bounded.count)))
        return bounded.map { "[\($0.source.name) · \(String($0.title.prefix(100)))]\n\($0.body.prefix(excerptLimit))" }.joined(separator: "\n\n")
    }
}
