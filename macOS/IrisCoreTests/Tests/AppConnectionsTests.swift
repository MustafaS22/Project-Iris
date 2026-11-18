import XCTest
@testable import IrisCore

final class AppConnectionsTests: XCTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }
    func testTargetsCannotRedirectCredentialsOrInjectQueries() {
        for (source, target) in [(KnowledgeConnector.github, "../repo"), (.github, "a/b?token=x"), (.notion, "https://evil.invalid"), (.slack, "C123456&x=y"), (.todoist, "../x"), (.googleChat, "spaces/a/messages?x=y")] {
            XCTAssertThrowsError(try AppKnowledgeAPI.request(source: source, target: target, token: "secret"))
        }
    }
    func testProviderRoutesAndReadOnlyLinearQuery() throws {
        let cases: [(KnowledgeConnector, String, String)] = [(.github,"owner/repo","api.github.com"),(.notion,String(repeating:"a",count:32),"api.notion.com"),(.slack,"C01234567","slack.com"),(.todoist,"","api.todoist.com"),(.linear,"","api.linear.app"),(.googleChat,"spaces/ABC_123","chat.googleapis.com"),(.googleTasks,"","tasks.googleapis.com")]
        for (source,target,host) in cases {
            let request = try AppKnowledgeAPI.request(source: source, target: target, token: "secret")
            XCTAssertEqual(request.url?.host,host); XCTAssertEqual(request.url?.scheme,"https")
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),source == .linear ? "secret" : "Bearer secret")
            if source == .linear { let body = String(data: request.httpBody!,encoding:.utf8)!; XCTAssertTrue(body.contains("assignedIssues")); XCTAssertFalse(body.contains("mutation")) }
            else { XCTAssertEqual(request.httpMethod,"GET") }
        }
    }
    func testInvalidAndErrorResponsesFailRatherThanEraseKnowledge() {
        for (source,payload) in [(KnowledgeConnector.slack,#"{"ok":false,"error":"invalid_auth"}"#),(.linear,#"{"errors":[{"message":"private"}]}"#),(.googleChat,"[]"),(.googleTasks,#"{"error":{"code":403}}"#),(.googleChat,#"{"messages":"invalid"}"#),(.todoist,"{}"),(.github,"{}"),(.notion,"{}") ] {
            XCTAssertThrowsError(try AppKnowledgeAPI.documents(data(payload),source:source,target:"x"))
        }
        XCTAssertNoThrow(try AppKnowledgeAPI.documents(data("{}"),source:.googleChat,target:"x"))
    }
    func testAllProviderPayloadsProduceKnowledge() throws {
        let fixtures: [(KnowledgeConnector,String)] = [
            (.github,#"[{"id":1,"title":"Fix","body":"Issue","html_url":"https://github.com/a/b/issues/1"}]"#),
            (.notion,#"{"results":[{"type":"paragraph","paragraph":{"rich_text":[{"plain_text":"Page text"}]}}]}"#),
            (.slack,#"{"ok":true,"messages":[{"ts":"1","user":"U1","text":"Hello"}]}"#),
            (.todoist,#"{"results":[{"id":"1","content":"Read","description":"Chapter one"}]}"#),
            (.linear,#"{"data":{"viewer":{"assignedIssues":{"nodes":[{"id":"1","identifier":"IR-1","title":"Fix","description":"Bug"}]}}}}"#),
            (.googleChat,#"{"messages":[{"name":"spaces/a/messages/b","text":"Hello"}]}"#),
            (.googleTasks,#"{"items":[{"id":"1","title":"Read","notes":"Chapter one"}]}"#)]
        for (source,payload) in fixtures { let docs = try AppKnowledgeAPI.documents(data(payload),source:source,target:"resource"); XCTAssertEqual(docs.count,1); XCTAssertEqual(docs.first?.source,source); XCTAssertFalse(docs.first!.body.isEmpty) }
    }
    func testXArchiveIsParsedWithoutExecutingJavaScript() throws {
        let docs = try SocialExportReader.read(data(#"window.YTD.tweets.part0 = [{"tweet":{"id_str":"1","full_text":"My post"}}];"#),source:.x,title:"tweets.js")
        XCTAssertEqual(docs.count,1); XCTAssertTrue(docs[0].body.contains("My post"))
        XCTAssertThrowsError(try SocialExportReader.read(data("alert('hello');"),source:.x,title:"x.js"))
        XCTAssertThrowsError(try SocialExportReader.read(data(#"window.YTD.tweets.part0 = []; malicious();"#),source:.x,title:"x.js"))
    }
    func testSelectedChatsOnlyAndRichTelegramText() throws {
        let ig = try SocialExportReader.read(data(#"{"title":"Friend","messages":[{"sender_name":"A","content":"new"},{"is_unsent":true,"content":"hidden"},{"sender_name":"B","content":"old"}]}"#),source:.instagram,title:"messages_1.json")
        XCTAssertEqual(ig[0].title,"Friend"); XCTAssertFalse(ig[0].body.contains("hidden")); XCTAssertEqual(ig[0].body,"B: old\nA: new")
        let tg = try SocialExportReader.read(data(#"{"name":"Group","messages":[{"from":"A","text":["Hello ",{"type":"bold","text":"world"}]}]}"#),source:.telegram,title:"result.json")
        XCTAssertEqual(tg[0].body,"A: Hello world")
        XCTAssertThrowsError(try SocialExportReader.read(data(#"{"chats":{"list":[]}}"#),source:.telegram,title:"all.json"))
    }
    func testInstagramKeepsNewestMessagesWithinLimit() throws {
        let messages = (0..<450).map { ["sender_name":"A","content":"message-\($0)"] }
        let bytes = try JSONSerialization.data(withJSONObject:["messages":messages])
        let docs = try SocialExportReader.read(bytes,source:.instagram,title:"chat.json")
        XCTAssertTrue(docs[0].body.contains("message-0\n") || docs[0].body.hasSuffix("message-0"))
        XCTAssertFalse(docs[0].body.contains("message-449"))
    }
    func testNewSourcesHaveReadOnlyGoogleScopes() {
        XCTAssertEqual(KnowledgeConnector.googleChat.scope,"https://www.googleapis.com/auth/chat.messages.readonly")
        XCTAssertEqual(KnowledgeConnector.googleTasks.scope,"https://www.googleapis.com/auth/tasks.readonly")
        XCTAssertNil(KnowledgeConnector.instagram.scope)
    }
}
