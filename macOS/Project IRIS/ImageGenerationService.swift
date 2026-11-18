import Foundation
import Security
import AppKit

/// A separate developer API credential; ChatGPT sign-in tokens are never used here.
enum ImageAPIVault {
    private static let service = "com.projectiris.image-generation"
    private static var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "openai"] }
    static func read() throws -> String? {
        var request = query; request[kSecReturnData as String] = true; request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = result as? Data else { throw IrisFailure.message("The image API credential couldn't be read from Keychain.") }
        return String(data: bytes, encoding: .utf8)
    }
    static func save(_ value: String) throws {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.hasPrefix("sk-"), !clean.contains(where: \.isWhitespace) else { throw IrisFailure.message("Enter an OpenAI API key, not a ChatGPT password or OAuth token.") }
        let bytes = Data(clean.utf8)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = bytes; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw IrisFailure.message("The API key couldn't be saved in Keychain.") }
    }
    static func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw IrisFailure.message("The image API key couldn't be removed.") }
    }
}
@MainActor enum ImageGenerationService {
    static let models = ["gpt-image-2.5-flare", "gpt-image-2.5-sunburst"]
    static var model: String {
        let saved = UserDefaults.standard.string(forKey: "IrisImageGenerationModel") ?? models[0]
        return models.contains(saved) ? saved : models[0]
    }
    static func generate(prompt: String, session: URLSession = .shared) async throws -> Data {
        guard let key = try ImageAPIVault.read(), !key.isEmpty else { throw IrisFailure.message("Add an image API key in Settings → AI → Image generation first. ChatGPT sign-in doesn't enable the Images API.") }
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, prompt.count <= 12000 else { throw IrisFailure.message("Use an image prompt of 1–12,000 characters.") }
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!); request.httpMethod = "POST"; request.timeoutInterval = 300
        request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization"); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "prompt": prompt, "n": 1, "size": "1024x1024", "quality": "low", "output_format": "png"])
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { throw IrisFailure.message("Image generation was rejected (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)). Check API billing, organization verification, model access or the prompt. No image was saved.") }
        return try decode(data)
    }
    static func decode(_ data: Data) throws -> Data {
        guard data.count <= 40_000_000, let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let item = (object["data"] as? [[String: Any]])?.first, let encoded = item["b64_json"] as? String, let raw = Data(base64Encoded: encoded), raw.count < 30_000_000, let bitmap = NSBitmapImageRep(data: raw), let png = bitmap.representation(using: .png, properties: [:]) else { throw IrisFailure.message("The image provider returned no valid image.") }
        return png
    }
}
