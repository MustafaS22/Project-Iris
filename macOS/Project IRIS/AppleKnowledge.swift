import AppKit
import Foundation

struct AppleKnowledgeSelection: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    var detail = ""
}

extension KnowledgeConnector {
    var usesAppleSelection: Bool {
        switch self {
        case .appleNotes, .appleMessages, .appleReminders, .appleMail: true
        default: false
        }
    }
    var appleSelectionLabel: String {
        switch self {
        case .appleNotes: "folders"
        case .appleMessages: "conversations"
        case .appleReminders: "lists"
        case .appleMail: "inboxes"
        default: "sources"
        }
    }
}

@MainActor enum AppleAutomationKnowledge {
    // Read-only scripts. All values returned by apps are descriptors, never executable code.
    private static func run(_ source: String, app: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw IrisFailure.message("Iris couldn’t prepare the \(app) connection.")
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            switch error[NSAppleScript.errorNumber] as? Int {
            case -1743, -1744:
                throw IrisFailure.message("Allow Iris to access \(app) in System Settings → Privacy & Security → Automation, then retry.")
            case -1712:
                throw IrisFailure.message("\(app) didn’t respond in time. Open \(app), then retry.")
            default:
                throw IrisFailure.message("Iris couldn’t read \(app). Open \(app) and make sure your account is available, then retry.")
            }
        }
        return result
    }

    private static func rows(_ value: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        guard value.numberOfItems > 0 else { return [] }
        return (1...value.numberOfItems).compactMap { value.atIndex($0) }
    }
    private static func literal(_ value: String) throws -> String {
        guard !value.isEmpty, value.utf8.count < 2048,
              value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else {
            throw IrisFailure.message("This item is no longer available. Refresh the list and try again.")
        }
        return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func choices(for source: KnowledgeConnector) throws -> [AppleKnowledgeSelection] {
        let notes = source == .appleNotes
        let result = try run(notes ? notesFolders : mailAccounts, app: notes ? "Notes" : "Mail")
        var seen = Set<String>()
        return rows(result).compactMap { row in
            guard let id = row.atIndex(1)?.stringValue, !id.isEmpty, seen.insert(id).inserted,
                  let name = row.atIndex(2)?.stringValue else { return nil }
            return .init(id: id, title: name, detail: row.atIndex(3)?.stringValue ?? "")
        }
    }

    static func documents(for source: KnowledgeConnector, selected: [AppleKnowledgeSelection]) throws -> [KnowledgeDocument] {
        let notes = source == .appleNotes
        let limit = notes ? 60 : 30
        let perSelection = max(1, limit / max(1, selected.count))
        var documents: [KnowledgeDocument] = []
        for item in selected {
            try Task.checkCancellation()
            let id = try literal(item.id)
            let result = try run(notes ? notesContents(folderID: id, limit: perSelection) : mailContents(accountID: id, limit: perSelection), app: notes ? "Notes" : "Mail")
            documents += rows(result).compactMap { row in
                guard let id = row.atIndex(1)?.stringValue,
                      let raw = row.atIndex(3)?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !raw.isEmpty else { return nil }
                let title = row.atIndex(2)?.stringValue ?? (notes ? "Untitled note" : "No subject")
                let date = row.atIndex(4)?.dateValue ?? Date()
                let sender = row.atIndex(5)?.stringValue
                let body = sender.map { "From: \($0)\nReceived: \(date.formatted())\n\n\(raw)" } ?? raw
                return .init(externalID: "direct:" + item.id + ":" + id, source: source, title: title, body: body, updatedAt: date)
            }
        }
        return documents
    }

    private static let notesFolders = """
    on addFolders(theFolders, parentName, depth, outputRows)
        if depth > 8 then return
        tell application id "com.apple.Notes"
            repeat with folderRef in theFolders
                if (count of outputRows) ≥ 400 then return
                set folderName to name of folderRef
                set end of outputRows to {id of folderRef, folderName, parentName}
                my addFolders(folders of folderRef, parentName & " / " & folderName, depth + 1, outputRows)
            end repeat
        end tell
    end addFolders
    with timeout of 12 seconds
        tell application id "com.apple.Notes"
            set outputRows to {}
            repeat with accountRef in every account
                my addFolders(folders of accountRef, name of accountRef, 0, outputRows)
            end repeat
            return outputRows
        end tell
    end timeout
    """

    private static func notesContents(folderID: String, limit: Int) -> String { """
    with timeout of 12 seconds
        tell application id "com.apple.Notes"
            set outputRows to {}
            set noteRefs to notes of folder id \(folderID)
            repeat with noteRef in noteRefs
                if (count of outputRows) ≥ \(limit) then exit repeat
                if password protected of noteRef is false then
                    set noteText to plaintext of noteRef
                    if noteText is not missing value and noteText is not "" then
                        if (length of noteText) > 18000 then set noteText to text 1 thru 18000 of noteText
                        set end of outputRows to {id of noteRef, name of noteRef, noteText, modification date of noteRef}
                    end if
                end if
            end repeat
            return outputRows
        end tell
    end timeout
    """ }

    private static let mailAccounts = """
    with timeout of 12 seconds
        tell application id "com.apple.mail"
            set outputRows to {}
            repeat with accountRef in every account
                if enabled of accountRef is true then set end of outputRows to {id of accountRef, name of accountRef, "Inbox"}
            end repeat
            return outputRows
        end tell
    end timeout
    """

    private static func mailContents(accountID: String, limit: Int) -> String { """
    with timeout of 12 seconds
        tell application id "com.apple.mail"
            set outputRows to {}
            set inboxRef to inbox of account id \(accountID)
            set total to count of messages of inboxRef
            if total > \(limit) then set total to \(limit)
            if total = 0 then return outputRows
            set messageRefs to messages 1 thru total of inboxRef
            repeat with messageRef in messageRefs
                set messageText to content of messageRef as text
                if (length of messageText) > 14000 then set messageText to text 1 thru 14000 of messageText
                set end of outputRows to {(id of messageRef) as text, subject of messageRef, messageText, date received of messageRef, sender of messageRef}
            end repeat
            return outputRows
        end tell
    end timeout
    """ }
}
