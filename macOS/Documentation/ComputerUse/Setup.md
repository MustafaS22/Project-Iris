# Using computer use

1. Connect an AI in Settings → AI providers. Choose a model that reliably follows structured instructions; choose a vision-capable model for screenshot questions.
2. Open Settings → Privacy & access and enable Iris's macOS Accessibility access for native input. Screen Recording is needed for screenshots, not semantic inspection. Keep the installed app at `/Applications/Iris.app`; no privacy database resets are needed.
3. In Settings → Computer, choose Observe, Assist or Autonomous. Assist is the default. Grant only the folders needed for the task. Optionally enable task screenshots; read the sharing disclosure first.
4. Type `@computer` followed by the objective, or ask a normal multi-step computer question. Review the task scope, then review individual input/tool requests. The activity card appears in desktop and notch chat.
5. Use Pause while navigating manually, Resume when ready, or Stop/Escape to cancel. Real manual input also pauses active automation. After a timeout or restart, inspect the result and start a new task rather than blindly repeating a write/send.

## MCP connections

Settings → MCP connections supports local stdio and remote HTTPS Streamable HTTP endpoints (localhost HTTP is also supported). Save/import configurations disabled, inspect the executable and arguments or service URL, then trust and enable. Connection tests perform initialization/discovery only. Tokens are optional Bearer credentials saved in Keychain. Edit credentials by removing and re-adding a server; removed credentials are deleted. Environment entries in compatible `mcpServers` JSON are imported into Keychain. Import never executes the command. Bare `npx`, `node`, `uvx`, `python3` and `docker` are resolved only from standard installed locations.

The Browser tools preset uses Microsoft's `@playwright/mcp@0.0.86` with `--isolated`. Node.js 20+ and an installed supported browser are required. Enabling npx can download that pinned package from npm. Iris uses its own npm cache under Application Support rather than changing your global npm cache. No browser profile cookies are silently copied. Close the MCP browser/session when finished to discard its in-memory state.

Fetch uses the reference `mcp-server-fetch==2026.11.11` through an installed `uvx`. It can read public web pages; keep its private-address protections enabled. GitHub uses `https://api.githubcopilot.com/mcp/` with your own personal access token and its granted scopes. Neither account credentials nor paid services are included with Iris. You can disable individual discovered tools. Resource/prompt content is read as untrusted data through the same approval gate.

For an optional external filesystem server, use the official `@modelcontextprotocol/server-filesystem` and pass explicit allowed directories as arguments. Its scope is controlled by that server; Iris's folder grants do not sandbox arbitrary external processes. Prefer Iris's built-in file tools for ordinary tasks.

Official references:

- [MCP Swift SDK](https://github.com/modelcontextprotocol/swift-sdk)
- [Playwright MCP](https://github.com/microsoft/playwright-mcp)
- [GitHub MCP server](https://github.com/github/github-mcp-server)
- [Reference filesystem server](https://github.com/modelcontextprotocol/servers/tree/main/src/filesystem)
- [Reference fetch server](https://github.com/modelcontextprotocol/servers/tree/main/src/fetch)
