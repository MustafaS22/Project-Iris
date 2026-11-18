# Gemini speech economy

## Defaults

Economy speech is on when the new preference is absent, including existing installations. It sends at most one Gemini speech request per reply and speaks an opening excerpt of at most 360 characters. Full written answers remain in chat. This is deterministic excerpt selection, not an extra model-generated summary. Stable excerpts can begin speaking before the answer finishes.

Previously a long answer could trigger up to eight separate sentence/chunk requests. Full speech remains available by disabling Economy speech in Voice settings; it retains the existing 2,000-character limit.

Typed chats no longer generate automatic speech unless Also speak typed chats is enabled. Voice-request replies still honor Speak replies after voice requests. Floating Iris continues speaking regardless of these two toggles. Manual read-aloud remains available and honors the saved Economy choice.

## Request conservation

Successful reply PCM is cached in memory, bounded to 8 MB, keyed by transcript, voice, model, delivery and authorization mode. Replaying an identical excerpt can use cached audio without calling Google. Partial or failed audio is never cached. Audio is not persisted to disk. Preview samples are shorter, and the existing preview cache remains in use.

HTTP 429 starts a local cooldown of at least 60 seconds (longer when Google's numeric Retry-After header requests it). No automatic retry is sent. New uncached voice generation is blocked during the cooldown; text answers and cached audio remain usable. This cooldown is not an assertion that a daily quota has reset.

Google enforces separate request/token/time-window quotas per project, not per API key. Iris cannot replenish Google's allowance or infer a precise remaining balance from a generic 429. See https://ai.google.dev/gemini-api/docs/rate-limits.

## Validation

Debug build passed. All 183 existing and economy regression tests passed before adding one further targeted quota cooldown regression. Economy tests cover one request across incremental updates, bounded text, early stable speech, no duplicate final request, hidden actions, and typed/voice/floating routing. No live API key was used and no paid audio was generated for testing.
