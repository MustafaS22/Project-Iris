using Windows.Media.Core;
using Windows.Media.Playback;
using Windows.Media.SpeechRecognition;
using Windows.Media.SpeechSynthesis;

namespace Iris.Windows;

internal sealed class NativeSpeech : IDisposable
{
    private SpeechSynthesizer? synthesizer;
    private MediaPlayer? player;
    private SpeechSynthesisStream? audio;
    private CancellationTokenSource? utterance;
    private bool disposed;

    public async Task<string> DictateAsync()
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        using var instance = new SpeechRecognizer();
        instance.Constraints.Add(new SpeechRecognitionTopicConstraint(SpeechRecognitionScenario.Dictation, "dictation"));
        if ((await instance.CompileConstraintsAsync()).Status != SpeechRecognitionResultStatus.Success)
            throw new InvalidOperationException("Windows dictation could not initialize.");
        if (disposed) return "";
        var result = await instance.RecognizeWithUIAsync();
        return result.Status == SpeechRecognitionResultStatus.Success ? result.Text : "";
    }

    public async Task SpeakAsync(string text)
    {
        ObjectDisposedException.ThrowIf(disposed, this);
        utterance?.Cancel();
        var output = player ??= new MediaPlayer { AutoPlay = false };
        var voice = synthesizer ??= new SpeechSynthesizer();
        output.Pause();
        output.Source = null;
        audio?.Dispose();
        audio = null;
        using var token = new CancellationTokenSource();
        utterance = token;
        try
        {
            var next = await voice.SynthesizeTextToStreamAsync(text.Length > 4000 ? text[..4000] : text);
            if (disposed || token.IsCancellationRequested) { next.Dispose(); return; }
            audio = next;
            output.Source = MediaSource.CreateFromStream(next, next.ContentType);
            output.Play();
        }
        finally
        {
            if (utterance == token) utterance = null;
        }
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        utterance?.Cancel();
        player?.Dispose();
        audio?.Dispose();
        synthesizer?.Dispose();
    }
}
