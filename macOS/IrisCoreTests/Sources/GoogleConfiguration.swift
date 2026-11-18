import Foundation
import AppKit
import UniformTypeIdentifiers
import Security

struct GoogleAppConfiguration: Codable {
    var clientID: String
    var clientSecret: String?
    var projectID: String?
    static func decodeDesktop(_ data: Data) throws -> Self {
        guard data.count < 100000,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let desktop = root["installed"] as? [String: Any],
              let id = desktop["client_id"] as? String,
              id.hasSuffix(".apps.googleusercontent.com") else {
            throw IrisFailure.message("Choose a Google OAuth Desktop app configuration. Web clients and API keys aren't supported.")
        }
        return Self(clientID: id, clientSecret: desktop["client_secret"] as? String, projectID: desktop["project_id"] as? String)
    }
    static func bundled(in bundle: Bundle = .main) throws -> Self? {
        guard let url = bundle.url(forResource: "GoogleOAuth", withExtension: "json") else { return nil }
        return try decodeDesktop(Data(contentsOf: url))
    }
    static func read(allowInteraction: Bool = true) throws -> Self? {
        // The shipped Desktop app registration is the default for every installation.
        // Native client registration is distributed with the app; user tokens never are.
        if !UserDefaults.standard.bool(forKey: "IrisGoogleRegistrationOverride"), let configuration = try bundled() { return configuration }
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.projectiris.google-registration", kSecAttrAccount as String: "desktop", kSecReturnData as String: true]
        if !allowInteraction { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data { return try JSONDecoder().decode(Self.self, from: data) }
        if status != errSecItemNotFound { throw IrisFailure.message("Google configuration couldn't be read from Keychain.") }
        guard let client = Bundle.main.object(forInfoDictionaryKey: "IRISGoogleClientID") as? String, !client.isEmpty else { return nil }
        return Self(clientID: client, clientSecret: Bundle.main.object(forInfoDictionaryKey: "IRISGoogleClientSecret") as? String, projectID: Bundle.main.object(forInfoDictionaryKey: "IRISGoogleProjectID") as? String)
    }
    static func useBundled() { UserDefaults.standard.set(false, forKey: "IrisGoogleRegistrationOverride") }
    @MainActor static func importFile() throws -> Bool {
        let picker = NSOpenPanel(); picker.allowedContentTypes = [.json]; picker.message = "Choose Iris's Google OAuth Desktop client JSON downloaded from Google Cloud. This is an app registration, not an API key."
        guard picker.runModal() == .OK, let url = picker.url else { return false }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let config = try decodeDesktop(Data(contentsOf: url))
        let encoded = try JSONEncoder().encode(config)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.projectiris.google-registration", kSecAttrAccount as String: "desktop"]
        let result = SecItemUpdate(query as CFDictionary, [kSecValueData as String: encoded] as CFDictionary)
        if result == errSecItemNotFound { var add = query; add[kSecValueData as String] = encoded; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly; guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw IrisFailure.message("Google registration couldn't be saved securely.") } }
        else if result != errSecSuccess { throw IrisFailure.message("Google registration couldn't be updated.") }
        UserDefaults.standard.set(true, forKey: "IrisGoogleRegistrationOverride")
        return true
    }
}
