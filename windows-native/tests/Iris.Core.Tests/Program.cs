using System.Net;
using System.Text.Json;
using Iris.Core;

var testPath = Path.Combine(Path.GetTempPath(), "Iris.Core.Tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(testPath);
var count = 0;

async Task Check(string name, Func<Task> body)
{
    await body();
    count++;
    Console.WriteLine("PASS " + name);
}

static void Require(bool condition, string reason)
{
    if (!condition) throw new Exception(reason);
}

static async Task Throws<T>(Func<Task> job) where T : Exception
{
    try { await job(); }
    catch (T) { return; }
    throw new Exception("Expected " + typeof(T).Name);
}

static async Task<string> Read(ChatClient client, Settings settings, string? secret = null,
    CancellationToken cancellationToken = default)
{
    var answer = "";
    await foreach (var token in client.StreamAsync(settings, secret, [new("user", "Hello")], "I prefer concise responses.", cancellationToken))
        answer += token;
    return answer;
}

try
{
    var store = new StateStore(Path.Combine(testPath, "workspace.json"));
    var local = new Settings(Model: "fixture");
    await Check("store round-trip and interrupted agents", async () =>
    {
        var workspace = Workspace.Empty();
        workspace.Jobs.Add(new(Guid.NewGuid(), "Draft", "Prepare a note", JobStatus.Running));
        workspace.Memories.Add(new(Guid.NewGuid(), "I prefer concise responses."));
        await store.SaveAsync(workspace);
        var loaded = await store.LoadAsync();
        Require(loaded.Jobs[0].Status == JobStatus.Interrupted && loaded.Memories[0].Text == workspace.Memories[0].Text, "Invalid restored state");
    });
    await Check("corrupt file is preserved", async () =>
    {
        var bad = "{invalid}";
        await File.WriteAllTextAsync(Path.Combine(testPath, "workspace.json"), bad);
        await Throws<JsonException>(() => store.LoadAsync());
        Require(await File.ReadAllTextAsync(Path.Combine(testPath, "workspace.json")) == bad, "Corrupt data was modified");
    });
    await Check("canceled save preserves existing data", async () =>
    {
        var saved = Workspace.Empty();
        await store.SaveAsync(saved);
        using var stopped = new CancellationTokenSource();
        stopped.Cancel();
        await Throws<OperationCanceledException>(() => store.SaveAsync(saved with { Settings = new(Model: "different") }, stopped.Token));
        Require((await store.LoadAsync()).Settings.Model == "", "Canceled save replaced workspace");
    });
    await Check("memory relevance", () =>
    {
        var memories = new[] { new Memory(Guid.NewGuid(), "Prefer concise responses."), new Memory(Guid.NewGuid(), "Thursday volleyball.") };
        Require(AssistantContext.RelevantMemory("Can we keep responses concise?", memories) == memories[0].Text, "Irrelevant memory leaked");
        return Task.CompletedTask;
    });
    await Check("endpoint trust", async () =>
    {
        Require(ChatClient.Endpoint(local).AbsolutePath == "/v1/chat/completions", "Local path mismatch");
        foreach (var endpoint in new[] { "http://lan.example/v1", "https://u:p@example.com/v1", "file:///etc/v1", "https://example.com/v1?token=x" })
            await Throws<ArgumentException>(() => Task.FromResult(ChatClient.Endpoint(local with { Endpoint = endpoint })));
        Require(ChatClient.Endpoint(local with { Provider = ProviderKind.OpenAI, Endpoint = "https://example.test" }).Host == "api.openai.com", "Cloud account could redirect");
    });
    await Check("OpenAI-compatible SSE and request shape", async () =>
    {
        using var http = new HttpClient(new Fixture(async (request, token) =>
        {
            using var json = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            var root = json.RootElement;
            Require(root.GetProperty("model").GetString() == "fixture" && root.GetProperty("stream").GetBoolean(), "Request fields missing");
            Require(request.Headers.Authorization?.Parameter == "test-key", "Credential not set");
            Require(root.GetProperty("messages")[1].GetProperty("content").GetString()!.Contains("untrusted reference data"), "Missing data delineation");
            return Fixture.Stream("data: {\"choices\":[{\"delta\":{\"content\":\"Iris\"}}]}\n\ndata: [DONE]\n\n");
        }));
        Require(await Read(new(http), local, "test-key") == "Iris", "Incorrect delta");
    });
    await Check("Gemini streaming and thought suppression", async () =>
    {
        using var http = new HttpClient(new Fixture((request, _) =>
        {
            Require(request.Headers.Contains("x-goog-api-key") && request.RequestUri!.Host == "generativelanguage.googleapis.com", "Gemini credential misrouted");
            return Task.FromResult(Fixture.Stream("data: {\"candidates\":[{\"content\":{\"parts\":[{\"thought\":true,\"text\":\"private\"},{\"text\":\"Hi\"}]},\"finishReason\":\"STOP\"}]}\n\n"));
        }));
        Require(await Read(new(http), local with { Provider = ProviderKind.Gemini }, "test-key") == "Hi", "Thought content reached user");
    });
    await Check("interrupted stream requires completion evidence", async () =>
    {
        using var http = new HttpClient(new Fixture((_, _) => Task.FromResult(Fixture.Stream("data: {\"choices\":[{\"delta\":{\"content\":\"part\"}}]}\n\n"))));
        await Throws<EndOfStreamException>(() => Read(new(http), local));
    });
    await Check("SSE multiline and bounded events", async () =>
    {
        using var multi = new HttpClient(new Fixture((_, _) => Task.FromResult(Fixture.Stream("data: {\r\ndata: \"choices\":[{\"delta\":{\"content\":\"ok\"}}]}\r\n\r\ndata: [DONE]\r\n\r\n"))));
        Require(await Read(new(multi), local) == "ok", "Multiline JSON did not arrive");
        using var huge = new HttpClient(new Fixture((_, _) => Task.FromResult(Fixture.Stream("data: " + new string('x', 1048577)))));
        await Throws<InvalidDataException>(() => Read(new(huge), local));
    });
    await Check("provider quota error", async () =>
    {
        using var http = new HttpClient(new Fixture((_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.TooManyRequests))));
        await Throws<HttpRequestException>(() => Read(new(http), local));
    });
    await Check("Cloudflare request contract and JPEG envelope", async () =>
    {
        using var http = new HttpClient(new Fixture(async (request, token) =>
        {
            Require(request.RequestUri!.Host == "api.cloudflare.com" && request.Headers.Authorization?.Parameter == "fake-token", "Image credential misrouted");
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            Require(body.RootElement.GetProperty("steps").GetInt32() == 4, "Unexpected image steps");
            return Fixture.Stream("""{"success":true,"result":{"image":"/9j/2Q=="}}""");
        }));
        var key = new string('a', 32);
        Require((await new CloudflareImageClient(http).GenerateAsync(key, "fake-token", "Iris", default)).Length == 4, "Invalid output format");
        await Throws<ArgumentException>(() => new CloudflareImageClient(http).GenerateAsync(key, "fake-token", new string('x', 2049), default));
    });
    await Check("MCP handshake, session header, discovery and explicit call", async () =>
    {
        var count = 0;
        using var http = new HttpClient(new Fixture(async (request, token) =>
        {
            if (request.Method == HttpMethod.Delete)
            {
                Require(request.Headers.GetValues("Mcp-Session-Id").Single() == "test-session", "Delete lost session");
                return new HttpResponseMessage(HttpStatusCode.NoContent);
            }
            using var json = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            var input = json.RootElement;
            var method = input.GetProperty("method").GetString();
            if (method != "initialize")
                Require(request.Headers.GetValues("Mcp-Session-Id").Single() == "test-session" &&
                        request.Headers.GetValues("MCP-Protocol-Version").Single() == "2025-11-25", "Session headers missing");
            if (method == "notifications/initialized")
            {
                Require(!input.TryGetProperty("id", out _), "Notifications must not have IDs");
                return new HttpResponseMessage(HttpStatusCode.Accepted);
            }
            var id = input.GetProperty("id").GetInt32();
            var response = method switch
            {
                "initialize" => new { protocolVersion = "2025-11-25" },
                "tools/list" => (object)new { tools = new[] { new { name = "example", inputSchema = new { type = "object" } } } },
                "tools/call" => new { content = new[] { new { type = "text", text = "verified fixture" } } },
                _ => throw new InvalidDataException("Unexpected fixture request")
            };
            count++;
            var message = Fixture.Stream(JsonSerializer.Serialize(new { jsonrpc = "2.0", id, result = response }));
            if (method == "initialize") message.Headers.Add("Mcp-Session-Id", "test-session");
            return message;
        }));
        var client = new McpClient(http, McpClient.Endpoint("http://127.0.0.1:5200/mcp"), null);
        var tools = await client.ConnectAsync(default);
        Require(count == 2 && tools.Single().Name == "example", "Tool executed during discovery");
        await Throws<ArgumentException>(() => client.CallAsync(tools[0], "[]", default));
        Require((await client.CallAsync(tools[0], "{}", default)).Contains("verified fixture"), "Invalid tool result");
        await client.DisconnectAsync(default);
    });
    await Check("request cancellation", async () =>
    {
        using var http = new HttpClient(new Fixture(async (_, token) =>
        {
            await Task.Delay(TimeSpan.FromSeconds(10), token);
            return Fixture.Stream("");
        }));
        using var token = new CancellationTokenSource(TimeSpan.FromMilliseconds(50));
        await Throws<OperationCanceledException>(() => Read(new(http), local, cancellationToken: token.Token));
    });
}
finally { Directory.Delete(testPath, recursive: true); }
Console.WriteLine($"{count} checks passed.");

internal sealed class Fixture(Func<HttpRequestMessage,CancellationToken,Task<HttpResponseMessage>> response) : HttpMessageHandler
{
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        => response(request, cancellationToken);

    public static HttpResponseMessage Stream(string data) => new(HttpStatusCode.OK) { Content = new StringContent(data) };
}
