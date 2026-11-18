import Foundation

enum KnowledgeConnector: String, Codable, CaseIterable, Identifiable, Sendable {
    case gmail, drive, googleCalendar, googleChat, googleTasks
    case appleCalendar, appleNotes, appleReminders, appleMessages, appleMail, files, whatsapp
    case github, notion, slack, todoist, linear
    case instagram, x, telegram
    var id: String { rawValue }
    var name: String { switch self {
        case .gmail: "Gmail"; case .drive: "Google Drive"; case .googleCalendar: "Google Calendar"; case .googleChat: "Google Chat"; case .googleTasks: "Google Tasks"
        case .appleCalendar: "Apple Calendar"; case .appleNotes: "Apple Notes"; case .appleReminders: "Apple Reminders"; case .appleMessages: "Apple Messages"; case .appleMail: "Apple Mail"; case .files: "Files & documents"; case .whatsapp: "WhatsApp"
        case .github: "GitHub"; case .notion: "Notion"; case .slack: "Slack"; case .todoist: "Todoist"; case .linear: "Linear"
        case .instagram: "Instagram"; case .x: "X"; case .telegram: "Telegram"
    } }
    var symbol: String { switch self {
        case .gmail: "envelope"; case .drive: "externaldrive"; case .googleCalendar, .appleCalendar: "calendar"; case .appleNotes: "note.text"; case .appleReminders: "checklist"; case .appleMessages: "message"; case .appleMail: "envelope"; case .files: "folder"
        case .googleChat, .slack: "bubble.left.and.bubble.right"; case .whatsapp: "phone.bubble"; case .googleTasks, .todoist: "checklist"
        case .github: "curlybraces"; case .notion: "doc.richtext"; case .linear: "list.bullet.rectangle"; case .instagram: "camera"; case .x: "text.bubble"; case .telegram: "paperplane"
    } }
    var group: String {
        switch self {
        case .gmail, .drive, .googleCalendar, .googleChat, .googleTasks: "Google"
        case .appleCalendar, .appleNotes, .appleReminders, .appleMessages, .appleMail: "Apple apps"
        case .files, .whatsapp: "On this Mac"
        case .github, .notion, .slack, .todoist, .linear: "Apps · API connections"
        case .instagram, .x, .telegram: "Social · file imports"
        }
    }
    var detail: String { switch self {
        case .gmail: "Recent inbox messages · read only"; case .drive: "Recent text files and Google Docs · read only"; case .googleCalendar: "Upcoming events · read only"
        case .googleChat: "One space · up to 100 text messages · Google sign-in"; case .googleTasks: "Default task list · up to 100 active tasks · Google sign-in"
        case .appleCalendar: "Choose calendars synced to this Mac"; case .appleNotes: "Text from folders you choose · skips locked notes"; case .appleReminders: "Open reminders from lists you choose"; case .appleMessages: "Recent text from conversations you choose · Full Disk Access"; case .appleMail: "Inbox text from Mail accounts you choose"; case .files: "Choose documents to keep in your knowledge"; case .whatsapp: "Choose chats from WhatsApp on this Mac · text only"
        case .github: "One repository · 30 open issues/PRs · API token"
        case .notion: "One shared page · top-level text · integration token"
        case .slack: "One channel · 15 recent messages, no threads · API token"
        case .todoist: "Up to 50 active tasks · optional project · API token"
        case .linear: "Up to 30 assigned issues · personal API key"
        case .instagram: "Import selected chat JSON files · no account sign-in"
        case .x: "Import up to 100 posts per archive file · no account sign-in"
        case .telegram: "Import individual chat JSON exports · no account sign-in"
    } }
    var scope: String? { switch self {
        case .gmail: "https://www.googleapis.com/auth/gmail.readonly"; case .drive: "https://www.googleapis.com/auth/drive.readonly"; case .googleCalendar: "https://www.googleapis.com/auth/calendar.events.readonly"
        case .googleChat: "https://www.googleapis.com/auth/chat.messages.readonly"; case .googleTasks: "https://www.googleapis.com/auth/tasks.readonly"
        default: nil
    } }
}
struct KnowledgeDocument: Identifiable, Codable, Equatable, Sendable {
    var externalID: String
    var source: KnowledgeConnector
    var title: String
    var body: String
    var updatedAt: Date
    var id: String { source.rawValue + ":" + externalID }
}
enum KnowledgeRetrieval {
    static func relevant(to query: String, documents: [KnowledgeDocument], enabled: Set<String>, limit: Int = 5) -> [KnowledgeDocument] {
        let terms = Set(query.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 && !["the", "and", "what", "with", "that", "this", "can", "you", "for", "about", "please"].contains($0) })
        guard !terms.isEmpty else { return [] }
        return documents.filter { enabled.contains($0.source.rawValue) }.compactMap { document -> (KnowledgeDocument, Int)? in
            let title = document.title.lowercased(), body = document.body.lowercased()
            let score = terms.reduce(0) { $0 + (title.contains($1) ? 4 : 0) + (body.contains($1) ? 1 : 0) }
            return score > 0 ? (document, score) : nil
        }.sorted { $0.1 == $1.1 ? $0.0.updatedAt > $1.0.updatedAt : $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}

/// Recovery guidance contains no provider response payloads or account identifiers.
enum GoogleAuthorizationHelp {
    static func message(for code: String) -> String {
        switch code {
        case "access_denied": return "Google blocked or declined access. Select the exact account listed in this project's Google Auth Platform → Audience → Test users. Check project, testing status and requested scopes. A Workspace administrator may also block access. Return to Iris and reconnect after fixing Google settings."
        case "org_internal": return "This Google app is restricted to its organization. Use an eligible organization account or change the app audience in Google Cloud."
        case "invalid_scope": return "Google rejected a requested permission. Check this project's OAuth Data Access configuration and enabled APIs."
        default: return "Google sign-in wasn't completed. Check the browser error, then reconnect. Your existing local knowledge is unchanged."
        }
    }
}

/// Interpret Google's structured API errors without retaining raw response bodies.
enum GoogleImportDiagnostics {
    static func explanation(status: Int, data: Data, service: String) -> String {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let error = root?["error"] as? [String: Any] ?? [:]
        let details = error["details"] as? [[String: Any]] ?? []
        let info = details.first { ($0["@type"] as? String)?.hasSuffix("google.rpc.ErrorInfo") == true }
        let legacy = error["errors"] as? [[String: Any]] ?? []
        let reason = info?["reason"] as? String ?? legacy.first?["reason"] as? String ?? error["status"] as? String ?? "UNKNOWN"
        let safeReason = String(reason.filter { $0.isLetter || $0.isNumber || $0 == "_" }.prefix(80))
        let name: String
        switch service {
        case "gmail.googleapis.com": name = "Gmail API"
        case "drive.googleapis.com", "www.googleapis.com": name = "Google Drive API"
        case "calendar.googleapis.com", "www.googleapis.com/calendar": name = "Google Calendar API"
        default: name = "Google API"
        }
        let recovery: String
        switch reason {
        case "SERVICE_DISABLED", "API_DISABLED", "accessNotConfigured":
            recovery = "\(name) is disabled in Iris's Google Cloud project. Enable it in Google Cloud → APIs & Services → Library, wait for activation, then import again. Signing in again is not required."
        case "ACCESS_TOKEN_SCOPE_INSUFFICIENT", "insufficientPermissions":
            recovery = "Google did not grant this source's read permission. Reconnect this source and approve its requested permission."
        case "domainPolicy", "ORG_RESTRICTION_VIOLATION":
            recovery = "Your Google Workspace policy blocks Iris. Ask your administrator to allow this app and source."
        case "rateLimitExceeded", "userRateLimitExceeded", "dailyLimitExceeded", "RATE_LIMIT_EXCEEDED", "QUOTA_EXCEEDED":
            recovery = "Google's request quota was reached. Wait before importing again or review the project's API quota."
        case "BILLING_DISABLED":
            recovery = "Google requires billing configuration for this request. Review the project in Google Cloud before retrying."
        default:
            recovery = status == 401 ? "Google sign-in expired or was revoked. Reconnect this source." : "Google rejected access to this source. Check its API status, granted permissions and account policy."
        }
        return "\(recovery) (HTTP \(status), \(safeReason.isEmpty ? "UNKNOWN" : safeReason)). Existing knowledge was kept."
    }
}
