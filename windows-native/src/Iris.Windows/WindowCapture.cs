using System.Runtime.InteropServices;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;
using WinRT;
using WinRT.Interop;

namespace Iris.Windows;

internal static class WindowCapture
{
    public static async Task<string?> ReadSelectedWindowAsync(nint owner, CancellationToken token)
    {
        if (!GraphicsCaptureSession.IsSupported())
            throw new InvalidOperationException("Windows Graphics Capture is unavailable on this device.");
        var picker = new GraphicsCapturePicker();
        InitializeWithWindow.Initialize(picker, owner);
        var item = await picker.PickSingleItemAsync();
        if (item is null) return null;
        token.ThrowIfCancellationRequested();
        if (item.Size.Width is < 1 or > 8192 || item.Size.Height is < 1 or > 8192 ||
            (long)item.Size.Width * item.Size.Height > 24_000_000)
            throw new InvalidOperationException("Choose a smaller window or display.");

        using var device = CreateDevice();
        using var pool = Direct3D11CaptureFramePool.CreateFreeThreaded(device, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, item.Size);
        using var session = pool.CreateCaptureSession(item);
        var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        void Arrived(Direct3D11CaptureFramePool sender, object args) => ready.TrySetResult();
        void Closed(GraphicsCaptureItem sender, object args) => ready.TrySetException(new InvalidOperationException("The selected capture target closed."));
        pool.FrameArrived += Arrived;
        item.Closed += Closed;
        try
        {
            session.StartCapture();
            await ready.Task.WaitAsync(TimeSpan.FromSeconds(8), token);
            using var frame = pool.TryGetNextFrame();
            if (frame is null) throw new InvalidOperationException("Windows returned no frame for the selected target.");
            using var bitmap = await SoftwareBitmap.CreateCopyFromSurfaceAsync(frame.Surface);
            token.ThrowIfCancellationRequested();
            session.Dispose();
            using var buffer = new InMemoryRandomAccessStream();
            var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, buffer);
            encoder.SetSoftwareBitmap(bitmap);
            await encoder.FlushAsync();
            buffer.Seek(0);
            return await DesktopTools.ReadScreenshotAsync(await BitmapDecoder.CreateAsync(buffer));
        }
        finally
        {
            item.Closed -= Closed;
            pool.FrameArrived -= Arrived;
        }
    }

    private static IDirect3DDevice CreateDevice()
    {
        const uint bgraSupport = 0x20;
        const uint sdkVersion = 7;
        var hr = D3D11CreateDevice(0, 1, 0, bgraSupport, 0, 0, sdkVersion, out var device, 0, 0);
        if (hr < 0) hr = D3D11CreateDevice(0, 5, 0, bgraSupport, 0, 0, sdkVersion, out device, 0, 0);
        Marshal.ThrowExceptionForHR(hr);

        var deviceInterface = new Guid("54EC77FA-1377-44E6-8C32-88FD5F44C84C");
        try
        {
            Marshal.ThrowExceptionForHR(Marshal.QueryInterface(device, in deviceInterface, out var dxgi));
            try
            {
                Marshal.ThrowExceptionForHR(CreateDirect3D11DeviceFromDXGIDevice(dxgi, out var inspectable));
                try { return MarshalInterface<IDirect3DDevice>.FromAbi(inspectable); }
                finally { Marshal.Release(inspectable); }
            }
            finally { Marshal.Release(dxgi); }
        }
        finally { Marshal.Release(device); }
    }

    [DllImport("d3d11.dll")]
    private static extern int D3D11CreateDevice(nint adapter, uint driverType, nint software, uint flags,
        nint levels, uint levelCount, uint sdkVersion, out nint device, nint featureLevel, nint context);
    [DllImport("d3d11.dll")]
    private static extern int CreateDirect3D11DeviceFromDXGIDevice(nint dxgi, out nint device);
}
