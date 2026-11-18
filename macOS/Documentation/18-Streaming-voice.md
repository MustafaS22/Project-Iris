# Streaming voice and lower latency

Iris no longer waits for an entire answer and then a complete audio file before speaking it.

## Pipeline

- Gemini's Read answers as they arrive preference is enabled by default. It applies to typed answers and voice requests; the existing Speak replies after voice requests preference can still silence voice-request replies.
- As chat text streams in, Iris extracts stable public phrases and sentences. The first phrase is short for a quick start; later phrases are batched. It never speaks private reasoning, action transport, unfinished JSON or fenced code.
- Gemini TTS receives these phrases while the chat provider continues writing. The next phrase can synthesize while previous audio is playing. Generated text continues to display immediately and is not held back to match reading speed.
- Speech requests use stream=true and explicit 24 kHz mono signed 16-bit little-endian PCM output. Audio deltas reach an independent AVAudioEngine player as they arrive, with a small 100 ms jitter buffer. No full WAV download is required for live replies or Read aloud.
- Flash-Lite is now the low-latency default for users without an explicit saved speech model. Existing model selections are preserved; choose Flash-Lite in Settings → Voice for the faster option.
- There is a 2,000-character spoken-text budget and at most eight speech requests per reply. Short responses often need one. Requests are sent serially, without automatic retries, to avoid duplicate speech or unbounded API usage.
- Stop voice cancels queued and active client requests and discards scheduled audio. Stop response also stops speech. Later chat deltas cannot restart speech after Stop. A new conversation or microphone request clears old playback.
- Standard voice previews remain explicitly triggered and cached in memory. The selected chat provider and computer-action review rules are unchanged.

This provides phrase/sentence-level concurrency, not word-level alignment or karaoke highlighting. Gemini's initial server latency and the user's network still affect the first sound. Brief answers may finish writing before the first audio arrives; Iris cannot eliminate remote service latency. No live latency reduction is claimed without a real-account measurement.

## Validation

The Debug build succeeds. All 95 package tests pass. Eleven new tests cover early sentence release, exact-once ordering, hidden command/code/reasoning filtering, bounded speech requests, rewrite protection, fragmented PCM conversion, SSE framing/errors, and the stateless streaming request schema. A delayed local HTTP fixture proves the audio callback fires before the HTTP response completes. No Gemini generation or paid model call was made for this validation.

Official streaming specification:
https://ai.google.dev/gemini-api/docs/speech-generation#streaming-speech-generation
