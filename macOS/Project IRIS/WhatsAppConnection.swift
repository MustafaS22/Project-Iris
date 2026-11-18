import AppKit
import Combine

@MainActor
final class WhatsAppConnection: ObservableObject {
    @Published private(set) var chats: [WhatsAppChat] = []
    @Published private(set) var selected: Set<String>
    @Published private(set) var connected: Bool
    @Published private(set) var busy = false
    @Published var error: String?
    @Published var status = ""
    private let store: KnowledgeStore
    private var bookmark: Data?
    private let defaults: UserDefaults
    init(store: KnowledgeStore, defaults: UserDefaults = .standard) {
        self.store = store; self.defaults = defaults
        bookmark = defaults.data(forKey: "IrisWhatsAppFolder")
        selected = Set(defaults.stringArray(forKey: "IrisWhatsAppChats") ?? [])
        connected = bookmark != nil
    }
    func grant() {
        let picker = NSOpenPanel(); picker.canChooseDirectories = true; picker.canChooseFiles = false
        picker.prompt = "Connect WhatsApp"; picker.message = "Grant WhatsApp's shared folder to list chat names. Iris reads text only from chats you then select. It cannot send messages."
        picker.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared")
        guard picker.runModal() == .OK, let url = picker.url else { return }
        do {
            let data = try url.bookmarkData(options: IrisLocalStorage.bookmarkOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
            let active = url.startAccessingSecurityScopedResource(); defer { if active { url.stopAccessingSecurityScopedResource() } }
            let list = try WhatsAppReader(url: url.appendingPathComponent("ChatStorage.sqlite")).chats()
            // A new grant starts with no chat permission and removes the previous local source.
            try store.remove(.whatsapp)
            bookmark = data; defaults.set(data, forKey: "IrisWhatsAppFolder")
            selected = []; defaults.set([], forKey: "IrisWhatsAppChats")
            chats = list; connected = true; error = nil; status = "Choose the chats Iris may import."
        } catch { self.error = error.localizedDescription }
    }
    private func reader<T>(_ body: (WhatsAppReader) throws -> T) throws -> T {
        guard let bookmark else { throw WhatsAppReader.Failure.access }
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: IrisLocalStorage.resolutionOptions, relativeTo: nil, bookmarkDataIsStale: &stale)
        guard !stale else { throw WhatsAppReader.Failure.access }
        let active = url.startAccessingSecurityScopedResource(); defer { if active { url.stopAccessingSecurityScopedResource() } }
        return try body(WhatsAppReader(url: url.appendingPathComponent("ChatStorage.sqlite")))
    }
    func reload() {
        do { chats = try reader { try $0.chats() }; error = nil }
        catch { self.error = error.localizedDescription }
    }
    func save(_ selection: Set<String>) {
        guard selection.count <= 20 else { error = WhatsAppReader.Failure.limit.localizedDescription; return }
        busy = true; defer { busy = false }
        do {
            // Revocation takes effect even if a subsequent refresh fails.
            let retained = store.documents.filter { $0.source == .whatsapp && selection.contains($0.externalID) }
            try store.ingest(retained, replacing: .whatsapp)
            selected = selection; defaults.set(Array(selection), forKey: "IrisWhatsAppChats")
            if selection.isEmpty { status = "No chats allowed · imported copies removed"; error = nil; return }
            let documents = try reader { try $0.documents(selected: selection) }
            try store.ingest(documents, replacing: .whatsapp)
            status = "\(documents.count) chats refreshed · \(Date().formatted(date: .omitted, time: .shortened))"; error = nil
        } catch { self.error = error.localizedDescription }
    }
    func selectedDocuments() throws -> [KnowledgeDocument] {
        guard connected, !selected.isEmpty else { throw IrisFailure.message("Choose WhatsApp chats first.") }
        return try reader { try $0.documents(selected: selected) }
    }
    func disconnect() {
        do {
            try store.remove(.whatsapp)
            bookmark = nil; selected = []; chats = []; connected = false
            defaults.removeObject(forKey: "IrisWhatsAppFolder"); defaults.removeObject(forKey: "IrisWhatsAppChats")
            status = "Disconnected · local chat copies removed"; error = nil
        } catch { self.error = error.localizedDescription }
    }
}
