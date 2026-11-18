# VoiceBox server compatibility

Iris supports VoiceBox 0.5.0 as well as newer servers with the OpenAI-compatible speech route.

When `/v1/audio/speech` returns 404, Iris checks the server API schema. Only a confirmed missing route enables the legacy `/generate` flow. A missing modern profile, server failure or timeout never triggers a second generation.

Legacy speech uses the selected profile language and configured engine, polls the returned job, then downloads its WAV audio. Personality rewriting stays off. Stop cancels the pending generation, and polling has a three-minute deadline. Playback speed is applied in Iris for consistent behavior on both APIs. VoiceBox must stay running.

Validation: the running VoiceBox 0.5.0 server produced a 3.475-second, 24 kHz mono WAV with a Kokoro profile. All 105 regression tests passed. The native Debug build succeeded.
