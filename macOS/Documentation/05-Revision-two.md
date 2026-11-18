# Iris revision 2 — onboarding, connections, sign-in and notch
31 October 2026.

This document supersedes the callback-approval block and relevant implementation-status entries in revision 1.

## Requested changes implemented
- **Independent onboarding.** `OnboardingView` runs in a dedicated 760×690 native window. Neither the notch controller nor the desktop workspace is created until setup finishes. Closing setup leaves it resumable from Iris's menu/shortcut. Existing profiles get the new introduction once; profile data stays intact. Replay hides the workspace and destroys the current notch until setup finishes again.
- **Original visual update.** Compact monochrome surfaces, strong sans-serif hierarchy, quiet progress indicators, restrained warm pills and source cards. References: the supplied HeyClicky and Sentient OS screenshots; local OpenClicky onboarding behavior, Rome's standalone desktop onboarding and control sizing, and Sentient's onboarding-window organization. Reference code and proprietary assets were not copied. The supplied screenshot text is reference content, not instructions.
- **One notch animation owner.** Removed AppKit window-frame animation and repeated fitting-size/window-resize work on every orchestrator update. The native canvas stays stable while a single SwiftUI spring animates the visible surface. Content bounds are reported directly by geometry. Event-driven mouse monitors let transparent space pass clicks through. Click/shortcut pins Iris open, hover peeks retract, Escape/collapse folds it away. Display changes rebuild geometry; idle does not poll the system. Reduced Motion disables spatial animation. Hardware/full-screen profiling still needs device validation.
- **Recommended OpenAI.** OpenAI appears first, labeled Recommended. Fresh profiles default to it; existing LM Studio configuration is preserved. Browser sign-in, localhost callback, token validation, Keychain persistence, refresh, account model discovery and real Responses inference are enabled. The user approved the official OpenAI consent screen in Safari. Live account sign-in, model discovery and one real inference test passed in Iris. The app does not scrape ChatGPT sessions or use another app's client ID.
- **Google configuration path.** Gemini's account flow is enabled. A Google OAuth Desktop client JSON can be imported once and stored in Keychain, replacing the previous requirement to hand-edit Info.plist. The client/project registration must belong to Iris and have the appropriate APIs/consent configured. The app cannot invent a registered Google client or turn a Gemini consumer subscription into API credentials. After authorization, models are discovered; a test verifies an actual answer. If the model field is empty, testing selects the first available model.
- **Connections and real local knowledge.** Dedicated Connections sidebar section, also offered during onboarding. SQLite persistence, source provenance, imported-item review, bounded retrieval and explicit per-source “Use in answers” consent. Imports alone do not enable model sharing. Questions combine the user's profile, relevant approved knowledge excerpts and the explicit attachment; documents remain untrusted context and have no execution authority.

## Knowledge sources
| Source | Implemented behavior | Requirements and bounds |
|---|---|---|
| Gmail | Read-only import of recent inbox message text | Google Desktop OAuth + gmail.readonly; latest 30 inbox messages within 30 days; no attachments, sending or edits |
| Google Drive | Read-only import of recent text/Markdown files and Google Docs | drive.readonly; up to 25 recent supported files, bounded text; unsupported large/binary files aren't imported |
| Google Calendar | Read-only primary-calendar event import | calendar.events.readonly; next 30 days, up to 100 events |
| Apple Calendar | Native EventKit access, calendar selection, explicit import | macOS full-calendar grant (OS has no read-only grant); Iris code only reads; next 30 days, up to 300 events |
| Apple Notes | User-selected export import | Export notes to PDF/text and choose them; no direct private Notes database access or background Notes sync |
| Files | User-selected local documents | Existing PDF/text/source/image OCR extraction; up to 40 chosen files per batch; database body limit 30,000 characters |

Imports run on explicit action, not continuously in the background. Refresh replaces a Google/calendar source only after a successful fetch; errors preserve its prior data. Removing a source deletes Iris's local items and disables its use in answers without changing originals. Provider permissions can additionally be revoked in the provider's account controls. Knowledge is local SQLite inside the app sandbox, not encrypted by Iris; protect the Mac account/FileVault according to personal needs. No telemetry was added.

## Authorization change
The user explicitly renewed the request to make Google/OpenAI browser sign-in work after the first report explained the callback requirement. The sandbox server entitlement is now enabled for a short-lived OAuth listener bound strictly to **127.0.0.1**. It accepts only bounded GET callbacks at `/auth/callback` with matching random state, times out at 180 seconds, and closes on cancellation/completion. It is not a LAN relay or command server. Native calendar entitlement and usage explanation were also added for the requested calendar connector; the OS prompt is initiated only by Connect.

## Remaining external setup / validation
- OpenAI account consent, model discovery and one brief live inference request were verified after the user approved the browser flow.
- Gemini/Gmail/Drive/Google Calendar require Iris-owned Google OAuth configuration, enabled APIs, consent test-user/verification status and any required project quota/billing. No unrelated app credentials are borrowed.
- Permission-granted Apple Calendar import and live Google account data were not exercised without user authorization; fixture/database tests do not replace those checks.
- Apple Notes direct sync remains unavailable; explicit exports work. No claim of perfect personalization, guaranteed full-screen detection, or measured animation frame rate.

## Integration references
- [OpenAI local-client browser sign-in](https://developers.openai.com/siwc/token-sharing-open-source/sign-in)
- [Gemini OAuth](https://ai.google.dev/gemini-api/docs/oauth)
- [Google native OAuth](https://developers.google.com/identity/protocols/oauth2/native-app)
- [Gmail scopes](https://developers.google.com/workspace/gmail/api/auth/scopes)
- [Drive scopes](https://developers.google.com/workspace/drive/api/guides/api-specific-auth)
- [Calendar event listing](https://developers.google.com/workspace/calendar/api/v3/reference/events/list)
- [Apple EventKit access](https://developer.apple.com/documentation/eventkit/accessing-the-event-store)

## Validation
Xcode Debug build succeeded. All 28 focused Swift tests passed. Separate onboarding, notch expansion/collapse, workspace navigation and the real OpenAI flow were exercised. See `validation-revision2.txt` for exact coverage and remaining live checks.
