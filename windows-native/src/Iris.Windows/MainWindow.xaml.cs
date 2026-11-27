using System.Text;
using Iris.Core;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Automation;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Storage;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace Iris.Windows;

public sealed partial class MainWindow : Window
{
    private readonly HttpClient http = new(new SocketsHttpHandler { AllowAutoRedirect = false, ConnectTimeout = TimeSpan.FromSeconds(15) });
    private readonly StateStore store;
    private readonly UserVault vault;
    private readonly SemaphoreSlim saveGate = new(1);
    private readonly Dictionary<Guid, CancellationTokenSource> agentRuns = [];
    private readonly NativeSpeech speech = new();
    private readonly DesktopPresence presence;
    private Workspace workspace = Workspace.Empty();
    private Conversation? selected;
    private CancellationTokenSource? chatRequest;
    private CancellationTokenSource? desktopRequest;
    private CancellationTokenSource? imageRequest;
    private CancellationTokenSource? captureRequest;
    private CancellationTokenSource? mcpRequest;
    private McpClient? mcp;
    private Uri? mcpEndpoint;
    private byte[]? lastImage;
    private (string Name, string Text)? attachment;
    private bool started;
    private bool savingAllowed = true;
    private bool updatingHistory;
    private bool dictating;
    private bool closed;
    private static readonly string[] Accents = ["Apricot", "Lavender", "Sage", "Ocean"];

    public SolidColorBrush Accent { get; } = new(global::Windows.UI.Color.FromArgb(255, 234, 188, 143));

    public MainWindow()
    {
        InitializeComponent();
        var path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AriZe", "Iris");
        store = new(Path.Combine(path, "workspace.json"));
        vault = new(Path.Combine(path, "credentials"));
        AppWindow.Resize(new global::Windows.Graphics.SizeInt32(1030, 730));
        var icon = Path.Combine(AppContext.BaseDirectory, "Assets", "Iris.ico");
        if (File.Exists(icon)) AppWindow.SetIcon(icon);
        presence = new(this, Accent);
        AppTargets.ItemsSource = DesktopTools.Names;
        AppTargets.SelectedIndex = 0;
        ShortcutStatus.Text = presence.HasShortcut ? "Ctrl+Alt+Space brings Iris forward." : "Ctrl+Alt+Space is unavailable. Open Iris from the taskbar.";
        Closed += (_, _) =>
        {
            closed = true;
            chatRequest?.Cancel();
            desktopRequest?.Cancel();
            imageRequest?.Cancel();
            captureRequest?.Cancel();
            mcpRequest?.Cancel();
            foreach (var running in agentRuns.Values) running.Cancel();
            speech.Dispose();
            presence.Dispose();
            http.Dispose();
        };
    }

    private async void Start(object sender, RoutedEventArgs args)
    {
        if (started) return;
        started = true;
        try { workspace = await store.LoadAsync(); }
        catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException)
        {
            savingAllowed = false;
            Show("Workspace protected", "Saved data could not be read. Iris will keep the original file and will not save changes in this session.");
        }
        if (closed) return;
        Navigation.SelectedItem = ChatItem;
        PopulateSettings();
        UpdateHistory(workspace.Chats.FirstOrDefault());
        RenderMemories();
        RenderAgents();
    }

    private void Navigate(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        var tag = (args.SelectedItem as NavigationViewItem)?.Tag as string;
        ChatPage.Visibility = tag == "chat" ? Visibility.Visible : Visibility.Collapsed;
        AgentsPage.Visibility = tag == "agents" ? Visibility.Visible : Visibility.Collapsed;
        MemoryPage.Visibility = tag == "memory" ? Visibility.Visible : Visibility.Collapsed;
        ComputerPage.Visibility = tag == "computer" ? Visibility.Visible : Visibility.Collapsed;
        ImagePage.Visibility = tag == "images" ? Visibility.Visible : Visibility.Collapsed;
        McpPage.Visibility = tag == "mcp" ? Visibility.Visible : Visibility.Collapsed;
        SettingsPage.Visibility = tag == "settings" ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ChooseChat(object sender, SelectionChangedEventArgs args)
    {
        if (updatingHistory) return;
        if (chatRequest is not null) { UpdateHistory(selected); return; }
        selected = History.SelectedItem as Conversation;
        SetAttachment(null);
        RenderChat();
    }

    private void NewChat(object sender, RoutedEventArgs args)
    {
        if (chatRequest is not null) { Show("Chat is active", "Stop the current response first."); return; }
        Composer.Text = "";
        SetAttachment(null);
        UpdateHistory(null);
        Composer.Focus(FocusState.Programmatic);
    }

    private async void DeleteChat(object sender, RoutedEventArgs args)
    {
        if (selected is null || chatRequest is not null) return;
        var conversation = selected;
        var dialog = new ContentDialog
        {
            XamlRoot = Shell.XamlRoot, Title = "Delete this conversation?",
            Content = conversation.Title, PrimaryButtonText = "Delete", CloseButtonText = "Cancel"
        };
        if (await dialog.ShowAsync() != ContentDialogResult.Primary || chatRequest is not null) return;
        workspace.Chats.Remove(conversation);
        UpdateHistory(workspace.Chats.FirstOrDefault());
        await SaveAsync();
    }

    private async void Send(object sender, RoutedEventArgs args)
    {
        if (closed || !started || chatRequest is not null) return;
        var prompt = Composer.Text.Trim();
        if (prompt.Length is < 1 or > 12000) { Show("Message length", "Enter a message of 1 to 12,000 characters."); return; }
        if (prompt.StartsWith("@image ", StringComparison.OrdinalIgnoreCase))
        {
            if (prompt.Length > 2055) { Show("Image prompt length", "Use up to 2,048 characters after @image."); return; }
            Navigation.SelectedItem = ImageItem;
            ImagePrompt.Text = prompt[7..];
            Composer.Text = "";
            await CreateImageAsync();
            return;
        }
        if (prompt.StartsWith("@document ", StringComparison.OrdinalIgnoreCase))
            prompt = "Write a complete standalone document in Markdown.\n\n" + prompt[10..];
        string? key;
        var settings = workspace.Settings;
        try { _ = ChatClient.Endpoint(settings); key = vault.Read(settings.Provider); }
        catch (Exception error) { Show("Check Settings", error.Message); return; }

        var target = selected;
        if (target is null)
        {
            if (workspace.Chats.Count >= 100) { Show("History is full", "Export and remove an older conversation before starting another."); return; }
            target = new(Guid.NewGuid(), prompt.Length > 55 ? prompt[..55] + "…" : prompt, []);
            workspace.Chats.Insert(0, target);
        }
        var references = AssistantContext.RelevantMemory(prompt, workspace.Memories);
        if (attachment is { } textFile)
            references += $"\nExplicitly attached text ({textFile.Name}):\n{textFile.Text}";
        target.Messages.Add(new("user", attachment is { } file ? prompt + $"\n\n[Attached {file.Name}]" : prompt));
        Composer.Text = "";
        SetAttachment(null);
        using var source = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        chatRequest = source;
        StopButton.IsEnabled = true;
        SendButton.IsEnabled = false;
        UpdateEyes(18);
        UpdateHistory(target);
        Greeting.Visibility = Visibility.Collapsed;
        TranscriptScroll.Visibility = Visibility.Visible;
        var live = AppendMessage(new("assistant", "Working…"));
        var output = new StringBuilder();
        try
        {
            await SaveAsync();
            await foreach (var delta in new ChatClient(http).StreamAsync(settings, key, target.Messages, references, source.Token))
            {
                output.Append(delta);
                live.Text = output.ToString();
                ScrollToEnd();
            }
            target.Messages.Add(new("assistant", output.ToString()));
        }
        catch (OperationCanceledException)
        {
            if (output.Length > 0) target.Messages.Add(new("assistant", output + "\n\n[Response stopped]"));
            if (!closed) Show("Response stopped", "You can send another message.");
        }
        catch (Exception error)
        {
            if (output.Length > 0) target.Messages.Add(new("assistant", output + "\n\n[Response interrupted]"));
            if (!closed) Show("Response interrupted", Present(error));
        }
        finally
        {
            chatRequest = null;
            if (!closed)
            {
                StopButton.IsEnabled = false;
                SendButton.IsEnabled = true;
                UpdateEyes(24);
                RenderChat();
                await SaveAsync();
            }
        }
    }

    private void StopChat(object sender, RoutedEventArgs args) => chatRequest?.Cancel();

    private async void StartAgent(object sender, RoutedEventArgs args)
    {
        if (closed || !started) return;
        var task = AgentObjective.Text.Trim();
        if (task.Length is < 1 or > 12000) { Show("Agent objective", "Enter a task of 1 to 12,000 characters."); return; }
        if (agentRuns.Count >= 2) { Show("Agents are busy", "Stop or finish a task before starting another."); return; }
        if (workspace.Jobs.Count >= 60) { Show("Agent history is full", "Remove an older task before starting another."); return; }
        var settings = workspace.Settings;
        string? key;
        try { _ = ChatClient.Endpoint(settings); key = vault.Read(settings.Provider); }
        catch (Exception error) { Show("Check Settings", error.Message); return; }
        var name = task.Length > 38 ? task[..38] + "…" : task;
        var job = new AgentJob(Guid.NewGuid(), name, task, JobStatus.Running);
        workspace.Jobs.Insert(0, job);
        AgentObjective.Text = "";
        using var token = new CancellationTokenSource(TimeSpan.FromMinutes(2));
        agentRuns.Add(job.Id, token);
        RenderAgents();
        await SaveAsync();
        var answer = new StringBuilder();
        try
        {
            var context = AssistantContext.RelevantMemory(task, workspace.Memories);
            var request = new Message("user", "Work through this assignment and report your findings or draft.\n\n" + task);
            await foreach (var text in new ChatClient(http).StreamAsync(settings, key, [request], context, token.Token))
                answer.Append(text);
            FinishJob(job, JobStatus.Completed, answer.ToString());
        }
        catch (OperationCanceledException) { FinishJob(job, JobStatus.Stopped, answer.ToString()); }
        catch (Exception error) { FinishJob(job, JobStatus.Failed, Present(error)); }
        finally
        {
            agentRuns.Remove(job.Id);
            if (!closed) { RenderAgents(); await SaveAsync(); }
        }
    }

    private void FinishJob(AgentJob job, JobStatus status, string output)
    {
        var index = workspace.Jobs.FindIndex(item => item.Id == job.Id);
        if (index >= 0) workspace.Jobs[index] = job with { Status = status, Result = output };
    }

    private async void SaveMemory(object sender, RoutedEventArgs args)
    {
        var text = MemoryEntry.Text.Trim();
        if (text.Length is < 1 or > 500) { Show("Memory length", "Enter 1 to 500 characters."); return; }
        if (workspace.Memories.Count >= 250) { Show("Memory is full", "Remove an entry before adding another."); return; }
        workspace.Memories.Insert(0, new(Guid.NewGuid(), text));
        MemoryEntry.Text = "";
        RenderMemories();
        await SaveAsync();
    }

    private void RenderMemories()
    {
        MemoryList.Children.Clear();
        foreach (var memory in workspace.Memories)
        {
            var stack = new StackPanel { Spacing = 8 };
            stack.Children.Add(new TextBlock { Text = memory.Text, TextWrapping = TextWrapping.Wrap });
            var remove = new Button { Content = "Forget" };
            remove.Click += async (_, _) => { workspace.Memories.Remove(memory); RenderMemories(); await SaveAsync(); };
            stack.Children.Add(remove);
            MemoryList.Children.Add(Card(stack));
        }
    }

    private void RenderAgents()
    {
        AgentList.Children.Clear();
        foreach (var job in workspace.Jobs)
        {
            var stack = new StackPanel { Spacing = 9 };
            stack.Children.Add(new TextBlock { Text = job.Name + " · " + job.Status, TextWrapping = TextWrapping.Wrap, FontSize = 16 });
            if (job.Result.Length > 0)
                stack.Children.Add(new TextBlock { Text = job.Result, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true });
            var button = new Button { Content = job.Status == JobStatus.Running ? "Stop" : "Remove" };
            button.Click += async (_, _) =>
            {
                if (agentRuns.TryGetValue(job.Id, out var token)) token.Cancel();
                else { workspace.Jobs.RemoveAll(item => item.Id == job.Id); RenderAgents(); await SaveAsync(); }
            };
            stack.Children.Add(button);
            AgentList.Children.Add(Card(stack));
        }
    }

    private void UpdateHistory(Conversation? chat)
    {
        updatingHistory = true;
        selected = chat;
        History.ItemsSource = workspace.Chats.ToArray();
        History.SelectedItem = chat;
        updatingHistory = false;
        RenderChat();
    }

    private void RenderChat()
    {
        Transcript.Children.Clear();
        var hasMessages = selected?.Messages.Count > 0;
        Greeting.Visibility = hasMessages ? Visibility.Collapsed : Visibility.Visible;
        TranscriptScroll.Visibility = hasMessages ? Visibility.Visible : Visibility.Collapsed;
        if (selected is null) return;
        foreach (var message in selected.Messages.TakeLast(60)) AppendMessage(message);
        ScrollToEnd();
    }

    private TextBlock AppendMessage(Message message)
    {
        var text = new TextBlock { Text = message.Text, TextWrapping = TextWrapping.Wrap, IsTextSelectionEnabled = true, FontSize = 15 };
        var stack = new StackPanel { Spacing = 7 };
        var user = message.Role == "user";
        stack.Children.Add(new TextBlock
        {
            Text = user ? "You" : "Iris", FontWeight = Microsoft.UI.Text.FontWeights.SemiBold, Foreground = Accent
        });
        stack.Children.Add(text);
        if (!user)
        {
            var speak = new Button { Content = "Read aloud" };
            speak.Click += async (_, _) =>
            {
                try { await speech.SpeakAsync(text.Text); }
                catch (Exception) { if (!closed) Show("Voice unavailable", "Check your installed Windows voices."); }
            };
            stack.Children.Add(speak);
        }
        var card = Card(stack);
        card.HorizontalAlignment = user ? HorizontalAlignment.Right : HorizontalAlignment.Left;
        card.MaxWidth = 740;
        Transcript.Children.Add(card);
        return text;
    }

    private void ScrollToEnd() => DispatcherQueue.TryEnqueue(() =>
        TranscriptScroll.ChangeView(null, TranscriptScroll.ScrollableHeight, null, disableAnimation: true));

    private static Border Card(UIElement content) => new()
    {
        Child = content, Padding = new Thickness(15), CornerRadius = new CornerRadius(12),
        Background = new SolidColorBrush(global::Windows.UI.Color.FromArgb(255, 40, 38, 36))
    };

    private void SetAttachment((string Name, string Text)? file)
    {
        attachment = file;
        AttachmentLabel.Text = file is { } selection ? "Attached · " + selection.Name : "";
        AttachmentRow.Visibility = file is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private void RemoveAttachment(object sender, RoutedEventArgs args) => SetAttachment(null);

    private async void Attach(object sender, RoutedEventArgs args)
    {
        if (chatRequest is not null) return;
        try
        {
            var picker = new FileOpenPicker();
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
            foreach (var ext in new[] { ".txt", ".md", ".csv", ".json" }) picker.FileTypeFilter.Add(ext);
            var file = await picker.PickSingleFileAsync();
            if (file is null || closed) return;
            await using var input = await file.OpenStreamForReadAsync();
            if (input.Length > 32768) { Show("File too large", "Choose a text file of at most 32 KiB."); return; }
            using var reader = new StreamReader(input);
            var text = await reader.ReadToEndAsync();
            if (!closed && chatRequest is null) SetAttachment((file.Name, text));
        }
        catch (Exception) { if (!closed) Show("Attachment unavailable", "Iris could not read the selected text file."); }
    }

    private async void CaptureWindow(object sender, RoutedEventArgs args)
    {
        if (captureRequest is not null || chatRequest is not null || closed) return;
        using var source = new CancellationTokenSource();
        captureRequest = source;
        try
        {
            var text = await WindowCapture.ReadSelectedWindowAsync(WindowNative.GetWindowHandle(this), source.Token);
            if (text is null || closed || chatRequest is not null) return;
            if (text.Length == 0) { Show("No text found", "The selected content may be protected or contain no readable text."); return; }
            SetAttachment(("Selected screen text", text));
            Show("Screen text attached", "Review the selection and send it with a question. Iris attaches extracted text.");
        }
        catch (OperationCanceledException) { }
        catch (Exception error) { if (!closed) Show("Capture unavailable", Present(error)); }
        finally { captureRequest = null; }
    }

    private async void AttachScreenshot(object sender, RoutedEventArgs args)
    {
        if (chatRequest is not null || closed) return;
        try
        {
            var picker = new FileOpenPicker();
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
            foreach (var ext in new[] { ".png", ".jpg", ".jpeg", ".bmp" }) picker.FileTypeFilter.Add(ext);
            var file = await picker.PickSingleFileAsync();
            if (file is null || closed) return;
            var text = await DesktopTools.ReadScreenshotAsync(file);
            if (closed || chatRequest is not null) return;
            if (text.Length == 0) { Show("No text found", "Try a sharper screenshot or attach text instead."); return; }
            SetAttachment(($"OCR · {file.Name}", text));
        }
        catch (Exception error)
        {
            if (!closed) Show("Screenshot unavailable", error is InvalidDataException or InvalidOperationException
                ? error.Message : "Windows could not read text from the selected image.");
        }
    }

    private async void OpenApp(object sender, RoutedEventArgs args)
    {
        if (desktopRequest is not null || AppTargets.SelectedItem is not string app) return;
        using var source = new CancellationTokenSource();
        desktopRequest = source;
        OpenAppButton.IsEnabled = false;
        StopDesktopButton.IsEnabled = true;
        DesktopResult.Text = "Opening " + app + "…";
        presence.SetWorking(true);
        UpdateEyes(18);
        try
        {
            var observed = await DesktopTools.OpenAndObserveAsync(app, source.Token);
            if (!closed) DesktopResult.Text = observed
                ? $"Observed {app} in the foreground."
                : $"Asked Windows to open {app}, but Iris could not verify its window.";
        }
        catch (OperationCanceledException) { if (!closed) DesktopResult.Text = "Stopped checking the app window."; }
        catch (Exception) { if (!closed) DesktopResult.Text = $"Windows could not open {app}."; }
        finally
        {
            desktopRequest = null;
            if (!closed)
            {
                OpenAppButton.IsEnabled = true;
                StopDesktopButton.IsEnabled = false;
                presence.SetWorking(false);
                UpdateEyes(chatRequest is null ? 24 : 18);
            }
        }
    }

    private void StopDesktop(object sender, RoutedEventArgs args) => desktopRequest?.Cancel();

    private async void ExportChat(object sender, RoutedEventArgs args)
    {
        if (selected is null) return;
        var content = string.Join("\n\n", selected.Messages.Select(message => "## " + (message.Role == "user" ? "You" : "Iris") + "\n\n" + message.Text));
        try
        {
            var picker = new FileSavePicker { SuggestedFileName = "Iris conversation" };
            InitializeWithWindow.Initialize(picker, WindowNative.GetWindowHandle(this));
            picker.FileTypeChoices.Add("Markdown", [".md"]);
            var file = await picker.PickSaveFileAsync();
            if (file is not null) await FileIO.WriteTextAsync(file, content);
        }
        catch (Exception) { if (!closed) Show("Export failed", "Iris could not write the selected file."); }
    }

    private async void Dictate(object sender, RoutedEventArgs args)
    {
        if (dictating || closed) return;
        dictating = true;
        VoiceButton.IsEnabled = false;
        UpdateEyes(30);
        try
        {
            var transcript = await speech.DictateAsync();
            if (!closed && transcript.Length > 0) Composer.Text = (Composer.Text + " " + transcript).Trim();
        }
        catch (Exception) { if (!closed) Show("Dictation unavailable", "Check Windows microphone access and speech settings."); }
        finally
        {
            dictating = false;
            if (!closed) { VoiceButton.IsEnabled = true; UpdateEyes(chatRequest is null ? 24 : 18); }
        }
    }

    private void ProviderChanged(object sender, SelectionChangedEventArgs args)
    {
        if (EndpointField is not null) EndpointField.IsEnabled = Provider.SelectedIndex == 0;
        if (ApiKey is not null) ApiKey.Password = "";
    }

    private void PopulateSettings()
    {
        var settings = workspace.Settings;
        Provider.SelectedIndex = (int)settings.Provider;
        EndpointField.Text = settings.Endpoint;
        ModelField.Text = settings.Model;
        CloudflareAccount.Text = settings.CloudflareAccount;
        Theme.SelectedIndex = Math.Max(0, Array.IndexOf(Accents, settings.Accent));
        CapsuleToggle.IsOn = settings.Capsule;
        MotionToggle.IsOn = settings.ReduceMotion;
        Accent.Color = ThemeColor(settings.Accent);
        presence.Configure(settings.Capsule, settings.ReduceMotion);
    }

    private async void SaveSettings(object sender, RoutedEventArgs args)
    {
        if (!savingAllowed) { Show("Workspace protected", "Settings will not be saved while the workspace needs recovery."); return; }
        var settings = new Settings((ProviderKind)Math.Max(0, Provider.SelectedIndex), EndpointField.Text.Trim(), ModelField.Text.Trim(),
            Accents[Math.Clamp(Theme.SelectedIndex, 0, Accents.Length - 1)], CapsuleToggle.IsOn, MotionToggle.IsOn, CloudflareAccount.Text.Trim());
        try
        {
            if (!string.IsNullOrEmpty(settings.Model)) _ = ChatClient.Endpoint(settings);
            if (!string.IsNullOrWhiteSpace(ApiKey.Password)) vault.Save(settings.Provider, ApiKey.Password.Trim());
            if (!string.IsNullOrWhiteSpace(CloudflareToken.Password)) vault.SaveImageToken(CloudflareToken.Password.Trim());
            ApiKey.Password = "";
            CloudflareToken.Password = "";
            workspace = workspace with { Settings = settings };
            PopulateSettings();
            await SaveAsync();
        }
        catch (Exception error) { Show("Settings not saved", Present(error)); }
    }

    private void ClearKey(object sender, RoutedEventArgs args)
    {
        try
        {
            vault.Remove((ProviderKind)Math.Max(0, Provider.SelectedIndex));
            ApiKey.Password = "";
            Show("Key removed", "The selected provider’s saved credential was removed.");
        }
        catch (Exception) { Show("Key not removed", "Windows denied the credential operation."); }
    }

    private async Task SaveAsync()
    {
        if (!savingAllowed || closed) return;
        await saveGate.WaitAsync();
        try { if (!closed) await store.SaveAsync(workspace); }
        catch (Exception error) when (error is IOException or InvalidDataException or UnauthorizedAccessException)
        { if (!closed) Show("Save failed", "Iris could not write the workspace. Existing saved data was kept."); }
        finally { saveGate.Release(); }
    }

    private void UpdateEyes(double height)
    {
        LeftEye.Height = RightEye.Height = height;
        presence.SetEyeHeight(height * .45);
    }

    private void Show(string title, string text)
    {
        Notice.Title = title;
        Notice.Message = text;
        Notice.IsOpen = true;
    }

    private static string Present(Exception error) => error is ArgumentException or InvalidOperationException or HttpRequestException or InvalidDataException
        ? error.Message : "The operation could not finish. Check the provider or permission and try again.";

    private static global::Windows.UI.Color ThemeColor(string theme) => theme switch
    {
        "Lavender" => global::Windows.UI.Color.FromArgb(255, 192, 162, 246),
        "Sage" => global::Windows.UI.Color.FromArgb(255, 170, 201, 169),
        "Ocean" => global::Windows.UI.Color.FromArgb(255, 143, 190, 237),
        _ => global::Windows.UI.Color.FromArgb(255, 234, 188, 143)
    };
}
