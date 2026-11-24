import Foundation

/// These decisions are applied outside the model. Tool descriptions never grant access.
enum ComputerMode: String, Codable, CaseIterable { case observe = "Observe", assist = "Assist", autonomous = "Autonomous" }
struct ComputerUsePolicy: Codable {
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
