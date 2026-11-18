import Foundation
import Security

enum GeminiSpeechVault {
    private static let service = "com.projectiris.gemini-speech"
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "api-key"] }
    static func readAsync() async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try read(allowInteraction: false)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }
    static func read(allowInteraction: Bool = true) throws -> String? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        if !allowInteraction { request[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var result: CFTypeRef?; let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = result as? Data else { throw IrisFailure.message("The Gemini voice key couldn't be read from Keychain.") }
        return String(data: bytes, encoding: .utf8)
    }
    static func save(_ value: String) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.count >= 20, !key.contains(where: \.isWhitespace) else { throw IrisFailure.message("Enter a Gemini API key from Google AI Studio.") }
        let bytes = Data(key.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = bytes; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw IrisFailure.message("The Gemini voice key couldn't be saved securely.") }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw IrisFailure.message("The Gemini voice key couldn't be removed.") }
    }
}
@MainActor enum GeminiSpeechService {
    static func credential(auth: String) async throws -> GeminiSpeechCredential {
        try Task.checkCancellation()
        let credential: GeminiSpeechCredential
        if auth == "account" {
            let token = try await AccountService.bearer(for: .gemini)
            credential = .bearer(token, project: try GoogleAppConfiguration.read()?.projectID)
        } else {
            guard let key = try GeminiSpeechVault.read(), !key.isEmpty else { throw IrisFailure.message("Add a Gemini API key in Settings → Voice, or select your connected Gemini account.") }
            credential = .apiKey(key)
        }
        return credential
    }
    static func audio(text: String, voice: String, model: String, style: String, auth: String) async throws -> Data {
        let credential = try await credential(auth: auth)
        return try await GeminiSpeechClient.audio(text: text, voice: voice, model: model, style: style, credential: credential)
    }
}
