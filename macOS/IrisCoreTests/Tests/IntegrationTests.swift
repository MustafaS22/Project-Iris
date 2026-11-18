import XCTest
import Foundation
@testable import IrisCore

final class FixtureProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.cancelled) }
            let (status, data) = try handler(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class IntegrationTests: XCTestCase {
    var session: URLSession!
    override func setUp() { let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [FixtureProtocol.self]; session = URLSession(configuration: config) }
    override func tearDown() { session.invalidateAndCancel(); FixtureProtocol.handler = nil }
    func testModelDiscoveryUsesConfiguredServer() async throws {
        FixtureProtocol.handler = { request in XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:1234/v1/models"); return (200, Data(#"{"data":[{"id":"local-model"}]}"#.utf8)) }
        let models = try await ModelService.models(server: "http://127.0.0.1:1234/v1", session: session)
        XCTAssertEqual(models, ["local-model"])
    }
    func testRealRequestPayloadAndAnswerParsing() async throws {
        FixtureProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return (200, Data(#"{"choices":[{"message":{"content":"A useful answer."}}]}"#.utf8))
        }
        let text = try await ModelService.answer(server: "http://127.0.0.1:1234/v1", model: "local-model", messages: [.init(role: "user", text: "Explain recursion")], context: "untrusted attachment", role: .student, session: session)
        XCTAssertEqual(text, "A useful answer.")
    }
    func testHTTPFailureIsNotPresentedAsAnAnswer() async {
        FixtureProtocol.handler = { _ in (503, Data(#"{"error":"unavailable"}"#.utf8)) }
        do { _ = try await ModelService.models(server: "http://localhost:1234/v1", session: session); XCTFail("Expected error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("503")) }
    }
    func testEmptyModelAnswerIsAnError() async {
        FixtureProtocol.handler = { _ in (200, Data(#"{"choices":[]}"#.utf8)) }
        do { _ = try await ModelService.answer(server: "http://localhost:1234/v1", model: "model", messages: [], context: "", role: .student, session: session); XCTFail("Expected error") }
        catch { XCTAssertTrue(error.localizedDescription.contains("no text")) }
    }
    func testMalformedCatalogDoesNotInventModels() async {
        FixtureProtocol.handler = { _ in (200, Data("not-json".utf8)) }
        do { _ = try await ModelService.models(server: "http://localhost:1234/v1", session: session); XCTFail("Expected error") } catch { }
    }
    func testPKCEChallengeMatchesRFC7636() {
        XCTAssertEqual(OAuthSecurity.challenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }
    func testFormEncodingCannotInjectParameters() {
        let encoded = String(data: OAuthSecurity.form(["code": "a&redirect_uri=evil+value"]), encoding: .utf8)!
        XCTAssertEqual(encoded, "code=a%26redirect_uri%3Devil%2Bvalue")
    }
    func testInvalidIdentityTokenIsRejectedBeforeStorage() async {
        do { _ = try await OAuthSecurity.validateIDToken("unsigned.fake.token", clientID: "iris", nonce: "nonce", issuer: "https://auth.openai.com", jwksURL: URL(string: "https://auth.openai.com/.well-known/jwks.json")!, session: session); XCTFail("Expected rejection") } catch { }
    }
    @MainActor func testCallbackBindsToLoopbackAndReturnsMatchingState() async throws {
        let listener = OAuthCallback()
        let redirect = try await listener.begin(state: "test-state")
        XCTAssertEqual(redirect.host, "127.0.0.1"); XCTAssertEqual(redirect.path, "/auth/callback")
        async let response = listener.wait()
        var url = URLComponents(url: redirect, resolvingAgainstBaseURL: false)!
        url.queryItems = [URLQueryItem(name: "state", value: "test-state"), URLQueryItem(name: "code", value: "test-only")]
        let (_, http) = try await URLSession.shared.data(from: url.url!)
        XCTAssertEqual((http as? HTTPURLResponse)?.statusCode, 200)
        let values = try await response
        XCTAssertEqual(values["code"], "test-only")
    }
}

import Security
extension IntegrationTests {
    private func signedToken(nonce: String = "expected", expiry: Double = Date().timeIntervalSince1970 + 300) throws -> (String, Data) {
        let key = SecKeyCreateRandomKey([kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeySizeInBits: 2048] as CFDictionary, nil)!
        let publicData = SecKeyCopyExternalRepresentation(SecKeyCopyPublicKey(key)!, nil)! as Data
        let bytes = Array(publicData)
        var offset = 0
        func readLength() -> Int { let first = Int(bytes[offset]); offset += 1; if first < 128 { return first }; var count = 0; for _ in 0..<(first & 0x7f) { count = (count << 8) | Int(bytes[offset]); offset += 1 }; return count }
        XCTAssertEqual(bytes[offset], 0x30); offset += 1; _ = readLength()
        func integer() -> Data { XCTAssertEqual(bytes[offset], 0x02); offset += 1; let length = readLength(); var value = Data(bytes[offset..<(offset + length)]); offset += length; if value.first == 0 { value.removeFirst() }; return value }
        let n = integer(), e = integer()
        let jwks = try JSONSerialization.data(withJSONObject: ["keys": [["kid": "test-key", "kty": "RSA", "alg": "RS256", "n": n.base64URL, "e": e.base64URL]]])
        let header = try JSONSerialization.data(withJSONObject: ["alg": "RS256", "kid": "test-key"]).base64URL
        let payload = try JSONSerialization.data(withJSONObject: ["iss": "https://auth.openai.com", "aud": "iris-client", "sub": "subject", "nonce": nonce, "exp": expiry]).base64URL
        let signed = header + "." + payload
        let signature = SecKeyCreateSignature(key, .rsaSignatureMessagePKCS1v15SHA256, Data(signed.utf8) as CFData, nil)! as Data
        return (signed + "." + signature.base64URL, jwks)
    }
    func testSignedIdentityIsValidatedWithPublishedKey() async throws {
        let (token, jwks) = try signedToken()
        FixtureProtocol.handler = { _ in (200, jwks) }
        let identity = try await OAuthSecurity.validateIDToken(token, clientID: "iris-client", nonce: "expected", issuer: "https://auth.openai.com", jwksURL: URL(string: "https://auth.openai.com/.well-known/jwks.json")!, session: session)
        XCTAssertEqual(identity.subject, "subject")
    }
    func testWrongNonceAndWrongAudienceAreRejected() async throws {
        let (token, jwks) = try signedToken(); FixtureProtocol.handler = { _ in (200, jwks) }
        for (client, nonce) in [("iris-client", "wrong"), ("other-client", "expected")] {
            do { _ = try await OAuthSecurity.validateIDToken(token, clientID: client, nonce: nonce, issuer: "https://auth.openai.com", jwksURL: URL(string: "https://auth.openai.com/.well-known/jwks.json")!, session: session); XCTFail("Expected rejection") } catch { }
        }
    }
    func testExpiredSignedTokenIsRejected() async throws {
        let (token, jwks) = try signedToken(expiry: Date().timeIntervalSince1970 - 5); FixtureProtocol.handler = { _ in (200, jwks) }
        do { _ = try await OAuthSecurity.validateIDToken(token, clientID: "iris-client", nonce: "expected", issuer: "https://auth.openai.com", jwksURL: URL(string: "https://auth.openai.com/.well-known/jwks.json")!, session: session); XCTFail("Expected rejection") } catch { }
    }
    func testTamperedSignatureIsRejected() async throws {
        let (token, jwks) = try signedToken(); FixtureProtocol.handler = { _ in (200, jwks) }
        var segments = token.split(separator: ".").map(String.init)
        var signature = Data(base64URL: segments[2])!; signature[0] ^= 0xff; segments[2] = signature.base64URL
        do { _ = try await OAuthSecurity.validateIDToken(segments.joined(separator: "."), clientID: "iris-client", nonce: "expected", issuer: "https://auth.openai.com", jwksURL: URL(string: "https://auth.openai.com/.well-known/jwks.json")!, session: session); XCTFail("Expected rejection") } catch { }
    }
}
