using Microsoft.UI.Xaml;

namespace Iris.Windows;

public partial class App : Application
{
    private MainWindow? main;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var owned = new Mutex(true, @"Local\AriZe.Iris.NativeWindows", out var first);
        if (!first) { owned.Dispose(); Exit(); return; }
        main = new MainWindow();
        main.Closed += (_, _) =>
        {
            owned.ReleaseMutex();
            owned.Dispose();
        };
        main.Activate();
    }
}
