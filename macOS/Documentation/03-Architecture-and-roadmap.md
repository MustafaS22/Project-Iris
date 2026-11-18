# Architecture, security and delivery
Written before implementation.

## 10. Technical architecture
AppKit AppDelegate owns lifecycle, notch panel, menu bar and auxiliary workspace. SwiftUI reads a main-actor observable Iris Orchestrator. Pure Foundation core contains session clocks, activity ranking, context policy, provider URL validation, proactive policy and capability contracts; test independently with SwiftPM. No third-party packages in application target.

Modules:
- Shell: borderless nonactivating key-capable NSPanel, black content, correct per-screen origin. Safe-area inset + auxiliary top areas determine notch dimensions; artificial notch for other displays. Rebuild placement on display/sleep/wake events.
- UI: notch surface, original stateful avatar, onboarding, native workspace for notes/history/settings. Controls call orchestrator actions, never view-local fake completions.
- Study: wall-clock deadline with preserved remainder, local snapshots after mutations, interruption recovery remains paused on launch. System sleep does not accumulate timer drift; elapsed wall time applies while active. Summary uses recorded duration, never invented learning outcomes.
- AI: provider protocol, cancellable URLSession requests, bounded transcript/context, honest transport/model/HTTP errors. LM Studio first; OAuth adapters require supported registrations and provider contracts. No model may execute shell commands or send messages on its own.
- Context: foreground app notifications only with opt-in. No window titles/AX tree captured passively. Sensitive apps protected by allowlist policy: explicit app opt-in required before screen capture, browser capture disabled by default because incognito cannot be reliably distinguished from public app APIs. Read only a user-selected file or screenshot. OCR with Vision and PDFKit, size bounds, preview and explicit submission.
- Voice: AVAudioEngine + Speech initiated by user, permissions checked individually, mic indicator and stop control; Apple recognition can require network depending on language/device. TTS uses AVSpeechSynthesizer. No always-listening wake word.
- Memory: Codable local file in Application Support, atomic writes and visible persistence errors. No telemetry. Store provider secrets only in Keychain. Notes/history/preferences remain local; users can remove local records.
- Permissions: microphone, speech, screen recording, accessibility reported independently; no startup permission barrage. Camera integration is a later slice, never falsely marked active. App sandbox with network client, user-selected read-only files, microphone entitlement; do not request broad disk access.
- Diagnostics: os.Logger categories for lifecycle/integrations, operation/result only, no prompts/context/tokens in logs. User-visible errors accompany failed operations.
- Offline: timers/notes/files continue; network model requests explain the error; no fake AI fallback. Local deterministic commands are labeled as tools.

Capability registry schema: name, description, required permission(s), platforms, risk, confirmation policy, offline behavior, failure behavior, audit policy. Available now should be distinguishable from designed/later. Higher-risk external actions remain unavailable until a preview/approval/execution boundary exists. Local utility parsing is explicit, not an autonomous computer-use claim.

## 11. Cross-device security model
A proposed protocol, not a shipped companion: discover with Bonjour only after explicit enablement; pair using ephemeral X25519 keys, QR fingerprint, user confirmation on both devices, 2-minute expiring challenge and pinned public keys in Keychain. TLS 1.3 transport + authenticated encrypted messages, per-device capability grants, monotonic sequence numbers, nonce/replay cache, message expiry, 64 KB bound, strict typed schema, rate limits and revocation. No unauthenticated HTTP command server. Phone focus controls require Android permissions and platform-specific DND restrictions; iOS cannot arbitrarily control other apps. Screen, microphone, files and messages are separate scopes and off by default. Sending/remote actions need confirmation and audit. Test wrong fingerprints, replay, stale sequence, reconnect, lost device, revoked permissions and malicious payloads before enabling. This slice must state “companion not connected / not yet available,” not display fake pairing codes.

## 12. Phased roadmap
1. Research and architecture artifacts, clean dependency boundary.
2. Native notch shell + stateful avatar + auxiliary workspace and first-run survey.
3. Study clock/history/recovery + notes + deterministic safe tools, unit coverage.
4. Real model setup/test/chat with cancellation, local file/image extraction, explicit voice/context permissions.
5. Cloud OAuth adapters tested against real user authorization; calendar/reminders/media with real permission paths; camera capture.
6. Companion applications and audited authenticated transport; scoped computer-control approvals and sandboxed developer workflows.
7. Hardware matrix, VoiceOver review, Instruments idle/active power measurements, signed/notarized distribution and user testing.
Do not equate phase 4 with the entire JARVIS product. Report actual implementation status after validation.

## 13. Risk register
| Risk | Mitigation / release gate |
|---|---|
| Oversized product scope | Vertical slices, visible availability, explicit remaining work |
| Reference licensing | Original source, no assets copied; review notices before any reuse |
| OAuth availability changes | Supported provider flows only, no borrowed client IDs or cookie scraping |
| Screen privacy / incognito | Default deny, explicit app allowlist, no browser passive capture |
| Prompt injection from documents | Context is untrusted content; models have no execution authority |
| Timer loss or clock changes | Absolute deadlines, pause on recovery, pure transition tests |
| Overlay blocks app/menu input | Tight panel bounds; collapse hitbox; hardware/VoiceOver QA |
| Multi-display/full-screen behavior | Safe-area geometry, display notification, explicit invocation policy |
| Idle energy | No idle animation/timers; observer-driven integrations; profile before release |
| Local data loss/corruption | Atomic writes, preserve failed decode file, actionable error |
| Speech/camera privacy | Explicit request/start/stop, persistent indicator, release resources |
| Remote command abuse | No exposed transport until pairing/replay/revocation tests pass |
| Emotional harm | No diagnosis or dependency framing; concise supportive exercises only |
| Distribution | Signing/notarization and permission identity must be validated on installed build |

## 14. Test strategy
Pure Swift tests: session elapsed/pause/resume/completion/relaunch, overdue timers, activity priority/expiry, quiet hours crossing midnight, proactive cooldown, URL validation (reject credentials/non-HTTPS remote endpoints), context default deny, registry metadata and capability risk. HTTP integration: URLProtocol fixture or local explicit test server for invalid model, bad HTTP, invalid JSON, cancellation and success; test fixtures never used in production. Build native target from clean derived data.

Manual matrix: physical notch/non-notch; external monitor above/left of main, disconnect/reconnect; normal/full-screen/presentation; reduced motion/VoiceOver/increased contrast; fresh/returning onboarding; denied microphone/speech/screen; offline model endpoint; empty notes/files; corrupt storage; sleep/wake timer; paused interruption; multiple simultaneous activities; output speech stop; keyboard-only access. Hardware results must be marked unverified until performed. Inspect screenshots of actual running views and fix clipping/layout issues.

## 15. Definition of done
For each slice: builds, real action connected to every visible control, persisted state where appropriate, errors visible, permissions contextual, tests for core behavior, no mock production responses, no hidden telemetry. Product release additionally requires the complete brief's cross-device, camera, media/reminder, computer-control and cloud authentication acceptance criteria plus real hardware/performance/accessibility QA. Explicitly list every unmet criterion in the delivery status; never call the full product done prematurely.
