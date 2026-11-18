# Live responses and task status

Iris now displays answer text while it arrives instead of waiting for the complete response. Desktop chat, notch chat and Studio share the same live-answer view, with elapsed time and observed stages: connecting, waiting for the response, writing an answer, or preparing an action/study artifact. These are operational status labels, not fabricated reasoning or a private thought transcript.

OpenAI exposes public response-text deltas; Gemini uses streamGenerateContent with SSE; LM Studio uses streaming chat completions. Provider reasoning events/fields are ignored. Local inline think/analysis/reasoning tags are removed. Partial fenced blocks and JSON objects are held until they can be classified, preventing action payloads or incomplete study JSON from flashing in chat. Requested code blocks appear once complete. Action parsing runs only after a successfully completed response, with reasoning removed.

Updates are throttled to roughly eight per second and kept outside persisted conversation history until completion. The existing offline Markdown/math renderer updates its DOM rather than reloading the entire document per fragment. Stop preserves visible partial text with a stopped marker. Interrupted responses preserve visible text with an interruption marker and do not apply an incomplete action plan. No simulated typing delay or extra model request is added.

Validation: Debug build succeeded; all 57 focused tests passed. New tests verify partial text before completion, reasoning-field exclusion across providers, every prefix of a reasoning/action response, partial JSON/code handling and interrupted-response behavior. A real local HTTP SSE fixture sent two delayed chunks through ModelService: the first visible text callback arrived before completion, with three callbacks total. Offline WebKit Markdown/math and hostile-content checks still passed. Strict code-signature verification passed. No paid provider requests were made; live provider latency and a complete UI walkthrough were not re-tested.

Primary protocol references:
- https://developers.openai.com/api/docs/guides/streaming-responses
- https://ai.google.dev/api/generate-content
- https://lmstudio.ai/docs/developer/openai-compat/chat-completions
