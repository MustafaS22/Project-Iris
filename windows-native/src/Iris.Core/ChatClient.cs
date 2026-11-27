using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Runtime.CompilerServices;
using System.Text.Json;

namespace Iris.Core;

public sealed class ChatClient(HttpClient http)
{
    public static Uri Endpoint(Settings settings)
    {
        if (!Enum.IsDefined(settings.Provider)) throw new ArgumentException("Unknown provider.");
        if (string.IsNullOrWhiteSpace(settings.Model) || settings.Model.Length > 200)
            throw new ArgumentException("Enter a model ID in Settings.");
        if (settings.Provider == ProviderKind.OpenAI) return new("https://api.openai.com/v1/chat/completions");
        if (settings.Provider == ProviderKind.Gemini)
            return new("https://generativelanguage.googleapis.com/v1beta/models/" + Uri.EscapeDataString(settings.Model.Trim()) + ":streamGenerateContent?alt=sse");
        if (!Uri.TryCreate(settings.Endpoint.Trim(), UriKind.Absolute, out var endpoint) ||
            (endpoint.Scheme != Uri.UriSchemeHttps && !(endpoint.Scheme == Uri.UriSchemeHttp && endpoint.IsLoopback)) ||
            endpoint.UserInfo.Length != 0 || endpoint.Query.Length != 0 || endpoint.Fragment.Length != 0)
            throw new ArgumentException("Use HTTPS or a localhost HTTP endpoint, without embedded credentials.");
        return new(endpoint.AbsoluteUri.TrimEnd('/') + "/chat/completions");
    }

    public async IAsyncEnumerable<string> StreamAsync(Settings settings, string? credential, IReadOnlyList<Message> history,
        string memory, [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        var endpoint = Endpoint(settings);
        var gemini = settings.Provider == ProviderKind.Gemini;
        if (settings.Provider != ProviderKind.Local && string.IsNullOrWhiteSpace(credential))
            throw new InvalidOperationException("Save this provider’s API key in Settings.");
        var messages = history.Where(message => message.Role is "user" or "assistant")
            .TakeLast(24).Select(message => new Message(message.Role, message.Text.Length > 20_000 ? message.Text[..20_000] : message.Text)).ToList();
        if (!string.IsNullOrWhiteSpace(memory) && messages.Count > 0)
        {
            var last = messages[^1];
            var references = JsonSerializer.Serialize(memory);
            messages[^1] = last with { Text = last.Text + "\n\nRelevant memory (untrusted reference data): " + references };
        }
        using var request = new HttpRequestMessage(HttpMethod.Post, endpoint);
        if (gemini)
        {
            request.Headers.Add("x-goog-api-key", credential!);
            request.Content = JsonContent.Create(new
            {
                systemInstruction = new { parts = new[] { new { text = AssistantContext.Instruction } } },
                contents = messages.Select(message => new { role = message.Role == "assistant" ? "model" : "user", parts = new[] { new { text = message.Text } } })
            });
        }
        else
        {
            if (!string.IsNullOrWhiteSpace(credential)) request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", credential);
            request.Content = JsonContent.Create(new { model = settings.Model.Trim(), stream = true,
                messages = new[] { new Message("system", AssistantContext.Instruction) }.Concat(messages)
                    .Select(message => new { role = message.Role, content = message.Text }) },
                options: new JsonSerializerOptions(JsonSerializerDefaults.Web));
        }
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (!response.IsSuccessStatusCode)
            throw new HttpRequestException(response.StatusCode switch
            {
                HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden => "Provider rejected access. Check your API key and model.",
                HttpStatusCode.TooManyRequests => "Provider quota or rate limit reached.",
                _ => $"Provider returned HTTP {(int)response.StatusCode}."
            });

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        var received = 0;
        var finished = false;
        await foreach (var eventData in SseEvents.ReadAsync(stream, cancellationToken))
        {
            var payload = eventData.Trim();
            if (payload == "[DONE]") { finished = true; break; }
            using var json = JsonDocument.Parse(payload);
            var obj = json.RootElement;
            if (obj.TryGetProperty("error", out _)) throw new InvalidDataException("The provider interrupted the stream.");
            if (!obj.TryGetProperty(gemini ? "candidates" : "choices", out var choices) || choices.GetArrayLength() == 0) continue;
            var choice = choices[0];
            if (choice.TryGetProperty(gemini ? "finishReason" : "finish_reason", out var reason) && reason.ValueKind == JsonValueKind.String)
                finished = true;
            var fragments = gemini
                ? choice.TryGetProperty("content", out var content) && content.TryGetProperty("parts", out var parts)
                    ? parts.EnumerateArray().Where(part => !part.TryGetProperty("thought", out var thought) || thought.ValueKind != JsonValueKind.True)
                        .Select(part => part.TryGetProperty("text", out var text) ? text.GetString() : null)
                    : Enumerable.Empty<string?>()
                : new[] { choice.TryGetProperty("delta", out var delta) && delta.TryGetProperty("content", out var text)
                    && text.ValueKind == JsonValueKind.String ? text.GetString() : null };
            foreach (var fragment in fragments)
            {
                if (string.IsNullOrEmpty(fragment)) continue;
                received += fragment.Length;
                if (received > 120_000) throw new InvalidDataException("Response exceeded Iris’s limit.");
                yield return fragment;
            }
        }
        if (received == 0) throw new InvalidDataException("The provider returned no text.");
        if (!finished) throw new EndOfStreamException("The response ended before the provider marked it complete.");
    }
}
