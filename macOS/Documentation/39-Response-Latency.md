# Faster first responses

Ordinary assistant calls previously included the full Iris identity, computer-action schema, document-generation rules, floating-screen instructions, and Studio descriptions, even for greetings and short factual questions.

ResponsePromptPolicy now selects a compact instruction for clear, short, standalone greetings, arithmetic and general explanation/definition questions. It preserves personality, formatting, truthful action reporting, live-data rules and supplied reference data. It never introduces a second model call, changes the selected model, or reduces output limits.

Requests with Studio skills, images, attachments, floating guidance, tool/action terms, personal references or follow-up language retain the full prompt. Unrecognized requests also retain the full prompt. Both cloud and local model services use the same policy. Existing token streaming remains enabled.

Installed-browser discovery is cached for 30 seconds rather than consulting Launch Services and inspecting every browser bundle on every question. Newly installed or removed browsers appear after the cache expires.

Validation: all 177 package tests passed, including routing regressions for actions, follow-ups, attachments and screen guidance. Debug build verified separately. No paid model calls or real-server latency benchmark was performed. This reduces request preprocessing and input size; inference/network latency remains provider-dependent.
