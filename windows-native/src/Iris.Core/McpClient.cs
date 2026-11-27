using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;

namespace Iris.Core;

public sealed record McpTool(string Name, string Description, string InputSchema)
{
    public override string ToString() => Name;
}

/// A session is bound to one reviewed endpoint. The model does not get access to this client.
public sealed class McpClient(HttpClient http, Uri endpoint, string? credential)
{
    private const string Version = "2025-11-25";
    private const int MaxBody = 1_048_576;
    private string? sessionId;
    private string? negotiated;
    private int nextId;

    public static Uri Endpoint(string address)
    {
        if (!Uri.TryCreate(address.Trim(), UriKind.Absolute, out var uri) ||
            (uri.Scheme != "https" && !(uri.Scheme == "http" && uri.IsLoopback)) ||
            uri.UserInfo.Length != 0 || uri.Fragment.Length != 0 || uri.Query.Length != 0)
            throw new ArgumentException("Use HTTPS or localhost HTTP, with no embedded credentials or query.");
        return uri;
    }

    public async Task<IReadOnlyList<McpTool>> ConnectAsync(CancellationToken token)
    {
        if (negotiated is not null) throw new InvalidOperationException("Reconnect with a new MCP session.");
        var initialization = await PostAsync("initialize", new
        {
            protocolVersion = Version,
            capabilities = new { },
            clientInfo = new { name = "Iris", version = "2.0.0-rc.1" }
        }, false, token);
        negotiated = initialization.GetProperty("protocolVersion").GetString();
        if (negotiated is not (Version or "2025-06-18" or "2025-03-26"))
            throw new InvalidOperationException("The endpoint requested an unsupported MCP protocol.");
        _ = await PostAsync("notifications/initialized", new { }, true, token);
        var tools = new List<McpTool>();
        string? cursor = null;
        for (var page = 0; page < 4; page++)
        {
            var result = await PostAsync("tools/list", cursor is null ? new { } : (object)new { cursor }, false, token);
            foreach (var tool in result.GetProperty("tools").EnumerateArray())
            {
                var name = tool.GetProperty("name").GetString();
                if (string.IsNullOrEmpty(name) || name.Length > 128) continue;
                var schema = tool.GetProperty("inputSchema").GetRawText();
                if (schema.Length > 16000) continue;
                var description = tool.TryGetProperty("description", out var text) ? text.GetString() ?? "" : "";
                tools.Add(new(name, Limit(description, 1000), schema));
                if (tools.Count >= 100) return tools;
            }
            if (!result.TryGetProperty("nextCursor", out var next) || string.IsNullOrEmpty(cursor = next.GetString()))
                break;
        }
        return tools;
    }

    public async Task<string> CallAsync(McpTool tool, string arguments, CancellationToken token)
    {
        if (negotiated is null) throw new InvalidOperationException("Connect to the MCP endpoint first.");
        if (arguments.Length > 16000) throw new ArgumentException("Tool arguments may contain at most 16,000 characters.");
        using var parsed = JsonDocument.Parse(arguments);
        if (parsed.RootElement.ValueKind != JsonValueKind.Object) throw new ArgumentException("Tool arguments must be a JSON object.");
        var result = await PostAsync("tools/call", new { name = tool.Name, arguments = parsed.RootElement }, false, token);
        if (result.TryGetProperty("isError", out var error) && error.ValueKind == JsonValueKind.True)
            throw new InvalidOperationException("The MCP server reported a tool error.");
        return Limit(result.GetRawText(), 32000);
    }

    public async Task DisconnectAsync(CancellationToken token)
    {
        if (sessionId is null) return;
        using var request = Request(HttpMethod.Delete);
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        sessionId = null;
    }

    private HttpRequestMessage Request(HttpMethod method)
    {
        var request = new HttpRequestMessage(method, endpoint);
        request.Headers.Accept.ParseAdd("application/json");
        request.Headers.Accept.ParseAdd("text/event-stream");
        if (!string.IsNullOrWhiteSpace(credential)) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential);
        if (negotiated is not null) request.Headers.Add("MCP-Protocol-Version", negotiated);
        if (sessionId is not null) request.Headers.Add("Mcp-Session-Id", sessionId);
        return request;
    }

    private async Task<JsonElement> PostAsync(string method, object data, bool notification, CancellationToken token)
    {
        var id = Interlocked.Increment(ref nextId);
        using var request = Request(HttpMethod.Post);
        request.Content = JsonContent.Create(notification ? new { jsonrpc = "2.0", method, @params = data }
            : (object)new { jsonrpc = "2.0", method, @params = data, id });
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (!response.IsSuccessStatusCode) throw new HttpRequestException($"MCP request failed (HTTP {(int)response.StatusCode}).");
        if (method == "initialize" && response.Headers.TryGetValues("Mcp-Session-Id", out var values))
        {
            var value = values.FirstOrDefault();
            if (value is null || value.Length > 256 || value.Any(character => character < '!' || character > '~'))
                throw new InvalidDataException("Invalid MCP session identifier.");
            sessionId = value;
        }
        if (notification) return default;
        await using var input = await response.Content.ReadAsStreamAsync(token);
        var stream = response.Content.Headers.ContentType?.MediaType == "text/event-stream";
        if (stream)
        {
            var budget = MaxBody;
            await foreach (var payload in SseEvents.ReadAsync(input, token))
            {
                budget -= payload.Length + 1;
                if (budget < 0) throw new InvalidDataException("MCP response exceeded the size limit.");
                if (ReadResult(payload, id) is { } result)
                    return result;
            }
            throw new EndOfStreamException("MCP sent no result for the request.");
        }

        using var buffer = new MemoryStream();
        var chunk = new byte[8192];
        while (await input.ReadAsync(chunk, token) is var count && count > 0)
        {
            if (buffer.Length + count > MaxBody) throw new InvalidDataException("MCP response exceeded the size limit.");
            buffer.Write(chunk, 0, count);
        }
        return ReadResult(Encoding.UTF8.GetString(buffer.ToArray()), id)
            ?? throw new InvalidDataException("MCP returned an unrelated response.");
    }

    private static JsonElement? ReadResult(string body, int id)
    {
        using var document = JsonDocument.Parse(body);
        var root = document.RootElement;
        if (!root.TryGetProperty("id", out var responseId) || responseId.ValueKind != JsonValueKind.Number ||
            !responseId.TryGetInt32(out var actual) || actual != id) return null;
        if (root.TryGetProperty("error", out _)) throw new InvalidOperationException("The MCP server rejected this request.");
        return root.GetProperty("result").Clone();
    }

    private static string Limit(string value, int length) => value.Length <= length ? value : value[..length];
}
