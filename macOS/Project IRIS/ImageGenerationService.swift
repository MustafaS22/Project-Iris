import Foundation
import Security
import AppKit

enum ImageProvider: String, CaseIterable {
    case openAI = "openai"
    case cloudflare

    static let preferenceKey = "IrisImageProvider"

    var title: String {
        switch self {
        case .openAI: "OpenAI"
        case .cloudflare: "Cloudflare Workers AI"
        }
    }
}

struct CloudflareImageCredential: Codable {
    let accountID: String
    let token: String

    init(accountID: String, token: String) throws {
        let account = accountID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard account.utf8.count == 32, account.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw IrisFailure.message("Enter the 32-character Cloudflare Account ID.")
        }
        guard !cleanToken.isEmpty, cleanToken.utf8.allSatisfy({ (33...126).contains($0) }) else {
            throw IrisFailure.message("Enter a valid Cloudflare Workers AI API token.")
        }
        self.accountID = account
        self.token = cleanToken
    }
}

/// Developer credentials are separate from chat sign-in and stored separately by provider.
enum ImageAPIVault {
    private static let service = "com.projectiris.image-generation"

    private static func query(_ provider: ImageProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }

    static func read() throws -> String? {
        try readData(.openAI).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func readCloudflare() throws -> CloudflareImageCredential? {
        try readData(.cloudflare).map { try JSONDecoder().decode(CloudflareImageCredential.self, from: $0) }
    }

    private static func readData(_ provider: ImageProvider) throws -> Data? {
        var request = query(provider)
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let bytes = result as? Data else {
            throw IrisFailure.message("The image credential couldn’t be read from Keychain.")
        }
        return bytes
    }

    static func save(_ value: String) throws {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.hasPrefix("sk-"), !clean.contains(where: \.isWhitespace) else {
            throw IrisFailure.message("Enter an OpenAI developer API key.")
        }
        try saveData(Data(clean.utf8), provider: .openAI)
    }

    static func saveCloudflare(_ credential: CloudflareImageCredential) throws {
        try saveData(JSONEncoder().encode(credential), provider: .cloudflare)
    }

    private static func saveData(_ data: Data, provider: ImageProvider) throws {
        let query = query(provider)
        var status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw IrisFailure.message("The image credential couldn’t be saved in Keychain.")
        }
    }

    static func delete(_ provider: ImageProvider = .openAI) throws {
        let status = SecItemDelete(query(provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw IrisFailure.message("The image credential couldn’t be removed.")
        }
    }
}

@MainActor enum ImageGenerationService {
    static let models = ["gpt-image-2.5-flare", "gpt-image-2.5-sunburst"]
    private static let cloudflareModel = "@cf/black-forest-labs/flux-1-schnell"

    static var provider: ImageProvider {
        let saved = UserDefaults.standard.string(forKey: ImageProvider.preferenceKey)
        return saved.flatMap(ImageProvider.init(rawValue:)) ?? .openAI
    }

    static var model: String {
        let saved = UserDefaults.standard.string(forKey: "IrisImageGenerationModel") ?? models[0]
        return models.contains(saved) ? saved : models[0]
    }

    static var reviewDescription: String {
        switch provider {
        case .cloudflare:
            "Sends your prompt to Cloudflare Workers AI and saves one PNG. FLUX.1 Schnell uses your Workers AI quota. Paid Cloudflare plans may charge for usage above their free allocation."
        case .openAI:
            "Sends your prompt to OpenAI and saves one 1024×1024 PNG at low quality. Model: \(model). Uses separate API billing. Cancellation may not prevent provider charges."
        }
    }

    static func generate(prompt: String, session: URLSession = .shared) async throws -> Data {
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let provider = provider
        let request: URLRequest
        switch provider {
        case .cloudflare:
            guard let credential = try ImageAPIVault.readCloudflare() else {
                throw IrisFailure.message("Add your Cloudflare Account ID and Workers AI token in Settings → AI → Image generation.")
            }
            request = try cloudflareRequest(prompt: prompt, credential: credential)
        case .openAI:
            guard let key = try ImageAPIVault.read(), !key.isEmpty else {
                throw IrisFailure.message("Add an OpenAI image API key in Settings → AI → Image generation, or choose Cloudflare. ChatGPT sign-in does not enable the Images API.")
            }
            guard !prompt.isEmpty, prompt.count <= 12_000 else {
                throw IrisFailure.message("Use an image prompt of 1–12,000 characters.")
            }
            request = try makeRequest(url: URL(string: "https://api.openai.com/v1/images/generations")!, token: key, body: [
                "model": model, "prompt": prompt, "n": 1, "size": "1024x1024", "quality": "low", "output_format": "png"
            ])
        }

        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(status) else {
            if provider == .cloudflare {
                if status == 429 {
                    throw IrisFailure.message("Cloudflare’s quota or rate limit was reached. Try again later or after the daily reset.")
                }
                if [401, 403].contains(status) {
                    throw IrisFailure.message("Cloudflare rejected the token. Check the Account ID and Workers AI token permissions.")
                }
                throw IrisFailure.message("Cloudflare could not generate the image (HTTP \(status)). Check your Workers AI quota and prompt.")
            }
            throw IrisFailure.message("OpenAI could not generate the image (HTTP \(status)). Check API billing, model access and the prompt.")
        }
        return try decode(data, provider: provider)
    }

    static func cloudflareRequest(prompt: String, credential: CloudflareImageCredential) throws -> URLRequest {
        guard !prompt.isEmpty, prompt.utf16.count <= 2048 else {
            throw IrisFailure.message("Use an image prompt of 1–2,048 characters for FLUX.1 Schnell.")
        }
        let url = URL(string: "https://api.cloudflare.com/client/v4/accounts/\(credential.accountID)/ai/run/\(cloudflareModel)")!
        return try makeRequest(url: url, token: credential.token, body: ["prompt": prompt, "steps": 4])
    }

    private static func makeRequest(url: URL, token: String, body: [String: Any]) throws -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func decode(_ data: Data, provider: ImageProvider = .openAI) throws -> Data {
        guard data.count <= 40_000_000, let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw IrisFailure.message("The image provider returned no valid image.")
        }
        let encoded: String?
        switch provider {
        case .cloudflare:
            encoded = object["success"] as? Bool == true ? (object["result"] as? [String: Any])?["image"] as? String : nil
        case .openAI:
            encoded = (object["data"] as? [[String: Any]])?.first?["b64_json"] as? String
        }
        guard let encoded, let raw = Data(base64Encoded: encoded), raw.count < 30_000_000,
              let bitmap = NSBitmapImageRep(data: raw), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw IrisFailure.message("The image provider returned no valid image.")
        }
        return png
    }
}
