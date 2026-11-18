# Integrated desktop, Studio skills and app actions

## Desktop refinement
The desktop uses one 56-point title row. Native traffic lights remain in the window, while the SwiftUI surface extends into the transparent titlebar. The duplicate chat header is removed. The sidebar uses smaller eye proportions, standard bold system lettering, grouped navigation and a collapse button inside its header. The assistant header and composer retain their intrinsic heights; the transcript takes the remaining space and clips within its bounds.

Settings and Studio use text tabs with a thin selection underline. At constrained widths, the tab bar falls back to a menu instead of compressing its labels. The existing notch behavior is preserved.

## Runtime skills
Eight bundled Markdown skills load into the model's instruction channel only for the selected Studio task. They cover flashcards, mind maps, summaries, doubts, app building, website building, code review and project planning. They distinguish reference content from instructions, require grounded outputs and forbid invented execution/test results.

A Studio task provides a request field, up to three locally extracted references, previews, removal and an explicit Generate button. Generate sends the request and up to 4,000 characters per reference to the selected provider and can consume allowance. References are not retained across a new conversation or relaunch. Saved conversation records retain the task identifier.

Validated flashcard responses render as expandable questions and can be saved into the existing practice deck. Mind maps render a central topic and grouped branches. Invalid structured outputs show a recovery message and the full response. Summaries, doubt explanations, plans and code reviews render Markdown. App and website skills use the reviewed file-action system to create or edit real files in approved folders. Generated work still depends on model quality and the user approving proposed file actions.

## Native app integrations
The action contract now supports:
- playSpotifyPlaylist: exact Spotify playlist URL or URI, validated before requesting playback through Spotify's scripting interface. Spotify must be installed and signed in; playback/account restrictions remain Spotify's responsibility.
- startLMStudio: starts the local server with the installed lms CLI, optionally loading a specified downloaded model. The command assumes ~/.lmstudio/bin/lms. It does not install the CLI or download models.
- runProject: approved folder plus optional project subfolder, with a fixed recipe for npm install, npm run build, a Vite-compatible development server, or a Python static server bound to 127.0.0.1:5173. npm recipes require package.json. Node/npm or Python must already be installed.

Each action remains explicitly reviewed. Terminal commands are shown verbatim before approval. Project scripts and dependency installation run with normal user privileges outside Iris's sandbox. macOS Automation permission is required for Terminal and Spotify; it is not granted by the build. The app reports that a command was requested and directs users to Terminal for completion/errors. It does not falsely claim successful hosting or compilation. Stop a server with Control-C in its Terminal tab. General arbitrary clicking/typing in every Mac application is not implemented.

The sandbox remains enabled. Apple Events are limited to com.apple.Terminal and com.spotify.client. These temporary exceptions need review before App Store distribution. Inputs use separate shell and AppleScript quoting; playlist, recipe and model identifiers are validated. Distinct recipes for one project remain separately reviewable.

## Validation
Final Debug build succeeded; all 47 focused tests passed. New coverage checks structured Studio artifacts, Spotify link restrictions, shell quoting, recipe/model input rejection and distinct action identities. All eight skill files are present in the built resources. Strict code-signature verification passed. No paid model calls or computer actions were executed during this revision's validation.

A live screenshot confirmed the integrated title row, reduced eye proportions, standard wordmark, sidebar layout and non-overlapping assistant transcript/composer. The native UI inspection service subsequently closed its pipe when navigating to Studio, limiting further live checks. Generated artifacts and Spotify/Terminal/LM Studio execution have not been verified end-to-end with actual model calls or Automation permission.

## Primary references
- LM Studio CLI and server: https://lmstudio.ai/docs/cli and https://lmstudio.ai/docs/cli/serve/server-start
- Apple sandbox Apple Event exceptions: https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html
- NSAppleScript: https://developer.apple.com/documentation/foundation/nsapplescript
