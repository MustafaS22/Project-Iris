using System.Runtime.CompilerServices;
using System.Text;

namespace Iris.Core;

internal static class SseEvents
{
    public static async IAsyncEnumerable<string> ReadAsync(Stream input,
        [EnumeratorCancellation] CancellationToken cancellationToken)
    {
        const int maxCharacters = 1_048_576;
        using var reader = new StreamReader(input, Encoding.UTF8, leaveOpen: true);
        var chunk = new char[4096];
        var line = new StringBuilder();
        var data = new StringBuilder();
        while (await reader.ReadAsync(chunk.AsMemory(), cancellationToken) is var count && count > 0)
        {
            for (var i = 0; i < count; i++)
            {
                var character = chunk[i];
                if (character != '\n')
                {
                    if (line.Length >= maxCharacters) throw new InvalidDataException("Provider event exceeded the size limit.");
                    line.Append(character);
                    continue;
                }
                if (line.Length > 0 && line[^1] == '\r') line.Length--;
                if (line.Length == 0)
                {
                    if (data.Length > 0)
                    {
                        yield return data.ToString();
                        data.Clear();
                    }
                }
                else
                {
                    var field = line.ToString();
                    if (field.StartsWith("data:", StringComparison.Ordinal))
                    {
                        var start = field.Length > 5 && field[5] == ' ' ? 6 : 5;
                        var length = field.Length - start;
                        if (data.Length + length + 1 > maxCharacters)
                            throw new InvalidDataException("Provider event exceeded the size limit.");
                        if (data.Length > 0) data.Append('\n');
                        data.Append(field, start, length);
                    }
                }
                line.Clear();
            }
        }
    }
}
