using System.Diagnostics;
using System.Runtime.InteropServices;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage;

namespace Iris.Windows;

internal static class DesktopTools
{
    private static readonly IReadOnlyDictionary<string, (string Launch, string Process)> Apps =
        new Dictionary<string, (string, string)>(StringComparer.OrdinalIgnoreCase)
        {
            ["Notepad"] = ("notepad.exe", "notepad"),
            ["File Explorer"] = ("explorer.exe", "explorer"),
            ["Microsoft Edge"] = ("microsoft-edge:", "msedge"),
            ["Windows Settings"] = ("ms-settings:", "SystemSettings")
        };

    public static string[] Names => Apps.Keys.ToArray();

    public static async Task<bool> OpenAndObserveAsync(string selection, CancellationToken token)
    {
        if (!Apps.TryGetValue(selection, out var app)) throw new ArgumentException("Choose an Iris-supported application.");
        using var launched = Process.Start(new ProcessStartInfo(app.Launch) { UseShellExecute = true });
        for (var attempt = 0; attempt < 32; attempt++)
        {
            token.ThrowIfCancellationRequested();
            if (ForegroundProcessIs(app.Process)) return true;
            await Task.Delay(250, token);
        }
        return false;
    }

    private static bool ForegroundProcessIs(string processName)
    {
        var window = GetForegroundWindow();
        if (window == 0) return false;
        _ = GetWindowThreadProcessId(window, out var id);
        if (id == 0) return false;
        try
        {
            using var process = Process.GetProcessById((int)id);
            return string.Equals(process.ProcessName, processName, StringComparison.OrdinalIgnoreCase);
        }
        catch (ArgumentException) { return false; }
        catch (InvalidOperationException) { return false; }
    }

    public static async Task<string> ReadScreenshotAsync(StorageFile file)
    {
        if ((await file.GetBasicPropertiesAsync()).Size > 20 * 1024 * 1024)
            throw new InvalidDataException("Choose an image smaller than 20 MiB.");
        using var stream = await file.OpenReadAsync();
        return await ReadScreenshotAsync(await BitmapDecoder.CreateAsync(stream));
    }

    internal static async Task<string> ReadScreenshotAsync(BitmapDecoder decoder)
    {
        var edge = Math.Min(OcrEngine.MaxImageDimension, 2800);
        var ratio = Math.Min(1.0, (double)edge / Math.Max(decoder.PixelWidth, decoder.PixelHeight));
        var transform = new BitmapTransform
        {
            ScaledWidth = Math.Max(1u, (uint)(decoder.PixelWidth * ratio)),
            ScaledHeight = Math.Max(1u, (uint)(decoder.PixelHeight * ratio))
        };
        using var bitmap = await decoder.GetSoftwareBitmapAsync(BitmapPixelFormat.Bgra8, BitmapAlphaMode.Ignore,
            transform, ExifOrientationMode.RespectExifOrientation, ColorManagementMode.DoNotColorManage);
        var engine = OcrEngine.TryCreateFromUserProfileLanguages()
            ?? throw new InvalidOperationException("Install an OCR-compatible Windows language pack.");
        var result = await engine.RecognizeAsync(bitmap);
        return result.Text.Length <= 20_000 ? result.Text : result.Text[..20_000];
    }

    [DllImport("user32")] private static extern nint GetForegroundWindow();
    [DllImport("user32")] private static extern uint GetWindowThreadProcessId(nint hwnd, out uint processId);
}
