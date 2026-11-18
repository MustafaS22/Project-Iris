import Foundation
import Combine
import AppKit
import Network
import CryptoKit
import Security
import OSLog

struct AccountCredential: Codable {
    var source: KnowledgeSource
    var clientID: String
    var subject: String
    var email: String?
    var accessToken: String
    var refreshToken: String?
    var idToken: String?
    var scopes: [String]
    var expiresAt: Date
}

enum CredentialVault {
    private static let service = "com.projectiris.accounts"
    static func read(_ source: KnowledgeSource, allowInteraction: Bool = true) throws -> AccountCredential? {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: source.rawValue, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        if !allowInteraction { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        var result: CFTypeRef?; let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw IrisFailure.message("The saved account couldn't be read from Keychain (\(status)).") }
        return try JSONDecoder().decode(AccountCredential.self, from: data)
    }
    /// Keychain may wait for macOS authorization. Never make the UI wait synchronously.
    static func readAsync(_ source: KnowledgeSource, allowInteraction: Bool = true) async throws -> AccountCredential? {
        let value = try await Task.detached(priority: .userInitiated) { try read(source, allowInteraction: allowInteraction) }.value
        try Task.checkCancellation(); return value
    }
    static func saveAsync(_ credential: AccountCredential, allowInteraction: Bool = true) async throws {
        try await Task.detached(priority: .userInitiated) { try save(credential, allowInteraction: allowInteraction) }.value
        try Task.checkCancellation()
    }
    static func save(_ credential: AccountCredential, allowInteraction: Bool = true) throws {
        let data = try JSONEncoder().encode(credential)
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: credential.source.rawValue]
        if !allowInteraction { query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail }
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecItemNotFound {
            var add = query; add[kSecValueData as String] = data; add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let status = SecItemAdd(add as CFDictionary, nil)
            guard status == errSecSuccess else { throw IrisFailure.message("The account couldn't be saved securely (\(status)).") }; return
        }
        guard update == errSecSuccess else { throw IrisFailure.message("The account couldn't be updated securely (\(update)).") }
    }
    static func delete(_ source: KnowledgeSource) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: source.rawValue]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw IrisFailure.message("The saved account couldn't be removed (\(status)).") }
    }
}

enum OAuthSecurity {
    static func random() -> String { Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64URL }
    static func challenge(_ verifier: String) -> String { Data(SHA256.hash(data: Data(verifier.utf8))).base64URL }
    static func form(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return Data(fields.sorted { $0.key < $1.key }.map { "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)" }.joined(separator: "&").utf8)
    }
    struct Identity { var subject: String; var email: String? }
    static func validateIDToken(_ token: String, clientID: String, nonce: String, issuer: String, jwksURL: URL, session: URLSession = .shared) async throws -> Identity {
        let parts = token.split(separator: ".").map(String.init)
        guard parts.count == 3, let headerData = Data(base64URL: parts[0]), let payloadData = Data(base64URL: parts[1]), let signature = Data(base64URL: parts[2]),
              let header = try JSONSerialization.jsonObject(with: headerData) as? [String: Any], header["alg"] as? String == "RS256", let kid = header["kid"] as? String,
              let payload = try JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else { throw IrisFailure.message("The sign-in token has an unsupported format.") }
        let (data, response) = try await session.data(from: jwksURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 1_000_000,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let keys = object["keys"] as? [[String: Any]],
              let key = keys.first(where: { $0["kid"] as? String == kid && $0["kty"] as? String == "RSA" }),
              let n = key["n"] as? String, let e = key["e"] as? String, let modulus = Data(base64URL: n), let exponent = Data(base64URL: e) else { throw IrisFailure.message("The identity provider's signing key could not be verified.") }
        let der = sequence(integer(modulus) + integer(exponent))
        var keyError: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(der as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, &keyError),
              SecKeyVerifySignature(secKey, .rsaSignatureMessagePKCS1v15SHA256, Data((parts[0] + "." + parts[1]).utf8) as CFData, signature as CFData, nil) else { throw IrisFailure.message("The identity token's signature is invalid.") }
        let audiences = payload["aud"] as? [String]
        let audienceMatches = (payload["aud"] as? String == clientID) || (audiences?.contains(clientID) ?? false)
        let authorizedPartyMatches = (audiences?.count ?? 0) <= 1 || payload["azp"] as? String == clientID
        let validFrom = (payload["nbf"] as? Double ?? 0) <= Date().timeIntervalSince1970 + 30
        guard payload["iss"] as? String == issuer, audienceMatches, authorizedPartyMatches, validFrom, payload["nonce"] as? String == nonce,
              let expiry = payload["exp"] as? Double, expiry > Date().timeIntervalSince1970,
              let subject = payload["sub"] as? String, !subject.isEmpty else { throw IrisFailure.message("The identity token did not match this sign-in attempt, or has expired.") }
        return Identity(subject: subject, email: payload["email"] as? String)
    }
    private static func length(_ count: Int) -> Data {
        if count < 128 { return Data([UInt8(count)]) }
        var n = count, bytes: [UInt8] = []; while n > 0 { bytes.insert(UInt8(n & 0xff), at: 0); n >>= 8 }
        return Data([0x80 | UInt8(bytes.count)] + bytes)
    }
    private static func integer(_ data: Data) -> Data { let bytes = (data.first ?? 0) >= 0x80 ? Data([0]) + data : data; return Data([0x02]) + length(bytes.count) + bytes }
    private static func sequence(_ data: Data) -> Data { Data([0x30]) + length(data.count) + data }
}

extension Data {
    var base64URL: String { base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    init?(base64URL: String) { var s = base64URL.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/"); s += String(repeating: "=", count: (4 - s.count % 4) % 4); self.init(base64Encoded: s) }
}

/// A short-lived HTTP callback bound only to IPv4 loopback. Never exposes a command endpoint.
@MainActor
final class OAuthCallback {
    private var listener: NWListener?
    private var result: CheckedContinuation<[String: String], Error>?
    private var timeout: Task<Void, Never>?
    private var expectedState = ""
    private var listenerReady = false
    private var connections: [NWConnection] = []
    func begin(state: String) async throws -> URL {
        expectedState = state
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try NWListener(using: parameters); self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in self?.accept(connection) }
        }
        let port: UInt16 = try await withCheckedThrowingContinuation { [weak self] continuation in
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    guard let self, !self.listenerReady else { return }
                    switch state {
                    case .ready:
                        self.listenerReady = true
                        if let port = listener.port { continuation.resume(returning: port.rawValue) }
                        else { continuation.resume(throwing: IrisFailure.message("The local callback port is unavailable.")) }
                    case .failed(let error): self.listenerReady = true; continuation.resume(throwing: error)
                    case .cancelled: self.listenerReady = true; continuation.resume(throwing: CancellationError())
                    default: break
                    }
                }
            }
            listener.start(queue: .main)
        }
        return URL(string: "http://127.0.0.1:\(port)/auth/callback")!
    }
    func wait() async throws -> [String: String] {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                result = continuation
                timeout = Task { [weak self] in try? await Task.sleep(for: .seconds(180)); guard !Task.isCancelled else { return }; self?.finish(.failure(IrisFailure.message("Sign-in timed out. Try again when you're ready."))) }
            }
        } onCancel: { Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) } }
    }
    func cancel() { finish(.failure(CancellationError())) }
    private func accept(_ connection: NWConnection) {
        guard connections.count < 8 else { connection.cancel(); return }
        connections.append(connection); connection.start(queue: .main)
        read(connection, buffer: Data())
    }
    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, complete, error in
            Task { @MainActor [weak self] in
                guard let self else { connection.cancel(); return }
                let collected = buffer + (data ?? Data())
                guard collected.count <= 16384, error == nil else { connection.cancel(); return }
                guard let text = String(data: collected, encoding: .utf8), text.contains("\r\n\r\n") else {
                    if complete { connection.cancel() } else { self.read(connection, buffer: collected) }; return
                }
                guard let line = text.components(separatedBy: "\r\n").first else { connection.cancel(); return }
                let parts = line.split(separator: " "); guard parts.count == 3, parts[0] == "GET",
                      let url = URLComponents(string: "http://127.0.0.1" + parts[1]), url.path == "/auth/callback" else { connection.cancel(); return }
                var values: [String: String] = [:]
                for item in url.queryItems ?? [] { guard values[item.name] == nil else { connection.cancel(); return }; values[item.name] = item.value ?? "" }
                guard values["state"] == self.expectedState else { connection.cancel(); return }
                let body = "Iris received your sign-in response. You can return to the app."
                let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nCache-Control: no-store\r\nContent-Security-Policy: default-src 'none'\r\nConnection: close\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                self.finish(.success(values), preserving: connection)
            }
        }
    }
    private func finish(_ value: Result<[String: String], Error>, preserving: NWConnection? = nil) {
        timeout?.cancel(); timeout = nil; listener?.cancel(); listener = nil
        for connection in connections where connection !== preserving { connection.cancel() }; connections = []
        let pending = result; result = nil; pending?.resume(with: value)
    }
}

@MainActor
final class AccountService: ObservableObject {
    @Published var authorizing = false
    @Published var status = "Not connected"
    private var statusTask: Task<Void, Never>?
    private var callback: OAuthCallback?
    private static let log = Logger(subsystem: "com.projectiris.Project-IRIS", category: "accounts")
    func signIn(source: KnowledgeSource, googleClientID: String, googleScopes: [String] = []) async throws {
        guard !authorizing, source != .local else { return }
        authorizing = true; status = "Waiting for browser authorization…"
        defer { authorizing = false; callback?.cancel(); callback = nil }
        let previous = try await CredentialVault.readAsync(source)
        let state = OAuthSecurity.random(), nonce = OAuthSecurity.random(), verifier = OAuthSecurity.random()
        let listener = OAuthCallback(); callback = listener
        let redirect = try await listener.begin(state: state)
        let newRegistration = previous == nil
        let clientID = source == .openAI ? (previous?.clientID ?? "dynamic_agent_client") : googleClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else { throw IrisFailure.message("Set Iris's registered Google desktop OAuth client ID first.") }
        var fields = ["client_id": clientID, "response_type": "code", "redirect_uri": redirect.absoluteString, "state": state, "nonce": nonce, "code_challenge_method": "S256", "code_challenge": OAuthSecurity.challenge(verifier)]
        let authorize: String
        if source == .openAI {
            authorize = "https://auth.openai.com/api/accounts/authorize"
            fields["scope"] = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
            fields["resource"] = "https://api.openai.com/v1"
            let defaults = UserDefaults.standard
            let hostID = defaults.string(forKey: "IrisOAuthHostID") ?? "urn:uuid:\(UUID().uuidString.lowercased())"
            defaults.set(hostID, forKey: "IrisOAuthHostID"); fields["ext_agent_host_id"] = hostID
            if newRegistration { fields["agent_name_hint"] = "Iris" } else { fields["id_token_hint"] = previous?.idToken }
        } else {
            authorize = "https://accounts.google.com/o/oauth2/v2/auth"
            let requested = source == .googleKnowledge ? Array(Set(googleScopes + (previous?.scopes ?? []))).sorted() : ["https://www.googleapis.com/auth/cloud-platform", "https://www.googleapis.com/auth/generative-language.retriever"]
            fields["scope"] = (["openid", "email", "profile"] + requested).joined(separator: " ")
            fields["include_granted_scopes"] = "true"
            fields["access_type"] = "offline"; fields["prompt"] = "select_account consent"
        }
        var components = URLComponents(string: authorize)!; components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url, NSWorkspace.shared.open(url) else { throw IrisFailure.message("The browser couldn't be opened for sign-in.") }
        let response = try await listener.wait()
        if let error = response["error"] {
            if source != .openAI { throw IrisFailure.message(GoogleAuthorizationHelp.message(for: error)) }
            throw IrisFailure.message("Sign-in wasn't completed (\(error)). Your previous connection is unchanged.")
        }
        guard let code = response["code"], !code.isEmpty else { throw IrisFailure.message("The authorization response did not contain a code.") }
        let issuedID = source == .openAI ? (response["client_id"] ?? clientID) : clientID
        if source == .openAI {
            guard issuedID != "dynamic_agent_client", !issuedID.isEmpty, newRegistration || issuedID == clientID else { throw IrisFailure.message("The returned client registration didn't match this sign-in attempt.") }
        }
        status = "Validating account…"
        var tokenFields = ["grant_type": "authorization_code", "code": code, "client_id": issuedID, "redirect_uri": redirect.absoluteString, "code_verifier": verifier]
        if source == .openAI { tokenFields["resource"] = "https://api.openai.com/v1" }
        if source != .openAI, let secret = try GoogleAppConfiguration.read()?.clientSecret, !secret.isEmpty { tokenFields["client_secret"] = secret }
        let token = try await Self.exchange(source: source, fields: tokenFields)
        guard let idToken = token.id_token else { throw IrisFailure.message("The identity provider returned no ID token.") }
        let identity = try await OAuthSecurity.validateIDToken(idToken, clientID: issuedID, nonce: nonce, issuer: source == .openAI ? "https://auth.openai.com" : "https://accounts.google.com", jwksURL: URL(string: source == .openAI ? "https://auth.openai.com/.well-known/jwks.json" : "https://www.googleapis.com/oauth2/v3/certs")!)
        if let previous, previous.clientID == clientID, previous.subject != identity.subject { throw IrisFailure.message("This sign-in belongs to a different account. Disconnect the existing account before changing it.") }
        let scopes = (token.scope ?? "").split(separator: " ").map(String.init)
        if source == .googleKnowledge, !Set(googleScopes).isSubset(of: Set(scopes)) { throw IrisFailure.message("The requested knowledge-source access wasn't granted. Nothing was imported.") }
        if source == .openAI, !scopes.contains("chatgpt.tokens.use.direct") { throw IrisFailure.message("ChatGPT plan usage wasn't granted. Enable it in the authorization flow before using Iris for AI requests.") }
        let credential = AccountCredential(source: source, clientID: issuedID, subject: identity.subject, email: identity.email, accessToken: token.access_token, refreshToken: token.refresh_token ?? (previous?.clientID == issuedID ? previous?.refreshToken : nil), idToken: idToken, scopes: scopes, expiresAt: Date().addingTimeInterval(token.expires_in ?? 3600))
        try await CredentialVault.saveAsync(credential)
        status = "Connected · \(identity.email ?? "verified account")"; Self.log.info("Account authorization validated")
    }
    static let callbackEnabled = true // Explicitly requested browser sign-in; listener binds only to 127.0.0.1.
    func refreshStatus(_ source: KnowledgeSource) {
        guard source != .local else { return }
        statusTask?.cancel(); status = "Checking account…"
        statusTask = Task { [weak self] in
            do {
                let saved = try await CredentialVault.readAsync(source); try Task.checkCancellation()
                self?.status = saved.map { "Connected · " + ($0.email ?? "verified account") } ?? "Not connected"
            } catch { if !Task.isCancelled { self?.status = error.localizedDescription } }
        }
    }
    func cancel() { callback?.cancel() }
    func disconnect(_ source: KnowledgeSource) throws { statusTask?.cancel(); try CredentialVault.delete(source); status = "Disconnected on this Mac" }
    static func bearer(for source: KnowledgeSource, allowInteraction: Bool = true) async throws -> String {
        guard var saved = try await CredentialVault.readAsync(source, allowInteraction: allowInteraction) else { throw IrisFailure.message("Connect your \(source.rawValue) account in Knowledge Source first.") }
        let configuration = source == .openAI ? nil : try await Task.detached { try GoogleAppConfiguration.read(allowInteraction: allowInteraction) }.value
        if source != .openAI, let configuration, saved.clientID != configuration.clientID {
            throw IrisFailure.message("Iris's Google app registration changed. Reconnect Google to authorize this version.")
        }
        if saved.expiresAt.timeIntervalSinceNow > 90 { return saved.accessToken }
        guard let refresh = saved.refreshToken else { throw IrisFailure.message("Your sign-in expired. Reconnect the account.") }
        var fields = ["grant_type": "refresh_token", "refresh_token": refresh, "client_id": saved.clientID]
        if source == .openAI { fields["resource"] = "https://api.openai.com/v1" }
        if source != .openAI, let secret = configuration?.clientSecret, !secret.isEmpty { fields["client_secret"] = secret }
        let token = try await exchange(source: source, fields: fields)
        if let scopes = token.scope { saved.scopes = scopes.split(separator: " ").map(String.init) }
        if source == .openAI, !saved.scopes.contains("chatgpt.tokens.use.direct") { throw IrisFailure.message("ChatGPT plan usage permission is no longer enabled.") }
        saved.accessToken = token.access_token; saved.refreshToken = token.refresh_token ?? saved.refreshToken; saved.expiresAt = Date().addingTimeInterval(token.expires_in ?? 3600)
        try await CredentialVault.saveAsync(saved, allowInteraction: allowInteraction); return saved.accessToken
    }
    private struct TokenResponse: Decodable { var access_token: String; var refresh_token: String?; var id_token: String?; var expires_in: Double?; var scope: String? }
    private static func exchange(source: KnowledgeSource, fields: [String: String]) async throws -> TokenResponse {
        let url = URL(string: source == .openAI ? "https://auth.openai.com/api/accounts/oauth/token" : "https://oauth2.googleapis.com/token")!
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 30; request.httpBody = OAuthSecurity.form(fields); request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw IrisFailure.message("The provider rejected the token exchange. Start a fresh sign-in; check account eligibility and OAuth configuration.") }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}
