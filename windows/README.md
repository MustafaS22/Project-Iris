# Iris for Windows 1.0 — test edition

This is an isolated Windows 11 x64 Electron port by AriZe, built on macOS. **It has not been run on a Windows PC and is not an exact, verified copy of the Mac app.** The installer is unsigned. macOS remains the primary platform. Windows stays at 1.0; future generic Iris changes apply only to macOS.

## Implemented
Desktop chat, top-edge compact/expanded panel, floating avatar with click controls and dragging, configurable Ctrl+Alt shortcuts, API-key Gemini/OpenAI and local OpenAI-compatible chat with streamed text, local memory/history, themes/personality preferences, selected file/image attachments including paste/drop, folder-scoped file generation/opening, PDF output, browser links/search, paid OpenAI image generation is not implemented, bounded background task views, Windows speech synthesis/recognition bridge, Gemini and VoiceBox speech adapters, user-enabled screen capture and normalized overlay annotations, drafting through Windows UI Automation with field-identity checks and explicit copy/insert choice.

## Important gaps from macOS
No Windows execution/testing has occurred. Apple app integrations, Mac subscription-account login, live Google/social connectors, double-tap gesture, sophisticated diagram library and guided app automation, full Studio parity, synchronized streaming narration, custom app-icon selection, screen solution positioning, and completed app-testing UI are not implemented. Knowledge currently imports selected UTF-8 files; no automatic live account sync is claimed. UI Automation and speech availability differ by installed Windows languages and target app.

## Build
`npm ci` then `npm test` and `npm run dist`. The NSIS installer is per-user and offers an installation folder and uninstall support. The executable resources use the Iris icon via a pure JavaScript PE resource editor. No code-signing key or API credential is bundled.

## Shortcuts
Ctrl+Alt+Space: panel/voice; Ctrl+Alt+F: floating/voice; Ctrl+Alt+T: floating typing; Ctrl+Alt+D: selected-field drafting. Change these in Settings. No tray/menu-bar icon is created. Quit Iris from Settings → About → Quit Iris. If every surface is hidden, the global shortcut reopens Iris.

## Privacy
API keys are stored using Electron safeStorage (Windows DPAPI); model requests run in the main process. The renderer is sandboxed, context-isolated, has no Node integration, and sanitized Markdown uses a restrictive CSP. Only explicitly granted folder paths are writable. The model cannot issue arbitrary shell commands. Screen capture is opt-in and may be sent to the chosen provider. Windows helper scripts are fixed application code, not generated commands. Speech and screen capture need real-device verification.
