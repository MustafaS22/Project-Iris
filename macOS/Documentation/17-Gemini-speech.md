# Gemini natural voice

Gemini is now Iris's preferred voice provider when no explicit voice-provider choice has been saved. VoiceBox and macOS voices remain selectable alternatives. Speech is independent of the chat provider: OpenAI, Gemini or LM Studio can write the response, then Gemini TTS reads its public text.

## Setup

Open Settings → Voice → Gemini. Add a Google AI Studio API key (saved only in Keychain), or choose Connected Gemini account and authorize the Gemini API project. Gmail authorization alone does not grant speech API access. API key access is the default setup path. No credentials are bundled in the app.

The default voice is Sulafat (Warm), with all 30 documented prebuilt voices available. Six voices appear initially; All 30 voices expands the list. Choose a voice without generating audio, then press its Preview button. Styles are Natural, Warm, Calm and Focused. Flash-Lite is now the low-latency default for users without a saved model; Flash remains available. See 18-Streaming-voice.md. Playback speed is adjustable. Previewing another voice does not change the saved voice selection.

Microphone requests speak replies when Speak replies after voice requests is enabled. The notch's Read aloud control uses the same selected provider. Live replies and Read aloud now stream PCM instead of waiting for a full WAV file; see 18-Streaming-voice.md. Stop cancels pending client generation and playback; a cancelled response cannot start playing later. No automatic network retry or silent system-voice fallback occurs.

## API and privacy

The connector uses Google's documented Interactions API with gemini-3.8-flash-tts or gemini-3.8-flash-lite-tts. It sends a text-only transcript, separate speech_metadata delivery instructions, one configured voice, explicit WAV output and store=false. It never sends chat tools or executes actions from a speech response. Only completed model_output audio blocks with valid WAV framing are accepted.

API keys use x-goog-api-key. Connected-account access uses the existing Gemini OAuth bearer token and configured Google Cloud quota project. That project's API availability, quota, billing and model permissions still apply. OAuth speech access has not been exercised against a live account in this validation.

Only the public spoken reply is sent, limited to 2,000 characters. Internal action data, code fences and basic Markdown markers are removed. Repeated previews are cached in memory, with a six-entry cap; regular reply audio is not cached. Google API charges and quotas may apply, including previews. This is cloud speech and requires internet. It does not bundle voice models or reuse the Gemini consumer app's subscription allowance.

## Verification

The Debug build succeeds and all 84 package tests pass. Eight Gemini speech tests cover the exact request schema, stateless storage setting, separate authentication paths, 30 distinct voices, valid and invalid audio responses, quota errors without retries, and cancellation. Native settings were inspected in the running app: Gemini, API key setup, speech model, delivery, voice rows and Preview controls render correctly. No live Gemini speech request was made because no speech API credential was provided for this test.

Official references:
- https://ai.google.dev/gemini-api/docs/speech-generation
- https://ai.google.dev/api/interactions-api
- https://ai.google.dev/gemini-api/docs/oauth
- https://ai.google.dev/gemini-api/docs/pricing
