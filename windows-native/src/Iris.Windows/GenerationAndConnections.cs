using Iris.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage;
using Windows.Storage.Pickers;
using Windows.Storage.Streams;
using WinRT.Interop;

namespace Iris.Windows;

public sealed partial class MainWindow
{
    private async void GenerateImage(object sender, RoutedEventArgs args) => await CreateImageAsync();

    private async Task CreateImageAsync()
    {
        if (closed || imageRequest is not null) return;
        using var source = new CancellationTokenSource(TimeSpan.FromMinutes(4));
        imageRequest = source;
        GenerateButton.IsEnabled = false;
        StopImageButton.IsEnabled = true;
        ImageProgress.IsActive = true;
        ImageProgress.Visibility = Visibility.Visible;
        try
        {
            var token = vault.ReadImageToken() ?? throw new InvalidOperationException("Add a Workers AI token in Settings.");
            var bytes = await new CloudflareImageClient(http).GenerateAsync(workspace.Settings.CloudflareAccount, token, ImagePrompt.Text, source.Token);
            using var stream = new InMemoryRandomAccessStream();
            using var writer = new DataWriter(stream);
            writer.WriteBytes(bytes);
            _ = await writer.StoreAsync();
            writer.DetachStream();
            stream.Seek(0);
            var image = new BitmapImage();
            await image.SetSourceAsync(stream);
            source.Token.ThrowIfCancellationRequested();
            if (!closed)
            {
                GeneratedImage.Source = image;
                lastImage = bytes;
                SaveImageButton.IsEnabled = true;
            }
        }
        catch (OperationCanceledException) { if (!closed) Show("Generation stopped", "Cloudflare may already have counted the request."); }
        catch (Exception error) { if (!closed) Show("Image generation failed", Present(error)); }
        finally
        {
            imageRequest = null;
            if (!closed)
            {
                GenerateButton.IsEnabled = true;
                StopImageButton.IsEnabled = false;
                ImageProgress.IsActive = false;
                ImageProgress.Visibility = Visibility.Collapsed;
            }
        }
    }

    private void StopImage(object sender, RoutedEventArgs args) => imageRequest?.Cancel();

    private async void SaveImage(object sender, RoutedEventArgs args)
    {
        if (lastImage is not { } bytes || closed) return;
        try
        {
            var picker = new FileSavePicker { SuggestedFileName = "Iris image" };
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
            picker.FileTypeChoices.Add("JPEG image", [".jpg"]);
            var file = await picker.PickSaveFileAsync();
            if (file is not null) await FileIO.WriteBytesAsync(file, bytes);
        }
        catch (Exception) { if (!closed) Show("Save failed", "Iris could not save the image at the selected location."); }
    }

    private void ClearImageKey(object sender, RoutedEventArgs args)
    {
        try { vault.RemoveImageToken(); CloudflareToken.Password = ""; Show("Token removed", "The Workers AI token was removed."); }
        catch (Exception) { Show("Token not removed", "Windows denied the credential operation."); }
    }

    private async void ConnectMcp(object sender, RoutedEventArgs args)
    {
        if (closed || mcpRequest is not null || mcp is not null) return;
        using var source = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        mcpRequest = source;
        ConnectMcpButton.IsEnabled = false;
        try
        {
            var endpoint = McpClient.Endpoint(McpAddress.Text);
            var client = new McpClient(http, endpoint, McpToken.Password.Trim());
            McpToken.Password = "";
            var tools = await client.ConnectAsync(source.Token);
            if (closed) return;
            mcp = client;
            mcpEndpoint = endpoint;
            McpAddress.IsEnabled = false;
            McpToken.IsEnabled = false;
            McpTools.ItemsSource = tools;
            McpTools.SelectedIndex = tools.Count > 0 ? 0 : -1;
            McpResult.Text = $"{tools.Count} tools discovered.";
            DisconnectMcpButton.IsEnabled = true;
        }
        catch (Exception error) { if (!closed) Show("MCP connection failed", Present(error)); }
        finally
        {
            mcpRequest = null;
            if (!closed)
            {
                ConnectMcpButton.IsEnabled = mcp is null;
                CallMcpButton.IsEnabled = McpTools.SelectedItem is McpTool;
            }
        }
    }

    private async void DisconnectMcp(object sender, RoutedEventArgs args)
    {
        if (mcp is not { } client || mcpRequest is not null) return;
        mcp = null;
        mcpEndpoint = null;
        using var source = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        mcpRequest = source;
        McpTools.ItemsSource = null;
        McpResult.Text = "Disconnected.";
        DisconnectMcpButton.IsEnabled = false;
        try { await client.DisconnectAsync(source.Token); }
        catch (Exception) { }
        finally
        {
            mcpRequest = null;
            if (!closed) { ConnectMcpButton.IsEnabled = McpAddress.IsEnabled = McpToken.IsEnabled = true; }
        }
    }

    private void SelectMcpTool(object sender, SelectionChangedEventArgs args)
    {
        var tool = McpTools.SelectedItem as McpTool;
        McpDescription.Text = tool is null ? "" : tool.Description + "\n" + tool.InputSchema;
        CallMcpButton.IsEnabled = tool is not null && mcpRequest is null;
    }

    private async void CallMcp(object sender, RoutedEventArgs args)
    {
        if (mcp is not { } client || mcpRequest is not null || McpTools.SelectedItem is not McpTool tool || mcpEndpoint is null) return;
        var argsJson = McpArguments.Text;
        var dialog = new ContentDialog
        {
            XamlRoot = Shell.XamlRoot,
            Title = "Call external tool?",
            Content = new ScrollViewer { Content = new TextBlock { Text = $"{mcpEndpoint}\n{tool.Name}\n\n{argsJson}", TextWrapping = TextWrapping.Wrap }, MaxHeight = 260 },
            PrimaryButtonText = "Call tool",
            CloseButtonText = "Cancel"
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary || closed || mcp != client || mcpRequest is not null) return;
        using var source = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        mcpRequest = source;
        CallMcpButton.IsEnabled = DisconnectMcpButton.IsEnabled = false;
        try
        {
            var response = await client.CallAsync(tool, argsJson, source.Token);
            if (!closed) McpResult.Text = response;
        }
        catch (Exception error) { if (!closed) Show("MCP tool failed", Present(error)); }
        finally
        {
            mcpRequest = null;
            if (!closed) { DisconnectMcpButton.IsEnabled = true; CallMcpButton.IsEnabled = McpTools.SelectedItem is McpTool; }
        }
    }
}
