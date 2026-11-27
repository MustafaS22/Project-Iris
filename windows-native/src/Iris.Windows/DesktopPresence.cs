using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Media.Animation;
using Windows.Graphics;
using WinRT.Interop;

namespace Iris.Windows;

internal sealed class DesktopPresence : IDisposable
{
    private readonly MainWindow main;
    private readonly Window capsule = new();
    private readonly Border left;
    private readonly Border right;
    private readonly Border activityBorder;
    private readonly Brush accent;
    private readonly ScaleTransform leftScale = new();
    private readonly ScaleTransform rightScale = new();
    private readonly DispatcherTimer blink = new() { Interval = TimeSpan.FromSeconds(5.1) };
    private readonly nint handle;
    private readonly SubclassProc subclass;
    private readonly WinEventProc foreground;
    private readonly nint eventHook;
    private bool enabled;
    private bool closing;

    public bool HasShortcut { get; }

    public DesktopPresence(MainWindow main, Brush accent)
    {
        this.main = main;
        this.accent = accent;
        left = Eye(accent, leftScale);
        right = Eye(accent, rightScale);
        var eyes = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 5, HorizontalAlignment = HorizontalAlignment.Center };
        eyes.Children.Add(left);
        eyes.Children.Add(right);
        var button = new Button
        {
            Content = eyes, CornerRadius = new CornerRadius(14), HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Stretch, Background = new SolidColorBrush(global::Windows.UI.Color.FromArgb(255, 15, 14, 14))
        };
        Microsoft.UI.Xaml.Automation.AutomationProperties.SetName(button, "Open Iris");
        button.Click += (_, _) => BringForward();
        activityBorder = new Border
        {
            CornerRadius = new CornerRadius(17), Padding = new Thickness(2),
            Child = button
        };
        capsule.Content = new Grid { Children = { activityBorder }, RequestedTheme = ElementTheme.Dark };
        capsule.Title = "Iris capsule";
        var presenter = OverlappedPresenter.Create();
        presenter.SetBorderAndTitleBar(false, false);
        presenter.IsAlwaysOnTop = true;
        presenter.IsResizable = presenter.IsMaximizable = presenter.IsMinimizable = false;
        capsule.AppWindow.SetPresenter(presenter);
        capsule.AppWindow.IsShownInSwitchers = false;
        capsule.AppWindow.Closing += (_, args) =>
        {
            if (closing) return;
            args.Cancel = true;
            capsule.AppWindow.Hide();
        };
        blink.Tick += (_, _) => Blink();
        handle = WindowNative.GetWindowHandle(main);
        subclass = HandleMessage;
        HasShortcut = SetWindowSubclass(handle, subclass, 1, 0) && RegisterHotKey(handle, 1, 0x4003, 0x20);
        foreground = (_, _, hwnd, _, _, _, _) =>
        {
            if (hwnd != 0 && enabled) main.DispatcherQueue.TryEnqueue(Refresh);
        };
        eventHook = SetWinEventHook(3, 3, 0, foreground, 0, 0, 0);
        main.AppWindow.Changed += (_, args) => { if (args.DidPositionChange && enabled) Refresh(); };
    }

    public void Configure(bool show, bool reduceMotion)
    {
        enabled = show;
        if (show && !reduceMotion) blink.Start();
        else blink.Stop();
        Refresh();
    }

    public void SetEyeHeight(double height) => left.Height = right.Height = height;

    public void SetWorking(bool working)
    {
        activityBorder.BorderThickness = working ? new Thickness(1.5) : new Thickness(0);
        activityBorder.BorderBrush = working ? accent : null;
    }

    private void Blink()
    {
        if (!capsule.AppWindow.IsVisible) return;
        foreach (var target in new[] { leftScale, rightScale })
        {
            var animation = new DoubleAnimation
            {
                To = 0.23, Duration = new Duration(TimeSpan.FromMilliseconds(85)), AutoReverse = true,
                EnableDependentAnimation = true
            };
            Storyboard.SetTarget(animation, target);
            Storyboard.SetTargetProperty(animation, "ScaleY");
            var storyboard = new Storyboard();
            storyboard.Children.Add(animation);
            storyboard.Begin();
        }
    }

    private void BringForward()
    {
        if (closing) return;
        if (main.AppWindow.Presenter is OverlappedPresenter presenter && presenter.State == OverlappedPresenterState.Minimized)
            presenter.Restore();
        main.Activate();
    }

    private void Refresh()
    {
        if (closing) return;
        if (!enabled || ForegroundIsFullscreen()) { capsule.AppWindow.Hide(); return; }
        var area = DisplayArea.GetFromWindowId(main.AppWindow.Id, DisplayAreaFallback.Primary).WorkArea;
        var scale = Math.Max(96u, GetDpiForWindow(handle)) / 96.0;
        var width = (int)Math.Round(94 * scale);
        var height = (int)Math.Round(37 * scale);
        capsule.AppWindow.MoveAndResize(new RectInt32(area.X + (area.Width - width) / 2, area.Y + 8, width, height));
        if (!capsule.AppWindow.IsVisible) capsule.AppWindow.Show(false);
    }

    private bool ForegroundIsFullscreen()
    {
        var window = GetForegroundWindow();
        if (window == 0 || window == handle || window == WindowNative.GetWindowHandle(capsule)) return false;
        var area = DisplayArea.GetFromWindowId(Microsoft.UI.Win32Interop.GetWindowIdFromWindow(window), DisplayAreaFallback.None);
        if (area is null || !GetWindowRect(window, out var rect)) return false;
        var monitor = area.OuterBounds;
        return rect.Left <= monitor.X && rect.Top <= monitor.Y &&
            rect.Right >= monitor.X + monitor.Width && rect.Bottom >= monitor.Y + monitor.Height;
    }

    private nint HandleMessage(nint hwnd, uint message, nuint wParam, nint lParam, nuint id, nuint data)
    {
        if (message == 0x0312 && wParam == 1)
        {
            main.DispatcherQueue.TryEnqueue(BringForward);
            return 0;
        }
        return DefSubclassProc(hwnd, message, wParam, lParam);
    }

    private static Border Eye(Brush accent, ScaleTransform transform) => new()
    {
        Width = 5, Height = 11, CornerRadius = new CornerRadius(2.5), Background = accent,
        RenderTransform = transform, RenderTransformOrigin = new global::Windows.Foundation.Point(0.5, 0.5)
    };

    public void Dispose()
    {
        if (closing) return;
        closing = true;
        blink.Stop();
        if (eventHook != 0) UnhookWinEvent(eventHook);
        if (HasShortcut) UnregisterHotKey(handle, 1);
        RemoveWindowSubclass(handle, subclass, 1);
        capsule.Close();
    }

    private delegate nint SubclassProc(nint hwnd, uint message, nuint wParam, nint lParam, nuint id, nuint data);
    private delegate void WinEventProc(nint hook, uint eventType, nint hwnd, int objectId, int childId, uint thread, uint time);
    [StructLayout(LayoutKind.Sequential)] private struct WindowRect { public int Left, Top, Right, Bottom; }

    [DllImport("comctl32")] private static extern bool SetWindowSubclass(nint hwnd, SubclassProc callback, nuint id, nuint data);
    [DllImport("comctl32")] private static extern bool RemoveWindowSubclass(nint hwnd, SubclassProc callback, nuint id);
    [DllImport("comctl32")] private static extern nint DefSubclassProc(nint hwnd, uint message, nuint wParam, nint lParam);
    [DllImport("user32")] private static extern bool RegisterHotKey(nint hwnd, int id, uint modifiers, uint key);
    [DllImport("user32")] private static extern bool UnregisterHotKey(nint hwnd, int id);
    [DllImport("user32")] private static extern uint GetDpiForWindow(nint hwnd);
    [DllImport("user32")] private static extern nint GetForegroundWindow();
    [DllImport("user32")] private static extern bool GetWindowRect(nint hwnd, out WindowRect rectangle);
    [DllImport("user32")] private static extern nint SetWinEventHook(uint min, uint max, nint module, WinEventProc callback, uint process, uint thread, uint flags);
    [DllImport("user32")] private static extern bool UnhookWinEvent(nint hook);
}
