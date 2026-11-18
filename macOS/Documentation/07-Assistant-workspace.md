# Assistant workspace revision

Iris now opens around a spacious personal-assistant conversation. Its eye avatar sits centered above the chat, with an anchored composer and three optional starting prompts. Student and developer tools live in a separate Studio section. The notch keeps its compact layout, with cleaner greeting spacing, centered supporting text, larger mode targets and an action-review shortcut.

## Visual settings
Appearance, Voice, AI, Computer and Privacy have separate settings sections. Knowledge sources use Google product logos or native app icons. Eight theme choices include a custom hue slider, with a matching avatar preview. Navigation transitions respect Reduce Motion. Onboarding uses a menu for the expanded theme choices.

## Voice
The keyboard shortcut opens Iris and starts listening when enabled. Recognized speech submits after a 1.6-second pause, or when recognition reports a final result. Voice requests can receive spoken answers. Users can choose installed macOS voices, preview them and adjust speed. The default prefers a higher-quality installed voice for the current locale. Microphone and speech-recognition permission remain controlled by macOS; recognition may use Apple servers.

## Reviewed computer actions
The model can propose opening an installed app or web URL, listing or reading files, writing a complete text file, creating a folder and revealing a file. A review sheet requires explicit execution. Full replacement text is visible before writing.

Users grant folders through the native picker. Downloads, Documents, Applications and another folder have dedicated entry points. Security-scoped bookmarks preserve grants; users can revoke them. Paths cannot escape an approved root through traversal or ancestor symlinks. Text reads are bounded to 500 KB and displayed up to 18,000 characters; writes are bounded to 100 KB. App bundles cannot be written. There is no shell execution, deletion, arbitrary cross-app clicking/typing or autonomous multi-step control loop.

Read and directory-list results stay local, outside model history. A separate button explicitly attaches a result to the next question.

## Validation and limits
The Debug build succeeded. All 39 focused tests passed, including four new tests covering action parsing, traversal, ancestor symlink escape and preference compatibility. The symlink test caught an ancestor-resolution flaw that was fixed before delivery. Bundled Gmail, Drive and Calendar logos were confirmed in the app resources.

No paid provider calls were made for this revision. Voice hardware behavior, new folder permission flows and computer actions against user files were not live-tested. Existing Google and OpenAI verification is recorded in revision three. This is a local development build, not a notarized distribution.
