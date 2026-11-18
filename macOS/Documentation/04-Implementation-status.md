> Superseded for onboarding, account callbacks, connections and notch behavior by 05-Revision-two.md. OpenAI sign-in and inference have now been verified.

# Iris implementation status and handoff
31 October 2026. This is the first working native slice, not the completed production JARVIS vision.

## Genuinely working / runtime verified
- Native SwiftUI/AppKit application builds and launches. Sandbox stays enabled. No Electron/web runtime or third-party dependencies.
- Borderless notch surface with a convincing collapsed/expanded shape, original procedural avatar, hover/click/keyboard activation, state-driven layout and a connected auxiliary workspace.
- First-run profile/interests survey, themes, optional permission explanations, knowledge-source setup/test, interaction guide and onboarding completion.
- Focus goal/start/pause, persisted remaining time, restart recovery in paused state, end confirmation, history and actual elapsed-time summary. Verified on an isolated validation profile.
- Local note capture and Knowledge listing; save and persistence verified in the app. Notes support copy, explicit context attachment and confirmed removal.
- LM Studio's real HTTP model discovery and inference path. Runtime connection attempt against the default endpoint correctly reported that no server was running. No model was configured here, so live model answer generation remains unverified against LM Studio itself.
- Desktop workspace navigation from the notch. A validation-discovered keyboard-focus issue was fixed: ongoing notch updates no longer make the panel key repeatedly.
- Event-driven network/battery status and optional foreground app metadata. The signed app's outgoing-client/read-selected-files/microphone entitlements were inspected; **no incoming-network entitlement is present**.

## Implemented, requiring device/permission/configuration validation
- Explicit voice transcription with Apple Speech, visible mic state, stop/cancel, 60-second resource timeout, and AVSpeechSynthesizer read-aloud. Permission denial paths are present. Microphone/speech permission was not granted during this task; no audio recorded.
- File-picker text/PDF extraction and image OCR with Vision, reviewable attachment text, explicit model submission. PDF scanning limitation is explained; text extraction is limited to 40 pages / 18,000 characters.
- Explicit allowed-app ScreenCaptureKit capture with local OCR. Screen Recording not granted; capture not exercised. Browser/password/banking identifiers are denied even if manually allowlisted; all other applications also default to denied.
- Multi-activity priority router; focus, processing, capture, errors and completion are real activity sources. No fabricated call/music/download widgets.
- Reduced-motion behavior and full-screen suppression logic; physical monitor arrangements, games/presentations and VoiceOver still require hardware QA. Full-screen detection uses a public-API visible-frame heuristic, not a guaranteed platform signal.
- Horizontal top-edge drag can select another display and reanchor; swipe up/down collapses/opens. Arbitrary positioning away from the notch is intentionally not exposed.

## Partially implemented / blocked
Cloud account adapters are present in `AccountService.swift` and `CloudModelService.swift`: PKCE, random state/nonce, system-browser flow, IPv4 loopback callback, OIDC RSA signature/issuer/audience/expiry/nonce checks, scope check, Keychain persistence, refresh, account-model discovery, OpenAI Responses stream terminal-event validation and Gemini generation. No API-key field is shown.

**Callback execution is disabled by `AccountService.callbackEnabled = false`.** Automatic approval review rejected adding the sandbox incoming-network capability because it broadens network exposure and was not specifically approved. The project has no server entitlement; no listener starts. Sign-in controls are disabled with an explanation. Explicit approval is required before enabling this capability and validating real accounts.

Concrete proposed permission change: add `com.apple.security.network.server = true` to `Configuration/Iris.entitlements` and enable the account callback gate. The implemented listener binds **127.0.0.1 only**, not all interfaces; accepts only a bounded GET `/auth/callback` with matching random state; exposes no command routes; expires after 180 seconds and closes on cancellation/completion. This permission is coarse at the OS sandbox level even though the code narrows the bind address. Review and test listener cancellation/flood handling before release. Do not enable without the requested approval.

OpenAI uses the official dynamic registration for eligible local/open-source clients, not another application's client ID. Eligibility and real-account inference have not been tested. Gemini additionally requires developer-owned `IRISGoogleClientID`, `IRISGoogleClientSecret` if required by the desktop registration, and `IRISGoogleProjectID` Info.plist configuration, plus an enabled Generative Language API and OAuth consent/verification. End users should not configure developer credentials in a production release.

## Mocked
None in production. Unit tests use URLProtocol HTTP fixtures and generated test-only RSA keys; those fixtures are not linked into the app. The `--iris-validation` argument changes only the local storage path to a temporary validation directory. It does not simulate integrations or seed production content.

## Not built yet
- Android/iOS companion, authenticated pairing and relay. The security model is designed in document 03; no connection is falsely claimed and no relay listens.
- Camera stream/still capture (user-selected images are supported), calendar and system Reminders integration, media playback integration, Bluetooth, system volume/brightness HUDs, file shelf/drop, stopwatch, weather, world clocks and conversions.
- Autonomous project building, arbitrary computer control, cross-app editing, approvals/execution sandbox, safe workflow runner and sending messages. The model is deliberately given no execution authority; it cannot falsely claim tool completion.
- Scheduled sessions/deadlines, opt-in distraction/stuck detection, adaptive tutoring/flashcards, semantic knowledge retrieval and mature long-term memory.
- Breathing/grounding exercise flow, crisis-response workflow, stress sensing (no emotion detection claims are made).
- Notarized distribution, update channel, localization, exhaustive accessibility audit and Instruments energy benchmarks.

## Configuration and run
Open the existing `Project IRIS.xcodeproj`; build and run scheme `Project IRIS`. Deployment floor is macOS 15; development was performed with Xcode 27.2. The project uses Xcode 27's `project.xcproj` representation. Source Material remains intact on disk but was removed from the navigator's recursive nested-project indexing to stop unrelated package resolution.

Menu-bar sparkle → Open Iris or Iris workspace. Shortcut: Control–Option–Space. In Knowledge Source, start LM Studio, load a chat model, enter its server URL and exact model identifier, then **Test connection & confirm**. The test verifies discovery and sends one actual inference request. The test must be repeated after launch or configuration changes. Local timers and notes work without a provider.

Storage: application sandbox's Application Support/Project IRIS/state.json; atomic writes. Decode failures preserve the original file and show a repair message; writes remain off until repaired. Conversation/attached context remain in memory. Credentials, if account support is later approved, use Keychain. No analytics or telemetry dependency is linked.

## Validation evidence
- Native Debug build succeeds with ad-hoc signing; entitlement inspection confirms sandbox/client/selected-file/microphone permissions and no network server permission.
- 23 core/integration tests pass from the delivered project after the final changes: clock behavior, recovery, priority, expiry, quiet/cooldown policy, context exclusion, URL validation, capability policy, model success/HTTP error/invalid JSON/empty answer, PKCE RFC vector, form encoding, signed-ID success, tamper/expiry/nonce/audience rejection, callback-disabled guard, and nonzero/negative-origin display geometry. A fresh Release clean build also succeeds. Final test/build results are recorded in validation.txt.
- Actual app visually inspected: onboarding and expanded notch; no clipping in inspected layouts. Tested onboarding completion without model setup, real unavailable-server error, focus start/pause/restart recovery/end/save/history, note capture and Knowledge listing, and notch-to-workspace navigation. Validation data is isolated from normal profile storage.
- Not yet validated: live provider answers, OAuth browser completion, speech/camera/screen permission grant, physical multi-monitor disconnect, full-screen games, VoiceOver and energy/CPU targets.

## Next work
First resolve the OAuth callback approval and Google app registration, then validate account flows with the user. Add camera and explicit safe-tool approval/execution slices; implement a real companion before enabling pairing UI. Continue through the roadmap and hardware matrix before calling the product production-ready.

## Primary integration references
- [OpenAI local-client sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [OpenAI plan model discovery and inference](https://developers.openai.com/siwc/token-sharing-open-source/models-and-inference)
- [Gemini OAuth](https://ai.google.dev/gemini-api/docs/oauth)
- [LM Studio API](https://lmstudio.ai/docs/developer/openai-compat)
- [Apple incoming-network entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.network.server)
