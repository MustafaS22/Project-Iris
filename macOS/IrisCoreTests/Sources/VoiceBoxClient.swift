import Foundation

struct VoiceBoxProfile: Decodable, Identifiable, Equatable {
    let id: String
    let name: String
    let language: String
    let description: String?
    let default_engine: String?
    let preset_engine: String?
}

private final class VoiceBoxRedirectGuard: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// VoiceBox's OpenAI-compatible endpoint runs locally; no OpenAI account or credential is used.
enum VoiceBoxClient {
    static let defaultServer = "http://127.0.0.1:17493"
    static let session = URLSession(configuration: .ephemeral, delegate: VoiceBoxRedirectGuard(), delegateQueue: nil)
    static func baseURL(_ server: String) throws -> URL {
        guard let parts = URLComponents(string: server.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "http", ["localhost", "127.0.0.1", "[::1]", "::1"].contains(parts.host?.lowercased() ?? ""),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/", let url = parts.url else {
            throw IrisFailure.message("Use VoiceBox's local address, such as http://127.0.0.1:17493. Remote voice servers are not enabled.")
        }
        return url
    }
    static func profiles(server: String, session: URLSession = session) async throws -> [VoiceBoxProfile] {
        var request = URLRequest(url: try baseURL(server).appendingPathComponent("profiles")); request.timeoutInterval = 8
        do {
            let (data, response) = try await session.data(for: request)
            try check(response, data: data)
            let profiles = try JSONDecoder().decode([VoiceBoxProfile].self, from: data)
            return profiles.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch let error as URLError where error.code != .cancelled {
            throw IrisFailure.message("Can't reach VoiceBox. Open VoiceBox, enable its local server, then refresh voices. Default port: 17493.")
        }
    }
    static func request(server: String, profile: String, text: String, speed: Double) throws -> URLRequest {
        guard !profile.isEmpty else { throw IrisFailure.message("Refresh voices and choose a VoiceBox profile in Settings → Voice.") }
        let spoken = speechText(text)
        guard !spoken.isEmpty else { throw IrisFailure.message("This response has no text to read aloud.") }
        var request = URLRequest(url: try baseURL(server).appendingPathComponent("v1/audio/speech"))
        request.httpMethod = "POST"; request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/wav", forHTTPHeaderField: "Accept")
        // tts-1 is VoiceBox's documented alias for the selected profile's configured engine.
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": "tts-1", "voice": profile, "input": spoken, "response_format": "wav", "speed": min(1.4, max(0.75, speed)), "instructions": SpeechRendering.delivery])
        return request
    }
    static func audio(server: String, profile: String, text: String, speed: Double, session: URLSession = session) async throws -> Data {
        try Task.checkCancellation()
        let request = try request(server: server, profile: profile, text: text, speed: speed)
        do {
            let (data, response) = try await session.data(for: request)
            try Task.checkCancellation()
            if (response as? HTTPURLResponse)?.statusCode == 404 {
                // Fall back only when the server confirms the route is absent, never on a
                // generation failure or a missing profile in the modern speech endpoint.
                var discovery = URLRequest(url: try baseURL(server).appendingPathComponent("openapi.json"))
                discovery.timeoutInterval = 8
                let (schema, schemaResponse) = try await session.data(for: discovery)
                try check(schemaResponse, data: schema)
                let root = try JSONSerialization.jsonObject(with: schema) as? [String: Any]
                if let paths=root?["paths"] as? [String:Any],paths["/v1/audio/speech"] == nil {
                    guard paths["/generate/stream"] != nil else{throw IrisFailure.message("Update VoiceBox to a version with an audio-only speech endpoint. The older auto-play route can cause overlapping voices.")}
                    return try await legacyAudio(server:server,profile:profile,text:text,session:session)
                }
            }
            try check(response, data: data)
            return try validatedAudio(data)
        } catch let error as URLError where error.code != .cancelled {
            throw IrisFailure.message("VoiceBox speech couldn't finish. Keep VoiceBox open with its voice model downloaded, then try Preview again.")
        }
    }
    private struct Generation: Decodable {
        let id: String
        let status: String?
    }
    private static func legacyAudio(server: String, profile: String, text: String, session: URLSession) async throws -> Data {
        let base=try baseURL(server)
        let voices=try await profiles(server:server,session:session)
        guard let voice=voices.first(where:{$0.id==profile}) else{throw IrisFailure.message("Refresh voices and choose an available VoiceBox profile.")}
        var request=URLRequest(url:base.appendingPathComponent("generate/stream"));request.httpMethod="POST";request.timeoutInterval=180
        request.setValue("application/json",forHTTPHeaderField:"Content-Type");request.setValue("audio/wav",forHTTPHeaderField:"Accept")
        request.httpBody=try JSONSerialization.data(withJSONObject:["profile_id":profile,"text":speechText(text),"language":voice.language,"engine":(voice.default_engine ?? voice.preset_engine).map{$0 as Any} ?? NSNull(),"personality":false,"instruct":SpeechRendering.delivery])
        let (data,response)=try await session.data(for:request);try Task.checkCancellation();try check(response,data:data)
        return try validatedAudio(data)
    }

    private static func cancelGeneration(_ url: URL, session: URLSession) async {
        var request = URLRequest(url: url); request.httpMethod = "POST"; request.timeoutInterval = 4
        _ = try? await session.data(for: request)
    }
    private static func validatedAudio(_ data: Data) throws -> Data {
            guard data.count > 44, data.count <= 25_000_000, data.starts(with: Data("RIFF".utf8)), data.subdata(in: 8..<12) == Data("WAVE".utf8) else { throw IrisFailure.message("VoiceBox returned no valid WAV audio. Check its selected voice and engine.") }
            return data
    }
    static func transcriptionRequest(server:String,audio:Data,language:String?=nil) throws -> URLRequest {
        guard !audio.isEmpty,audio.count<=8_000_000 else{throw IrisFailure.message("Voice recording is empty or too long. Try a shorter question.")}
        let boundary="IrisVoice-"+UUID().uuidString
        var request=URLRequest(url:try baseURL(server).appendingPathComponent("transcribe"));request.httpMethod="POST";request.timeoutInterval=60
        request.setValue("multipart/form-data; boundary="+boundary,forHTTPHeaderField:"Content-Type")
        var body=Data()
        func append(_ text:String){body.append(Data(text.utf8))}
        if let language,language.range(of:#"^[a-z]{2,3}$"#,options:.regularExpression) != nil {append("--\(boundary)\r\nContent-Disposition: form-data; name=\"language\"\r\n\r\n\(language)\r\n")}
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"question.m4a\"\r\nContent-Type: audio/mp4\r\n\r\n");body.append(audio);append("\r\n--\(boundary)--\r\n");request.httpBody=body
        return request
    }
    static func transcribe(server:String,audio:Data,language:String?=nil,session:URLSession=session) async throws -> String {
        let (data,response)=try await session.data(for:transcriptionRequest(server:server,audio:audio,language:language))
        try Task.checkCancellation()
        if (response as? HTTPURLResponse)?.statusCode == 202 {throw IrisFailure.message("VoiceBox is preparing its local recognition model. Wait for its download to finish, then try again; Iris will not retry automatically.")}
        try check(response,data:data)
        struct Transcript:Decodable{let text:String}
        let text=String(try JSONDecoder().decode(Transcript.self,from:data).text.trimmingCharacters(in:.whitespacesAndNewlines).prefix(6000))
        guard !text.isEmpty else{throw IrisFailure.message("No speech was recognized. Try speaking closer to the microphone.")};return text
    }
    static func speechText(_ text: String) -> String {
        var clean = ResponsePresentation.visibleText(text)
        clean = clean.replacingOccurrences(of: "(?s)```.*?(?:```|$)", with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "!?\\[([^\\]]+)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "(?m)^\\s{0,3}(?:#{1,6} |[-*+] )", with: "", options: .regularExpression)
        clean = clean.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
        return String(SpeechRendering.text(clean).prefix(2000))
    }
    private static func check(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 { throw IrisFailure.message("VoiceBox couldn't find this voice or audio. Refresh voices and choose an available profile.") }
            if code == 400 || code == 422 { throw IrisFailure.message("VoiceBox couldn't use this voice. Check the profile's engine and reference sample in VoiceBox, then refresh voices.") }
            throw IrisFailure.message("VoiceBox couldn't generate speech (HTTP \(code)). Check its engine and model status in VoiceBox.")
        }
    }
}
