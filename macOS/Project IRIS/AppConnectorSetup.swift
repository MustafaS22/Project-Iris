import SwiftUI
import Security

/// API secrets stay in Keychain, never in preferences, chat context, or diagnostic messages.
enum AppConnectorVault {
    private static func query(_ source: KnowledgeConnector) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.projectiris.connections", kSecAttrAccount as String: source.rawValue] }
    static func read(_ source: KnowledgeConnector, allowInteraction: Bool = true) throws -> String? {
        var q = query(source); if !allowInteraction { q[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else { throw IrisFailure.message("The connection token couldn't be read from Keychain.") }
        return String(data: data, encoding: .utf8)
    }
    static func save(_ raw: String, source: KnowledgeConnector) throws {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, token.count <= 4000, !token.contains(where: \.isWhitespace) else { throw IrisFailure.message("Enter a valid token without whitespace.") }
        let data = Data(token.utf8), q = query(source)
        var status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound { var add = q; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; status = SecItemAdd(add as CFDictionary, nil) }
        guard status == errSecSuccess else { throw IrisFailure.message("The connection token couldn't be saved.") }
    }
    static func delete(_ source: KnowledgeConnector) throws {
        let status = SecItemDelete(query(source) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw IrisFailure.message("The token couldn't be removed from Keychain.") }
    }
}

struct AppConnectorSetup: View {
    @ObservedObject var iris: IrisOrchestrator
    let source: KnowledgeConnector
    @Environment(\.dismiss) private var dismiss
    @State private var target = ""
    @State private var token = ""
    @State private var saved = false
    @State private var error: String?
    private var needsToken: Bool { AppKnowledgeAPI.tokenSources.contains(source) }
    private var targetTitle: String? { switch source { case .github: "Repository · owner/name"; case .notion: "Notion page ID"; case .slack: "Slack channel ID"; case .todoist: "Project ID · optional"; case .googleChat: "Google Chat space ID"; default: nil } }
    private var help: String { switch source {
        case .github: "Use a fine-grained token with read access to issues and pull requests for the chosen repository. Imports open issue/PR text only; no code or comments."
        case .notion: "Create a read-content integration, share the chosen page with it, and copy its page ID from the page link. Imports at most 100 top-level blocks; nested pages, nested blocks and media are not imported."
        case .slack: "Use a user or bot token with history access for this channel, and invite the app if needed. Find the channel ID in channel details or its copied link. Imports one page of 15 messages; no thread replies."
        case .todoist: "Use your Todoist API token. Choose a project ID to limit the import, or leave it blank for up to 50 active tasks."
        case .linear: "Use a personal API key with read permission. Imports up to 30 issues assigned to the key's user."
        case .googleChat: "Enter the space ID from your Chat link. Enable Google Chat API for Iris's Google project. Your organization may require administrator approval. Imports text from one space you belong to."
        case .googleTasks: "Uses Google sign-in and the read-only Tasks scope. Enable Google Tasks API for Iris's Google project. Imports up to 100 active tasks from your default list."
        default: ""
    } }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { SourceLogo(source: source); Text(source.name).font(.system(size: 27, weight: .semibold)); Spacer(); Button("Done") { dismiss() }.buttonStyle(IrisActionStyle()) }
            Text(source.detail).font(.callout).foregroundStyle(IrisDesign.secondary)
            Text(help).font(.system(size: 14)).lineSpacing(4).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            if let targetTitle { IrisFormField(title: targetTitle, prompt: targetTitle, text: $target) }
            if needsToken {
                Text(saved ? "Token saved in Keychain. Leave blank to keep it." : "Your API token").font(.caption).foregroundStyle(IrisDesign.secondary)
                SecureField("API token", text: $token).textFieldStyle(IrisTextFieldStyle())
            }
            Label("Manual, read-only imports. No messages, posts or tasks are changed. Imported content stays local unless Use in answers is enabled.", systemImage: "lock.shield").font(.caption).foregroundStyle(IrisDesign.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            if let status = iris.connections.status[source.rawValue] { Text(status).font(.caption).foregroundStyle(IrisDesign.secondary) }
            HStack {
                if iris.connections.busy == source { ProgressView().controlSize(.small); Button("Cancel") { iris.connections.cancel() } }
                else {
                    Button(needsToken ? "Save & import" : "Sign in & import") { connect() }.buttonStyle(IrisActionStyle(primary: true)).disabled(iris.connections.busy != nil)
                    Spacer()
                    Button("Disconnect", role: .destructive) {
                        do { try iris.knowledge.remove(source); if needsToken { try AppConnectorVault.delete(source) }; UserDefaults.standard.removeObject(forKey: "IrisConnectorTarget-" + source.rawValue); token = ""; saved = false; target = ""; error = nil; iris.connections.status[source.rawValue] = "Disconnected · local imported items removed" }
                        catch { self.error = error.localizedDescription }
                    }.buttonStyle(.plain).disabled(iris.connections.busy != nil)
                }
            }
        }.padding(28).frame(width: 590).background(IrisBackdrop(accent: iris.accent)).foregroundStyle(IrisDesign.text).preferredColorScheme(.dark)
            .onAppear { target = UserDefaults.standard.string(forKey: "IrisConnectorTarget-" + source.rawValue) ?? ""; if needsToken { saved = (try? AppConnectorVault.read(source)) != nil } }
    }
    private func connect() {
        do {
            let current = UserDefaults.standard.string(forKey: "IrisConnectorTarget-" + source.rawValue) ?? ""
            let credential = needsToken ? (token.isEmpty ? try AppConnectorVault.read(source) ?? "" : token.trimmingCharacters(in: .whitespacesAndNewlines)) : "validation"
            _ = try AppKnowledgeAPI.request(source: source, target: target, token: credential)
            if !token.isEmpty || current != target { try iris.knowledge.setSharing(source, enabled: false) }
            if needsToken, !token.isEmpty { try AppConnectorVault.save(token, source: source); token = ""; saved = true }
            UserDefaults.standard.set(target.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "IrisConnectorTarget-" + source.rawValue)
            error = nil; iris.connections.connect(source)
        } catch { self.error = error.localizedDescription }
    }
}
