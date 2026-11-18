import SwiftUI
import EventKit
import ContactsUI
import UniformTypeIdentifiers
import PDFKit

struct IrisReference: Codable, Identifiable {
    var id = UUID()
    var name: String
    var text: String
    var enabled = true
}

@MainActor final class IrisConnections: ObservableObject {
    static let shared = IrisConnections()
    let store = EKEventStore()
    @Published var calendars: [EKCalendar] = []
    @Published var reminderLists: [EKCalendar] = []
    @Published var references: [IrisReference] = []
    @Published var error: String?
    private let file = URL.documentsDirectory.appending(path: "references.json")
    init() {
        if let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode([IrisReference].self, from: data) { references = saved }
        refresh()
    }
    func refresh() {
        calendars = EKEventStore.authorizationStatus(for: .event) == .fullAccess ? store.calendars(for: .event) : []
        reminderLists = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess ? store.calendars(for: .reminder) : []
    }
    func connectCalendar() async {
        do { guard try await store.requestFullAccessToEvents() else { throw IrisError.message("Calendar access wasn’t granted. You can change it in iPhone Settings.") }; refresh() }
        catch { self.error = error.localizedDescription }
    }
    func connectReminders() async {
        do { guard try await store.requestFullAccessToReminders() else { throw IrisError.message("Reminders access wasn’t granted. You can change it in iPhone Settings.") }; refresh() }
        catch { self.error = error.localizedDescription }
    }
    func selection(_ key: String) -> Set<String> { Set((UserDefaults.standard.array(forKey: key) as? [String]) ?? []) }
    func toggle(_ identifier: String, key: String) {
        var ids = selection(key)
        if ids.contains(identifier) { ids.remove(identifier) } else { ids.insert(identifier) }
        UserDefaults.standard.set(Array(ids), forKey: key); objectWillChange.send()
    }
    func add(name: String, text: String) {
        guard references.count < 12, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { error = "Use up to 12 references with readable text."; return }
        references.append(.init(name: String(name.prefix(150)), text: String(text.prefix(5_000))))
        save()
    }
    func setEnabled(_ id: UUID, enabled: Bool) {
        if let index = references.firstIndex(where: { $0.id == id }) { references[index].enabled = enabled; save() }
    }
    func remove(_ id: UUID) { references.removeAll { $0.id == id }; save() }
    private func save() {
        if let data = try? JSONEncoder().encode(references) { try? data.write(to: file, options: [.atomic, .completeFileProtection]) }
    }
    func context() async -> String {
        var chunks: [String] = []
        let calendarIDs = selection("IrisCalendarIDs")
        let chosen = calendars.filter { calendarIDs.contains($0.calendarIdentifier) }
        if !chosen.isEmpty, EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let end = Calendar.current.date(byAdding: .day, value: 7, to: .now)!
            let events = store.events(matching: store.predicateForEvents(withStart: .now, end: end, calendars: chosen))
            let text = events.prefix(25).map { "\($0.startDate.formatted()) · \($0.title ?? "Event")" }.joined(separator: "\n")
            chunks.append("Selected calendars, next 7 days:\n" + text)
        }
        let reminderIDs = selection("IrisReminderIDs")
        let lists = reminderLists.filter { reminderIDs.contains($0.calendarIdentifier) }
        if !lists.isEmpty, EKEventStore.authorizationStatus(for: .reminder) == .fullAccess {
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: lists)
            let reminders: [EKReminder] = await withCheckedContinuation { continuation in store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) } }
            chunks.append("Selected incomplete reminders:\n" + reminders.prefix(30).map { $0.title ?? "Reminder" }.joined(separator: "\n"))
        }
        for reference in references where reference.enabled { chunks.append("Selected reference: \(reference.name)\n\(reference.text)") }
        return String(chunks.joined(separator: "\n\n").prefix(12_000))
    }
    func importFile(_ url: URL) {
        let allowed = url.startAccessingSecurityScopedResource()
        defer { if allowed { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size < 8_000_000 else { throw IrisError.message("Choose a document smaller than 8 MB.") }
            let text: String
            if url.pathExtension.lowercased() == "pdf" { text = PDFDocument(url: url)?.string ?? "" }
            else { text = try String(contentsOf: url, encoding: .utf8) }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw IrisError.message("No readable text was found. Scanned PDFs need OCR first.") }
            add(name: url.lastPathComponent, text: text)
        } catch { self.error = error.localizedDescription }
    }
}

struct IrisConnectionsView: View {
    @ObservedObject var connections = IrisConnections.shared
    @State private var chooseContacts = false
    @State private var chooseFile = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Bring a little context.").font(.title2.weight(.semibold))
            Text("Only checked calendars, lists and references are sent to your selected AI provider when you ask a question. Iris reads Calendar and Reminders; it does not edit them. Uncheck a source to stop sharing it.")
                .font(.subheadline).foregroundStyle(.secondary)
            source("Calendar", symbol: "calendar", color: .red) {
                Button("Connect Calendar") { Task { await connections.connectCalendar() } }
                ForEach(connections.calendars, id: \.calendarIdentifier) { calendar in
                    Toggle(calendar.title, isOn: Binding(get: { connections.selection("IrisCalendarIDs").contains(calendar.calendarIdentifier) }, set: { _ in connections.toggle(calendar.calendarIdentifier, key: "IrisCalendarIDs") }))
                }
            }
            source("Reminders", symbol: "checklist", color: .blue) {
                Button("Connect Reminders") { Task { await connections.connectReminders() } }
                ForEach(connections.reminderLists, id: \.calendarIdentifier) { list in
                    Toggle(list.title, isOn: Binding(get: { connections.selection("IrisReminderIDs").contains(list.calendarIdentifier) }, set: { _ in connections.toggle(list.calendarIdentifier, key: "IrisReminderIDs") }))
                }
            }
            source("Selected contacts & documents", symbol: "folder.fill", color: IrisStyle.accent) {
                Text("Choose individual contacts or readable PDF/text files. Iris cannot browse all your contacts, messages, Notes, WhatsApp, or Mail on iOS.").font(.caption).foregroundStyle(.secondary)
                HStack { Button("Choose contacts") { chooseContacts = true }; Spacer(); Button("Add file") { chooseFile = true } }
                ForEach(connections.references) { reference in
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(reference.name, isOn: Binding(get: { reference.enabled }, set: { connections.setEnabled(reference.id, enabled: $0) }))
                        HStack {
                            Text(String(reference.text.prefix(90))).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Spacer()
                            Button(role: .destructive) { connections.remove(reference.id) } label: { Image(systemName: "trash") }.accessibilityLabel("Remove " + reference.name)
                        }
                    }
                }
            }
            if let error = connections.error { Text(error).font(.caption).foregroundStyle(.orange) }
        }
        .onAppear { connections.refresh() }
        .sheet(isPresented: $chooseContacts) { IrisContactPicker { contacts in
            for contact in contacts {
                let name = CNContactFormatter.string(from: contact, style: .fullName) ?? "Selected contact"
                let emails = contact.isKeyAvailable(CNContactEmailAddressesKey) ? contact.emailAddresses.map { $0.value as String } : []
                let phones = contact.isKeyAvailable(CNContactPhoneNumbersKey) ? contact.phoneNumbers.map { $0.value.stringValue } : []
                let details = ([name] + emails + phones).joined(separator: "\n")
                connections.add(name: name, text: details)
            }
        } }
        .fileImporter(isPresented: $chooseFile, allowedContentTypes: [.plainText, .pdf]) { result in
            switch result { case .success(let url): connections.importFile(url); case .failure(let error): connections.error = error.localizedDescription }
        }
    }
    private func source<Content: View>(_ title: String, symbol: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(color)
            content()
        }.padding(18).background(IrisStyle.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct IrisContactPicker: UIViewControllerRepresentable {
    var selected: ([CNContact]) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController(); picker.delegate = context.coordinator; return picker
    }
    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}
    final class Coordinator: NSObject, CNContactPickerDelegate {
        let owner: IrisContactPicker
        init(_ owner: IrisContactPicker) { self.owner = owner }
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) { owner.selected(contacts); owner.dismiss() }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) { owner.dismiss() }
    }
}
