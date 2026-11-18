# More app connections

Connections now offers ten additional sources, with search and four source groups. Existing Gmail, Drive, Calendar, Apple Notes, files and WhatsApp support remains available.

## Read-only API imports

Open Connections, find the app, and choose **Set up**. Imports run only when requested, not in the background.

| App | Setup | Imported content per refresh |
| --- | --- | --- |
| Google Chat | Google sign-in, space ID, Chat API enabled; Workspace administrator approval may be required | Up to 100 text messages from one accessible space |
| Google Tasks | Google sign-in and Tasks API enabled | Up to 100 active tasks from the default list |
| GitHub | Fine-grained token with repository issue/PR read access; owner/repository | Up to 30 open issues and pull requests; no source code or comments |
| Notion | Read-content integration token; share the page with the integration; page ID | Up to 100 top-level blocks; nested blocks, nested pages and media excluded |
| Slack | Authorized user/bot history token; channel ID; channel membership | One page of up to 15 messages; no thread replies |
| Todoist | Personal API token; optional project ID | Up to 50 active tasks |
| Linear | Read-enabled personal API key | Up to 30 issues assigned to that key's user |

These are bounded snapshots, not complete account mirrors. Google APIs and OAuth scopes must be enabled for the app's Google project. Organization policy, provider permissions and rate limits still apply. No credentials are bundled for third-party accounts.

Tokens are saved in macOS Keychain. Requests use fixed HTTPS provider endpoints; redirects are rejected so credentials cannot be forwarded to another host. Provider response size is capped at 5 MB. Tokens are excluded from knowledge, model context and error messages. Changing a token or selected resource turns off that source's AI sharing until enabled again.

**Manage → Disconnect** removes that API token, selected resource and imported local knowledge. Google sources share the existing Google account credential; revoke its access through Google Account if needed. **Remove** on a source row removes imported knowledge and its sharing permission, without deleting saved connection credentials.

## Social export imports

Instagram, X and Telegram are explicitly labeled **file imports**, with no account sign-in or live sync. Unzip downloaded archives first, then select only the files to import.

- **Instagram:** individual chat `messages_*.json` files with a `messages` array. Up to 400 recent text messages per file; unsent messages and media are skipped.
- **X:** `tweets.js` with the recognized `window.YTD.tweets.partN = ...` wrapper, or a JSON post array. Up to 100 posts per file. JavaScript is parsed as data and never executed. DMs are unsupported.
- **Telegram:** an individual chat JSON export from Telegram Desktop, including rich text entities. Up to 400 recent text messages per file. Full-account archives and media are unsupported.

Select up to 20 files, each no larger than 10 MB; an import exceeding 500 documents is rejected without changing existing knowledge. Chat text is capped at 30,000 characters, retaining its newest end. Original export files remain untouched. Re-importing the same path updates its stored snapshot.

Relevant imported excerpts are sent to the selected model only after **Use in answers** is enabled. Explicitly attaching an item in chat remains a separate action.

## Validation

The macOS Debug build succeeded. All 157 core tests passed, including eight new tests covering fixed provider hosts, target validation, read-only requests, all seven API response formats, error responses, selected chat imports, chronology and JavaScript archive rejection. No account tokens, live messages or paid APIs were used during validation. Live provider sign-in/imports still require the user's credentials and provider-side setup.
