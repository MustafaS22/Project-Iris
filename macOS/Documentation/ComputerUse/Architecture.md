# Native computer use and MCP

## Existing architecture and integration

Iris is a native SwiftUI/AppKit macOS app. `IrisOrchestrator` owns chat, provider selection, permissions, attachments, speech and existing file/app recipes. `ScreenGuidance` already provides ScreenCaptureKit, Accessibility/OCR targets and accurate diagram projection. `AssistantActions` and `ActionPolicy` implement the existing reviewed action protocol. Background agents use `IrisAgentStore` with serialized computer access. These components remain in place; Windows 1.0 and iOS are unchanged.

The new computer-use path is `@computer` or a model-produced `computerTask` action. It uses the existing review sheet before starting. Simple app/link/file recipes retain their direct path. Background agents can hand a larger computer objective to the same session, while retaining their computer lock.

## Layers

- `ComputerUsePolicy`: app exclusions, Observe/Assist/Autonomous decisions, denied tools, endpoint validation, point bounds and loop normalization. Policies are enforced outside model output.
- `NativeComputerUse`: AppKit application management, bounded AX traversal and fresh element IDs, ScreenCaptureKit window/explicit display images, local Vision OCR, point/pixel metadata, CGEvent input and window controls. This executor does not depend on an MCP transport.
- `ComputerUseFiles`: direct filesystem operations using Iris's existing folder bookmarks and symlink-aware containment. New files only, no overwrite/delete, same-grant moves, bounded text reads, hidden/credential-related paths blocked.
- `IrisMCPManager`: the official Swift SDK, stdio child processes, Streamable HTTP, capability discovery, tools/resources/prompts, process cleanup, health checks, reconnect, limited metadata logs and Keychain credentials.
- `ComputerUseSession`: bounded provider-independent single-action planning, execution, observation and completion verification; task facts, recent actions, retries, loop detection, pause/cancel and five-minute deadline. Uses existing OpenAI/Gemini/LM Studio requests with a strict JSON tool-decision instruction. This is a text-based tool adapter, not provider-specific native function-calling. Unsupported/malformed model decisions fail closed.
- `ComputerUseViews`: the existing Iris design language, activity cards in desktop/notch chat, Computer mode controls and dedicated MCP settings.

The official SDK is pinned at `234e412874267c16309a4fc76a6e3629c9fea13f`. It negotiates MCP 2025-11-25. A server supporting only the newer discovery-only protocol needs a compatible SDK update; Iris does not pretend to support that transport variant.

## Execution and context

1. Explicit user objective and start review establish the task scope and interface-text sharing.
2. Discover enabled MCP tools; supply a bounded roster and relevant complete schemas. `discover_tools` retrieves narrower schemas without another network service.
3. Prefer direct app/MCP APIs or approved-folder operations, then browser DOM, then AX, then fresh visual coordinates. This preference is in the planner instruction; hardware/privacy policy remains deterministic.
4. Ask the configured AI for exactly one tool decision. Supplied UI, screenshots, files, tool descriptions and results are untrusted reference data.
5. Check mode, app/tool restrictions and approval. All external tools, clicks, typing, shortcuts, file reads/changes and closing windows require explicit review. Autonomous mode only skips review for local inspection and a narrow set of low-risk navigation controls.
6. Execute, inspect the resulting interface or file, and replan. Never replay an uncertain MCP mutation automatically. Preserve IDs returned by a semantic inspection until the next explicit observation; do not invalidate them with an extra hidden tree read.
7. Finish only with observation evidence; otherwise stop with a specific blocker. Limit 24 actions, 32 planning turns, two consecutive failures, repeated unchanged actions and five minutes overall.

The session sends bounded interface text and requested images only while active. Screenshots default off, are memory-only, use at most 1440 pixels across and carry an explicit global-points transform. A model can request the foreground window or an explicit display. Full displays exclude Iris and configured apps and require Accessibility for secure-field detection. Cached image hashes report changes; Iris does not stream desktop frames continuously. Task facts and recent actions reduce repeated context. No extra planning request is made for ordinary chat.

## Privacy and interruption

Observe blocks mutation. Tool descriptions and MCP read-only annotations never grant permissions. Stdio executables run with the user's account privileges; trusting a server is distinct from approving its tools. Config imports remain disabled until explicitly trusted. Bearer tokens and imported environment secrets are stored in the macOS Keychain, not configuration JSON, logs or AI prompts.

Password controls are redacted and never typed into; capture is blocked when a secure field is detected. Detection is best effort: AX-inaccessible custom controls cannot be guaranteed to identify every sensitive pixel. Use app exclusions and task-specific screenshot sharing accordingly. Explicit full-display capture can include other allowed windows; it is never the default.

Escape stops an active session. Unexpected real mouse/keyboard input pauses the session. Iris-generated events carry a marker so they do not trigger their own pause. Every action checks cancellation. Mouse-up cleanup must still run after cancellation. The task record stores objective, status and a limited action history, not screenshots, typed arguments, raw tool outputs or credentials. Tasks never restart automatically after a crash/relaunch. Clear history in Computer settings.

## Local MCP server

Run the installed executable with `--iris-computer-use-mcp`:

```json
{
  "mcpServers": {
    "iris-computer-use": {
      "command": "/Applications/Iris.app/Contents/MacOS/Project IRIS",
      "args": ["--iris-computer-use-mcp"]
    }
  }
}
```

It exposes the actual native executor over stdio, reserves stdout for MCP messages and presents an Iris approval dialog for external mutations. Its own mode, excluded apps and screenshot setting still apply. Launching raw binaries from a terminal can cause macOS to attribute Accessibility to the parent application; test native permission behavior through a normal Launch Services app launch. Do not reset TCC to work around this.

## Boundaries

This is supervised computer use, not a guarantee of arbitrary application automation. It cannot bypass TCC, app logins, protected/secure fields, inaccessible controls or model capability limits. App exclusions are configurable. Playwright's default preset uses an isolated browser, not the user's Safari profile. OAuth browser registration/consent for external MCP services is not implemented: use a service-supported personal bearer token. GitHub credentials and private repositories are never bundled. Remote services may require their own account and billing. Filesystem MCP is optional; Iris's scoped local file tools work without it. Windows and iPhone do not gain system-wide Mac controls.

## Validation on 24 November 2026

334 XCTest regressions/policy tests passed. The signed app was launched through normal macOS Launch Services with its existing permission entries, without resetting TCC. Real AppKit field selection, Unicode insertion and a resulting button action passed. Tests also recovered from a real NSAlert, switched between Finder and the fixture, captured a real window and used its point/pixel transform, rejected stale targets, created/read/moved temporary files, exercised stdio MCP discovery/reconnect and Streamable HTTP structured tool/resource results, and navigated a real Chrome DOM through official Playwright MCP. A local scripted planner completed one mixed native/MCP/file objective with real actions, explicit approval continuations, observation and verified output. Pause, stop and unexpected-input handling were checked. Test details and reproducible fixtures are in `Validation/`.

These checks used one connected Retina display and isolated applications/files. They do not establish physical multi-monitor coverage or planning quality for every live AI model, account, third-party application or dialog. Coordinate math tests supplement, rather than replace, hardware tests. No cloud AI quota was used for the integration harness. Read the model, OAuth, platform and privacy limitations above before treating a task as unattended automation.
