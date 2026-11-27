using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;

namespace Iris.Core;

public sealed class CloudflareImageClient(HttpClient http)
{
    public async Task<byte[]> GenerateAsync(string accountId, string token, string prompt, CancellationToken cancellationToken)
    {
        if (accountId.Length != 32 || accountId.Any(character => !char.IsAsciiHexDigit(character)))
            throw new ArgumentException("Enter a 32-character Cloudflare Account ID.");
        if (string.IsNullOrWhiteSpace(token)) throw new ArgumentException("Save a Workers AI API token.");
        prompt = prompt.Trim();
        if (prompt.Length is < 1 or > 2048) throw new ArgumentException("Use 1 to 2,048 characters for the image prompt.");

        using var request = new HttpRequestMessage(HttpMethod.Post,
            $"https://api.cloudflare.com/client/v4/accounts/{accountId}/ai/run/@cf/black-forest-labs/flux-1-schnell");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
        request.Content = JsonContent.Create(new { prompt, steps = 4 });
        using var response = await http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
        if (!response.IsSuccessStatusCode)
            throw new HttpRequestException($"Cloudflare could not generate the image (HTTP {(int)response.StatusCode}).");
        await response.Content.LoadIntoBufferAsync(25_000_000, cancellationToken);
        using var json = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(cancellationToken),
            cancellationToken: cancellationToken);
        var root = json.RootElement;
        if (!root.TryGetProperty("success", out var success) || success.ValueKind != JsonValueKind.True ||
            !root.TryGetProperty("result", out var result) || !result.TryGetProperty("image", out var image) ||
            !image.TryGetBytesFromBase64(out var raw) || raw.Length < 4 || raw[0] != 0xff || raw[1] != 0xd8)
            throw new InvalidDataException("Cloudflare returned no supported JPEG image.");
        return raw;
    }
}
