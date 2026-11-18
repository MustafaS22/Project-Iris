# VoiceBox speech

Iris now supports VoiceBox's local speech API alongside the existing macOS voice engine.

Settings → Voice provides local server configuration, profile discovery, individual voice previews, profile selection, playback speed and Stop. Both spoken replies after microphone requests and notch Read aloud use the chosen engine. Gemini is now the preferred engine when no explicit engine preference exists; VoiceBox and macOS voices remain selectable. See 17-Gemini-speech.md. There is no silent fallback.

## Setup

1. Install and open VoiceBox from https://voicebox.sh.
2. Download an engine and configure a voice profile in VoiceBox. Kokoro is a lightweight option; Qwen offers expressive voices.
3. In Iris Settings → Voice, select VoiceBox, keep its local address (default http://127.0.0.1:17493), and press Refresh voices.
4. Select a profile and use Preview voice. Keep VoiceBox running for speech.

The connector uses GET /profiles and POST /v1/audio/speech. The documented tts-1 alias selects the profile's configured local engine; it does not call OpenAI. Voices are discovered from VoiceBox, not copied from its website. Iris does not create or clone voice profiles.

Reply text is sent only to the configured loopback endpoint. The connector rejects remote addresses, credentials in URLs, URL query strings and HTTP redirects. It sends no API keys. Speech strips internal action blocks, code fences and basic Markdown formatting, with a 2,000-character cap. WAV bytes are validated before native audio playback. Preview audio is cached in memory for up to six combinations; replies are not cached. Stop cancels the client request and prevents delayed playback, but VoiceBox may finish synthesis on its server after a client disconnect. Changing voice or starting microphone input stops existing playback.

## Validation

The Debug app builds. All 76 package tests pass. Eight new tests cover loopback validation, profile discovery, request serialization, speech cleanup, actual WAV decoding, invalid responses, offline errors and cancellation. No paid voice calls were made. VoiceBox was not installed or running, so a live natural-voice preview has not been verified. This build does not bundle speech model weights.

## Alternatives discussed

Kokoro can be embedded with model weights, voice data, a runtime and text phonemization. An audio recording alone cannot synthesize new sentences. Gemini TTS is implemented as the preferred cloud option in 17-Gemini-speech.md. ElevenLabs is not implemented. Gemini Live would require a separate conversational-audio integration.

Sources:
- https://github.com/jamiepine/voicebox/blob/main/backend/routes/openai_compat.py
- https://github.com/jamiepine/voicebox/blob/main/backend/routes/profiles.py
- https://huggingface.co/hexgrad/Kokoro-82M
- https://ai.google.dev/gemini-api/docs/speech-generation
- https://elevenlabs.io/docs/overview/capabilities/text-to-speech
