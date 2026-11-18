# Iris revision 3 — shared Google registration, interface redesign and testing
31 October 2026, Asia/Dubai.

This report supersedes revision 2 where it describes Google configuration and interface layout.

## Delivered in Project IRIS

- Bundled the user-supplied **Google Desktop OAuth registration** as an app resource. Fresh installations use it directly. Gmail, Drive, Google Calendar and Gemini no longer require each user to import a client JSON. Explicit developer overrides remain under troubleshooting and can be switched back to the bundled registration.
- Added a Google account chooser, actionable access-denied recovery, fixed-client callback identity handling, and safeguards against refreshing tokens or carrying refresh tokens across changed client registrations.
- Added **App testing** to the desktop sidebar. It replays full onboarding, AI setup, knowledge setup or the notch tour. It also opens each real notch mode and shows connection-check status. Replays preserve notes, knowledge and credentials; they do not send model requests or start focus sessions automatically.
- Redesigned the notch around the supplied HeyClicky references: black top-anchored surface, compact mode switch, clear greeting, polished pill actions, conversation bubbles, voice action and text composer. Iris keeps its original eye avatar.
- Redesigned standalone onboarding with a step rail and fixed footer. Redesigned the desktop with a charcoal sidebar, shared dark tokens, readable source rows and a dedicated testing surface. Opening the workspace hides the notch; Back to the notch brings it back.
- Preserved the stable native notch canvas and single SwiftUI animation owner. Reduced Motion remains supported. No frame-rate measurement is claimed.

## Google issue diagnosed

The attached error is a Google consent access block, not an absent JSON file. During inspection, the exact project associated with the supplied client showed **Testing**, **zero test users**, and incomplete Branding. This was direct browser evidence, even though the user believed their account had already been added.

With the user's explicit approval, the test-account entry was prepared and Save was submitted in Google Cloud. The interface showed a loading state. Native UI automation initially disconnected. On the next check, the saved test account was confirmed in this exact project. The user then reached an import HTTP 403, proving the next failure happened after OAuth. Gmail API and Drive API were found disabled and enabled. Gmail then imported 30 messages and Drive imported 19 documents successfully. Both source-sharing toggles remained off.

For personal testing, confirm the intended Google account appears under this exact project's Audience → Test users. Complete Branding, configure requested permissions under Data Access, and enable Gmail, Drive, Calendar and Gemini APIs as appropriate. Reconnect from Iris and use the same test account.

For public distribution, Google controls audience, scope verification, organizational policy and quota. Bundling the registration removes user configuration; it cannot promise universal or permanent access. Sensitive/restricted scopes may need Google review or applicable exceptions. No Google publishing, verification submission or billing change was performed. Gmail and Drive API activation was performed for the requested connectors. Calendar API activation was initially blocked by automatic approval review. The user then explicitly approved it; activation was completed and its Enabled status confirmed.

Primary references:
- [Google app audience](https://support.google.com/cloud/answer/15549945)
- [OAuth app states](https://developers.google.com/identity/protocols/oauth2/production-readiness/overview)
- [Restricted-scope verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/restricted-scope-verification)
- [Desktop OAuth](https://developers.google.com/identity/protocols/oauth2/native-app)

## Skills used

The attached Caveman skill was read first and used for concise chat updates. Impeccable, frontend-design, UI Skills routing/SwiftUI patterns, improve-ui's evidence review and TypeUI fundamentals informed the redesign. The explicit request to build overrides improve-ui's read-only handoff restriction. The three requested skills were installed, and the TypeUI MCP server was added and authenticated. TypeUI's project-local fundamentals were installed in the project. Its hosted section-prompt tool returned setup guidance rather than a generated native UI; no generated TypeUI screen is claimed.

Impeccable's context launcher could not initialize its engine cache under the sandbox. The required fallback was followed: existing app/source context and the skill references were read directly. The user supplied the visual direction, so the HeyClicky-like native product composition governed the design.

## Validation

- Final Xcode Debug build: **passed**, local ad-hoc signing.
- Focused Swift tests: **35 passed, zero failures**. New tests cover bundled Desktop registration loading, invalid/Web configuration rejection, access-denied recovery and structured import failures for disabled APIs, missing scopes, quota and malformed responses.
- Confirmed the built app contains GoogleOAuth.json. No user access tokens, refresh tokens, account database or profile data are included in the archive.
- Standalone onboarding and notch were visually inspected. All six onboarding steps, contained notch preview and finish transition were exercised. Workspace/sidebar navigation was observed through accessibility.
- The Connections desktop was visually confirmed with Gmail, Drive and Calendar import results. App testing replay interactions trigger a crash in the native UI automation service; source/build checks passed, but live replay confirmation remains pending.
- Named palette contrast checks: primary text/canvas 16.92:1; secondary/canvas 8.55:1; secondary/surface 7.39:1; secondary/control 6.13:1; action text/blue 11.96:1. These are token checks, not a full accessibility certification.
- Gmail and Drive live imports passed (30 messages and 19 documents). Calendar API activation passed. Its first request reported a lost network connection; retry succeeded and returned zero upcoming events. Gemini inference remains unverified. OpenAI account sign-in/model discovery/inference were verified in revision 2; no extra OpenAI request was made in this revision.

Remaining checks: App testing replay, permission-granted Apple Calendar import, Gemini inference, multi-display/full-screen behavior and measured animation performance. Gmail, Drive and Google Calendar imports are now live verified.

## Import diagnostics follow-up
Iris now distinguishes structured Google API errors such as SERVICE_DISABLED, insufficientPermissions, quota and organization-policy failures. Recovery names the failing API or required permission. Raw provider response bodies are not logged or retained. Existing knowledge remains unchanged after failure.

## Confirmed Google result
The correct project now has the approved test user and enabled Gmail, Google Drive and Google Calendar APIs. Live Iris imports succeeded: 30 Gmail messages, 19 supported Drive documents, and a successful Calendar request returning zero upcoming events. No source was enabled for sharing with model providers. The original HTTP 403 issue is resolved for these tested connectors.
