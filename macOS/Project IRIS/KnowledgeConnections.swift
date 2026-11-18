import AppKit
import Carbon
import Foundation
import Combine
import EventKit
import CryptoKit
import UniformTypeIdentifiers
import OSLog

@MainActor
final class KnowledgeConnections: ObservableObject {
    @Published var busy: KnowledgeConnector?
    @Published var status: [String: String] = [:]
    @Published var calendars: [EKCalendar] = []
    @Published var selectedCalendars: Set<String> = []
    @Published private(set) var appleChoices: [KnowledgeConnector: [AppleKnowledgeSelection]] = [:]
    let whatsApp: WhatsAppConnection
    private let eventStore = EKEventStore()
    private let store: KnowledgeStore
    private let accounts: AccountService
    private var task: Task<Void, Never>?
    private var automaticTask: Task<Void, Never>?
    private var refreshTimer: Timer?
    private static let log = Logger(subsystem: "com.projectiris.Project-IRIS", category: "knowledge")
    init(store: KnowledgeStore, accounts: AccountService) { self.store = store; self.accounts = accounts; self.whatsApp = WhatsAppConnection(store: store); store.didRemoveSource = { [weak self] source in self?.setAutomatic(source, enabled: false) } }
    func connect(_ source: KnowledgeConnector) {
        guard busy == nil else { return }
        if source == .whatsapp { return }
        if SocialExportReader.sources.contains(source) { importSocial(source); return }
        if source == .files { importFiles(source); return }
        if source.usesAppleSelection { loadAppleChoices(source); return }
        busy = source; status[source.rawValue] = "Connecting…"
        task = Task {
            defer { busy = nil }
            do {
                if source == .appleCalendar {
                    guard try await eventStore.requestFullAccessToEvents() else { throw IrisFailure.message("Calendar access wasn't granted. You can change it in System Settings → Privacy & Security → Calendars.") }
                    calendars = eventStore.calendars(for: .event)
                    selectedCalendars.formIntersection(calendars.map(\.calendarIdentifier))
                    // No automatic import of every calendar. The user chooses and imports explicitly.
                    status[source.rawValue] = "Choose calendars below, then import events."
                    return
                }
                let target = UserDefaults.standard.string(forKey: "IrisConnectorTarget-" + source.rawValue) ?? ""
                if AppKnowledgeAPI.tokenSources.contains(source) {
                    guard let token = try AppConnectorVault.read(source) else { throw IrisFailure.message("Configure the API token first.") }
                    let documents = try await AppKnowledgeAPI.fetch(source: source, target: target, token: token)
                    try Task.checkCancellation(); try store.ingest(documents, replacing: source)
                    status[source.rawValue] = "\(documents.count) items imported"; imported(source); return
                }
                if source == .googleChat { _ = try AppKnowledgeAPI.request(source: source, target: target, token: "validation") }
                if try GoogleAppConfiguration.read() == nil { guard try GoogleAppConfiguration.importFile() else { status[source.rawValue] = "Setup cancelled · nothing imported"; return } }
                guard let configuration = try GoogleAppConfiguration.read(), let scope = source.scope else { throw IrisFailure.message("Import Iris's Google Desktop OAuth configuration first. No API key is needed.") }
                let saved = try CredentialVault.read(.googleKnowledge)
                if saved == nil || saved?.clientID != configuration.clientID || !(saved?.scopes.contains(scope) ?? false) { try await accounts.signIn(source: .googleKnowledge, googleClientID: configuration.clientID, googleScopes: [scope]) }
                let token = try await AccountService.bearer(for: .googleKnowledge)
                let documents = (source == .googleChat || source == .googleTasks) ? try await AppKnowledgeAPI.fetch(source: source, target: target, token: token) : try await GoogleKnowledgeAPI.fetch(source, token: token)
                try Task.checkCancellation()
                try store.ingest(documents, replacing: source)
                status[source.rawValue] = "\(documents.count) items imported · \(Date().formatted(date: .omitted, time: .shortened))"
                imported(source)
                Self.log.info("Knowledge import completed for \(source.rawValue, privacy: .public)")
            } catch is CancellationError { status[source.rawValue] = "Cancelled · existing knowledge kept" }
            catch { status[source.rawValue] = error.localizedDescription; Self.log.error("Knowledge import failed") }
        }
    }
    static func supportsAutomaticRefresh(_ source: KnowledgeConnector) -> Bool {
        source.scope != nil || AppKnowledgeAPI.tokenSources.contains(source) || source.usesAppleSelection || source == .appleCalendar || source == .whatsapp
    }
    var automaticSources: Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "IrisAutomaticConnections") ?? [])
    }
    func setAutomatic(_ source: KnowledgeConnector, enabled: Bool) {
        guard Self.supportsAutomaticRefresh(source) else { return }
        var sources = automaticSources
        if enabled { sources.insert(source.rawValue) } else { sources.remove(source.rawValue) }
        UserDefaults.standard.set(Array(sources).sorted(), forKey: "IrisAutomaticConnections")
        UserDefaults.standard.set(!enabled, forKey: "IrisAutomaticDisabled-" + source.rawValue)
        objectWillChange.send()
    }
    private func imported(_ source: KnowledgeConnector) {
        guard Self.supportsAutomaticRefresh(source) else { return }
        if !UserDefaults.standard.bool(forKey: "IrisAutomaticDisabled-" + source.rawValue) { setAutomatic(source, enabled: true) }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "IrisLastAutomaticAttempt-" + source.rawValue)
    }
    func startAutomaticRefresh() {
        guard refreshTimer == nil else { return }
        // Existing imports were explicitly connected; never discover new accounts or chats.
        if UserDefaults.standard.object(forKey: "IrisAutomaticConnections") == nil {
            let existing = Set(store.documents.map(\.source)).filter { Self.supportsAutomaticRefresh($0) }
            UserDefaults.standard.set(existing.map(\.rawValue), forKey: "IrisAutomaticConnections")
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAutomaticIfDue() }
        }
    }
    func stopAutomaticRefresh() { refreshTimer?.invalidate(); refreshTimer = nil; automaticTask?.cancel(); automaticTask = nil }
    private func refreshAutomaticIfDue() {
        guard busy == nil, automaticTask == nil else { return }
        let now = Date()
        let due = KnowledgeConnector.allCases.filter { source in
            guard automaticSources.contains(source.rawValue), Self.supportsAutomaticRefresh(source) else { return false }
            let stamp = UserDefaults.standard.double(forKey: "IrisLastAutomaticAttempt-" + source.rawValue)
            return ConnectionRefreshPolicy.isDue(lastAttempt: stamp == 0 ? nil : Date(timeIntervalSince1970: stamp), now: now)
        }
        let ordered = due.sorted {
            UserDefaults.standard.double(forKey: "IrisLastAutomaticAttempt-" + $0.rawValue) < UserDefaults.standard.double(forKey: "IrisLastAutomaticAttempt-" + $1.rawValue)
        }
        guard let source = ordered.first else { return }
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "IrisLastAutomaticAttempt-" + source.rawValue)
        busy = source
        automaticTask = Task { [weak self] in
            guard let self else { return }
            defer { self.busy = nil; self.automaticTask = nil }
            do {
                let documents = try await self.automaticDocuments(source)
                try Task.checkCancellation()
                guard self.automaticSources.contains(source.rawValue) else { return }
                try self.store.ingest(documents, replacing: source)
                self.status[source.rawValue] = "\(documents.count) items · refreshed automatically at \(Date().formatted(date: .omitted, time: .shortened))"
            } catch is CancellationError { }
            catch { self.status[source.rawValue] = "Auto refresh paused: " + error.localizedDescription + " Existing knowledge kept." }
        }
    }
    private func automaticDocuments(_ source: KnowledgeConnector) async throws -> [KnowledgeDocument] {
        if source == .whatsapp { return try whatsApp.selectedDocuments() }
        if source == .appleCalendar {
            guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw IrisFailure.message("Calendar access needs attention in Settings.") }
            let ids = Set(UserDefaults.standard.stringArray(forKey: "IrisAppleCalendarSelection") ?? [])
            let selected = eventStore.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) }
            guard !ids.isEmpty, selected.count == ids.count else { throw IrisFailure.message("Choose your calendars again.") }
            let now = Date(), until = Calendar.current.date(byAdding: .day, value: 30, to: now)!
            return eventStore.events(matching: eventStore.predicateForEvents(withStart: now, end: until, calendars: selected)).prefix(300).map {
                .init(externalID: ($0.eventIdentifier ?? "") + "-\($0.startDate.timeIntervalSince1970)", source: source, title: $0.title ?? "Untitled event", body: "\($0.startDate.formatted()) – \($0.endDate.formatted())\n\($0.location ?? "")\n\($0.notes ?? "")", updatedAt: $0.lastModifiedDate ?? now)
            }
        }
        if source.usesAppleSelection {
            let ids = savedAppleSelection(source)
            guard !ids.isEmpty else { throw IrisFailure.message("Choose the folders, lists or chats Iris may refresh.") }
            if source == .appleReminders {
                guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else { throw IrisFailure.message("Reminders access needs attention in Settings.") }
                return try await reminderDocuments(ids: ids)
            }
            if source == .appleMessages {
                return try await Task.detached(priority: .utility) {
                    let reader = try AppleMessagesReader()
                    let selected = try reader.choices().filter { ids.contains($0.id) }
                    guard selected.count == ids.count else { throw IrisFailure.message("Your selected conversations changed; choose them again.") }
                    return try reader.documents(selected: selected)
                }.value
            }
            let bundle = source == .appleNotes ? "com.apple.Notes" : "com.apple.mail"
            guard !NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty else { throw IrisFailure.message("Open \(source.name) to refresh it.") }
            let descriptor = NSAppleEventDescriptor(bundleIdentifier: bundle)
            guard AEDeterminePermissionToAutomateTarget(descriptor.aeDesc, typeWildCard, typeWildCard, false) == noErr else { throw IrisFailure.message("Reconnect \(source.name) to restore Automation access.") }
            let selection = try AppleAutomationKnowledge.choices(for: source).filter { ids.contains($0.id) }
            guard selection.count == ids.count else { throw IrisFailure.message("Your saved selection changed; choose it again.") }
            return try AppleAutomationKnowledge.documents(for: source, selected: selection)
        }
        let target = UserDefaults.standard.string(forKey: "IrisConnectorTarget-" + source.rawValue) ?? ""
        if AppKnowledgeAPI.tokenSources.contains(source) {
            guard let token = try await Task.detached(priority: .utility, operation: { try AppConnectorVault.read(source, allowInteraction: false) }).value else { throw IrisFailure.message("Reconnect this account.") }
            return try await AppKnowledgeAPI.fetch(source: source, target: target, token: token)
        }
        let saved = try await CredentialVault.readAsync(.googleKnowledge, allowInteraction: false)
        let config = try await Task.detached(priority: .utility) { try GoogleAppConfiguration.read(allowInteraction: false) }.value
        guard let saved, let scope = source.scope, saved.scopes.contains(scope),
              let config, saved.clientID == config.clientID else { throw IrisFailure.message("Reconnect this Google source.") }
        let token = try await AccountService.bearer(for: .googleKnowledge, allowInteraction: false)
        return (source == .googleChat || source == .googleTasks) ? try await AppKnowledgeAPI.fetch(source: source, target: target, token: token) : try await GoogleKnowledgeAPI.fetch(source, token: token)
    }

    func cancel() { task?.cancel(); automaticTask?.cancel(); accounts.cancel() }

    private func loadAppleChoices(_ source: KnowledgeConnector) {
        appleChoices[source] = nil
        busy = source
        status[source.rawValue] = nil
        task = Task {
            defer { busy = nil }
            do {
                let choices: [AppleKnowledgeSelection]
                switch source {
                case .appleNotes, .appleMail:
                    choices = try AppleAutomationKnowledge.choices(for: source)
                case .appleReminders:
                    guard try await eventStore.requestFullAccessToReminders() else {
                        throw IrisFailure.message("Allow Iris in System Settings → Privacy & Security → Reminders, then retry.")
                    }
                    choices = eventStore.calendars(for: .reminder).map {
                        .init(id: $0.calendarIdentifier, title: $0.title, detail: $0.source.title)
                    }
                case .appleMessages:
                    choices = try await Task.detached(priority: .userInitiated) { try AppleMessagesReader().choices() }.value
                default: return
                }
                try Task.checkCancellation()
                appleChoices[source] = choices
            } catch is CancellationError { status[source.rawValue] = "Cancelled · existing knowledge kept" }
            catch { status[source.rawValue] = error.localizedDescription }
        }
    }

    func savedAppleSelection(_ source: KnowledgeConnector) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: "IrisAppleSelection-" + source.rawValue) ?? [])
    }

    func importAppleSelection(_ source: KnowledgeConnector, ids: Set<String>) {
        guard busy == nil, !ids.isEmpty, ids.count <= 10,
              let available = appleChoices[source] else { return }
        let selection = available.filter { ids.contains($0.id) }
        guard selection.count == ids.count else { return }
        busy = source
        status[source.rawValue] = nil
        task = Task {
            defer { busy = nil }
            do {
                let documents: [KnowledgeDocument]
                switch source {
                case .appleNotes, .appleMail:
                    documents = try AppleAutomationKnowledge.documents(for: source, selected: selection)
                case .appleMessages:
                    documents = try await Task.detached(priority: .userInitiated) {
                        try AppleMessagesReader().documents(selected: selection)
                    }.value
                case .appleReminders:
                    documents = try await reminderDocuments(ids: ids)
                default: return
                }
                try Task.checkCancellation()
                guard !documents.isEmpty else {
                    status[source.rawValue] = "No readable items in the selection · existing knowledge kept"
                    return
                }
                if ids != savedAppleSelection(source) { try store.setSharing(source, enabled: false) }
                try store.ingest(documents, replacing: source)
                imported(source)
                UserDefaults.standard.set(ids.sorted(), forKey: "IrisAppleSelection-" + source.rawValue)
                status[source.rawValue] = "\(documents.count) imported · on this Mac"
            } catch is CancellationError { status[source.rawValue] = "Cancelled · existing knowledge kept" }
            catch { status[source.rawValue] = error.localizedDescription }
        }
    }

    private func reminderDocuments(ids: Set<String>) async throws -> [KnowledgeDocument] {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            throw IrisFailure.message("Allow Iris to read Reminders in System Settings, then retry.")
        }
        let lists = eventStore.calendars(for: .reminder).filter { ids.contains($0.calendarIdentifier) }
        guard lists.count == ids.count else {
            throw IrisFailure.message("A selected reminder list is no longer available. Reopen the connection and try again.")
        }
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
        guard let items = await withCheckedContinuation({ (continuation: CheckedContinuation<[EKReminder]?, Never>) in
            _ = eventStore.fetchReminders(matching: predicate) { continuation.resume(returning: $0) }
        }) else { throw IrisFailure.message("Iris couldn’t read the selected Reminders lists.") }
        return items.prefix(300).map { reminder in
            var details = ["List: " + reminder.calendar.title]
            if let due = reminder.dueDateComponents?.date { details.append("Due: " + due.formatted()) }
            if let notes = reminder.notes, !notes.isEmpty { details.append(notes) }
            return .init(externalID: reminder.calendarItemIdentifier, source: .appleReminders,
                         title: reminder.title ?? "Untitled reminder", body: details.joined(separator: "\n"),
                         updatedAt: reminder.lastModifiedDate ?? Date())
        }
    }
    func importCalendarEvents() {
        guard !selectedCalendars.isEmpty else { status[KnowledgeConnector.appleCalendar.rawValue] = "Select at least one calendar."; return }
        let selected = calendars.filter { selectedCalendars.contains($0.calendarIdentifier) }
        let now = Date(), until = Calendar.current.date(byAdding: .day, value: 30, to: Date())!
        let events = eventStore.events(matching: eventStore.predicateForEvents(withStart: now, end: until, calendars: selected))
        let documents = events.prefix(300).map { event in
            KnowledgeDocument(externalID: (event.eventIdentifier ?? UUID().uuidString) + "-\(event.startDate.timeIntervalSince1970)", source: .appleCalendar, title: event.title ?? "Untitled event", body: "\(event.startDate.formatted()) – \(event.endDate.formatted())\n\(event.location ?? "")\n\(event.notes ?? "")", updatedAt: event.lastModifiedDate ?? now)
        }
        do { try store.ingest(documents, replacing: .appleCalendar); UserDefaults.standard.set(selectedCalendars.sorted(), forKey: "IrisAppleCalendarSelection"); imported(.appleCalendar); status[KnowledgeConnector.appleCalendar.rawValue] = "\(documents.count) events imported · next 30 days" }
        catch { status[KnowledgeConnector.appleCalendar.rawValue] = error.localizedDescription }
    }
    private func importSocial(_ source: KnowledgeConnector) {
        let picker = NSOpenPanel(); picker.allowsMultipleSelection = true; picker.canChooseDirectories = false
        picker.allowedContentTypes = [.json, .javaScript, .plainText]
        picker.message = source == .x ? "Unzip your X archive first. Choose tweets.js or individual post JSON files. No JavaScript is executed. DMs are not supported." : "Choose individual exported chat JSON files. Only selected files are imported; ZIP files, full-account archives and media are not read."
        guard picker.runModal() == .OK else { return }
        let urls = Array(picker.urls.prefix(20)); busy = source
        task = Task {
            defer { busy = nil }
            do {
                var documents: [KnowledgeDocument] = []
                for url in urls {
                    try Task.checkCancellation()
                    let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
                    guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 10_000_000 else { throw IrisFailure.message("Choose export files no larger than 10 MB.") }
                    let prefix = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
                    documents += try SocialExportReader.read(Data(contentsOf: url), source: source, title: url.lastPathComponent).map { item in
                        var item = item; item.externalID = prefix + ":" + item.externalID; return item
                    }
                }
                guard documents.count <= 500 else { throw IrisFailure.message("Choose fewer export files: an import can contain at most 500 items.") }
                try Task.checkCancellation(); try store.ingest(documents)
                status[source.rawValue] = "\(documents.count) items imported locally · file snapshots, not live sync"
            } catch { status[source.rawValue] = error.localizedDescription }
        }
    }
    private func importFiles(_ source: KnowledgeConnector) {
        let picker = NSOpenPanel(); picker.allowsMultipleSelection = true; picker.canChooseDirectories = false
        picker.allowedContentTypes = [.pdf, .plainText, .sourceCode, .image, .json]
        picker.message = "Choose the documents Iris may keep in its local knowledge database."
        guard picker.runModal() == .OK else { return }
        let urls = Array(picker.urls.prefix(40)); busy = source
        task = Task {
            defer { busy = nil }
            do {
                var documents: [KnowledgeDocument] = []
                for url in urls {
                    try Task.checkCancellation()
                    let content = try await ContextReader.read(url: url)
                    documents.append(.init(externalID: SHA256.hash(data: Data(url.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined(), source: source, title: content.name, body: content.text, updatedAt: Date()))
                }
                try store.ingest(documents)
                status[source.rawValue] = "\(documents.count) documents imported locally"
            } catch { status[source.rawValue] = error.localizedDescription }
        }
    }
}

@MainActor
enum GoogleKnowledgeAPI {
    private static func data(_ raw: String, query: [String: String] = [:], token: String, session: URLSession) async throws -> Data {
        var url = URLComponents(string: raw)!; url.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: url.url!); request.timeoutInterval = 30; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard data.count < 8_000_000 else { throw IrisFailure.message("This Google response exceeds the import size limit.") }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let service = raw.contains("/calendar/") ? "calendar.googleapis.com" : raw.contains("/drive/") ? "drive.googleapis.com" : "gmail.googleapis.com"
            throw IrisFailure.message(GoogleImportDiagnostics.explanation(status: (response as? HTTPURLResponse)?.statusCode ?? 0, data: data, service: service))
        }
        return data
    }
    private static func json(_ raw: String, query: [String: String] = [:], token: String, session: URLSession) async throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: await data(raw, query: query, token: token, session: session)) as? [String: Any] else { throw IrisFailure.message("Google returned an invalid response.") }; return object
    }
    static func fetch(_ source: KnowledgeConnector, token: String, session: URLSession = .shared) async throws -> [KnowledgeDocument] {
        switch source {
        case .gmail:
            let listing = try await json("https://gmail.googleapis.com/gmail/v1/users/me/messages", query: ["maxResults": "30", "q": "in:inbox newer_than:30d"], token: token, session: session)
            var result: [KnowledgeDocument] = []
            for entry in listing["messages"] as? [[String: String]] ?? [] {
                try Task.checkCancellation(); guard let id = entry["id"] else { continue }
                let object = try await json("https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)", query: ["format": "full"], token: token, session: session)
                let payload = object["payload"] as? [String: Any] ?? [:], headers = payload["headers"] as? [[String: String]] ?? []
                func header(_ name: String) -> String { headers.first { $0["name"]?.lowercased() == name }?["value"] ?? "" }
                let body = plainText(payload)
                result.append(.init(externalID: id, source: .gmail, title: header("subject"), body: "From: \(header("from"))\nDate: \(header("date"))\n\(body.isEmpty ? (object["snippet"] as? String ?? "") : body)", updatedAt: Date(timeIntervalSince1970: (Double(object["internalDate"] as? String ?? "") ?? Date().timeIntervalSince1970 * 1000) / 1000)))
            }; return result
        case .drive:
            let listing = try await json("https://www.googleapis.com/drive/v3/files", query: ["pageSize": "25", "orderBy": "modifiedTime desc", "q": "trashed=false and (mimeType='text/plain' or mimeType='text/markdown' or mimeType='application/vnd.google-apps.document')", "fields": "files(id,name,mimeType,modifiedTime,size)"], token: token, session: session)
            var result: [KnowledgeDocument] = []
            for file in listing["files"] as? [[String: Any]] ?? [] {
                try Task.checkCancellation(); guard let id = file["id"] as? String else { continue }
                if let size = file["size"] as? String, (Int(size) ?? 0) > 1_000_000 { continue }
                let googleDoc = file["mimeType"] as? String == "application/vnd.google-apps.document"
                let bytes = try await data("https://www.googleapis.com/drive/v3/files/\(id)" + (googleDoc ? "/export" : ""), query: googleDoc ? ["mimeType": "text/plain"] : ["alt": "media"], token: token, session: session)
                guard let text = String(data: bytes, encoding: .utf8) else { continue }
                result.append(.init(externalID: id, source: .drive, title: file["name"] as? String ?? "Document", body: String(text.prefix(30000)), updatedAt: ISO8601DateFormatter().date(from: file["modifiedTime"] as? String ?? "") ?? Date()))
            }; return result
        case .googleCalendar:
            let formatter = ISO8601DateFormatter()
            let object = try await json("https://www.googleapis.com/calendar/v3/calendars/primary/events", query: ["timeMin": formatter.string(from: Date()), "timeMax": formatter.string(from: Date().addingTimeInterval(30 * 86400)), "singleEvents": "true", "orderBy": "startTime", "maxResults": "100"], token: token, session: session)
            return (object["items"] as? [[String: Any]] ?? []).filter { $0["status"] as? String != "cancelled" }.compactMap { event in
                guard let id = event["id"] as? String else { return nil }
                let start = event["start"] as? [String: String] ?? [:]
                return .init(externalID: id, source: .googleCalendar, title: event["summary"] as? String ?? "Untitled event", body: "\(start["dateTime"] ?? start["date"] ?? "")\n\(event["location"] as? String ?? "")\n\(event["description"] as? String ?? "")", updatedAt: formatter.date(from: event["updated"] as? String ?? "") ?? Date())
            }
        default: throw IrisFailure.message("This source is imported locally.")
        }
    }
    private static func plainText(_ payload: [String: Any]) -> String {
        if payload["mimeType"] as? String == "text/plain", let body = payload["body"] as? [String: Any], let raw = body["data"] as? String, let data = Data(base64URL: raw) { return String(data: data, encoding: .utf8) ?? "" }
        return (payload["parts"] as? [[String: Any]] ?? []).map { plainText($0) }.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}
