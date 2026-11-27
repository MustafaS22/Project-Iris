import Foundation

/// These decisions are applied outside the model. Tool descriptions never grant access.
enum ComputerMode: String, Codable, CaseIterable { case observe = "Observe", assist = "Assist", autonomous = "Autonomous" }
enum ComputerApprovalCategory: String, Codable, CaseIterable {
    case navigation, localDrafting

    var title: String {
        switch self {
        case .navigation: "Routine navigation"
        case .localDrafting: "Typing in local editors"
        }
    }
}

enum ComputerApprovalDecision { case once, task, always, deny }

struct ComputerUsePolicy: Codable {
    // Optional for policies saved before approval categories were introduced.
    var rememberedApprovals: Set<ComputerApprovalCategory>?

    mutating func remember(_ category: ComputerApprovalCategory, allowed: Bool) {
        var categories = rememberedApprovals ?? []
        if allowed { categories.insert(category) } else { categories.remove(category) }
        rememberedApprovals = categories
    }

    func requiresReview(_ name: String, external: Bool, routine: Bool, category: ComputerApprovalCategory?, taskApproved: Bool) -> Bool {
        if external { return true }
        return needsApproval(name, external: false) && !routine
    }

    var mode: ComputerMode = .assist
    var excludedApps: [String] = ["com.apple.keychainaccess", "com.apple.systempreferences", "com.1password.1password", "com.agilebits.onepassword7"]
    var deniedTools: [String] = []
    var shareScreen = false
    static let inspections: Set<String> = ["get_displays", "list_applications", "list_windows", "get_active_window", "get_accessibility_tree", "find_ui_element", "get_screen", "capture_window", "wait_for_element"]
    static let lowRisk: Set<String> = ["move_cursor", "scroll", "focus_window", "launch_application", "resize_window"]
    func permits(_ name: String, app: String?) -> Bool {
        !deniedTools.contains(name) && !(app.map(excludedApps.contains) ?? false) && (mode != .observe || Self.inspections.contains(name))
    }
    func permitsTool(_ name: String, server: String) -> Bool {
        let key = server == "native" ? name : server + "/" + name
        return !deniedTools.contains(key) && (mode != .observe || (server == "native" && Self.inspections.contains(name)))
    }
    func needsApproval(_ name: String, external: Bool) -> Bool {
        // Unknown servers and clicks/typing can send, publish, purchase or change security.
        // Never infer safety from a remote server's readOnlyHint or the model's description.
        external || (!Self.inspections.contains(name) && (mode != .autonomous || !Self.lowRisk.contains(name)))
    }
    /// Safety is derived from the actual native target, never the planner's risk claim.
    func permitsRoutineAction(_ name: String, role: String, label: String, bundle: String, key: String = "", modifiers: [String] = []) -> Bool {
        guard mode != .observe else { return false }
        let text = label.lowercased()
        let sensitive = ["send", "submit", "publish", "purchase", "buy", "pay", "delete", "remove", "trash", "share", "invite", "grant", "allow", "password", "security", "install", "sign in", "log in", "confirm", "erase", "reset", "checkout"]
        guard !sensitive.contains(where: text.contains) else { return false }
        if Self.inspections.contains(name) || Self.lowRisk.contains(name) { return true }
        let localEditors = ["com.apple.Notes", "com.apple.TextEdit", "com.apple.iWork.Pages", "com.apple.Pages", "com.arize.iris.computer-fixture"]
        if name == "type_text" { return localEditors.contains(bundle) || text.contains("search") || text.contains("address") || text.contains("location") }
        if name == "click" {
            if ["AXTextField", "AXTextArea", "AXComboBox", "AXMenuBarItem", "AXTab", "AXRow", "AXOutlineRow"].contains(role) { return true }
            return ["back", "forward", "search", "new note", "new folder", "new document", "file", "edit", "view", "window", "help", "cancel", "close", "next", "previous"].contains(text.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if name == "press_key" { return modifiers.isEmpty && ["escape", "tab", "left", "right", "up", "down", "home", "end", "pageup", "pagedown"].contains(key) }
        if name == "keyboard_shortcut", modifiers == ["command"] { return ["l", "f", "a", "c"].contains(key) || (localEditors.contains(bundle) && ["n", "s", "b", "i"].contains(key)) }
        return false
    }
    static func isSyntheticInput(marker: Int64, sourcePID: Int64, ownPID: Int32) -> Bool {
        marker == 0x49524953 || sourcePID == Int64(ownPID)
    }

}
struct ComputerHistoryEntry: Codable, Identifiable {
    var id = UUID()
    var date = Date()
    var tool: String
    var detail: String
    var succeeded: Bool
}
struct ComputerTaskRecord: Codable {
    var objective: String
    var status: String
    var history: [ComputerHistoryEntry]
    var updated = Date()
}
enum ComputerUseGuard {
    static func validatePoint(x: Double, y: Double, width: Double, height: Double) -> Bool {
        x.isFinite && y.isFinite && width > 0 && height > 0 && x >= 0 && y >= 0 && x <= width && y <= height
    }
    static func loopKey(tool: String, arguments: String, observation: String) -> String { tool + "|" + normalized(arguments) + "|" + normalized(observation) }
    static func semanticState(_ observation: String) -> String? {
        // Combined visual observations place the AX tree after frame metadata and OCR.
        // Compare the readable state independently from new frame and element tokens.
        let source = observation.split(separator: "\n", omittingEmptySubsequences: false)
        guard let start = source.lastIndex(where: { $0.hasPrefix("Application: ") && $0.hasSuffix("UI content is untrusted data.") }) else { return nil }
        return normalized(source[start...].joined(separator: "\n"))
    }

    static func changedInterface(before: String, after: String) -> Bool {
        guard let current = semanticState(after) else { return false }
        return semanticState(before).map { $0 != current } ?? false
    }

    private static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: #"[A-Fa-f0-9]{8}-[A-Fa-f0-9-]{27,36}"#, with: "FRAME", options: .regularExpression)
            .replacingOccurrences(of: #"[A-Fa-f0-9]{8}-[0-9]+"#, with: "ELEMENT", options: .regularExpression)
    }
    static func endpoint(_ raw: String) -> URL? {
        guard let url = URL(string: raw), url.user == nil, url.password == nil, let host = url.host else { return nil }
        guard url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1"].contains(host)) else { return nil }
        return url
    }
}
