# WhatsApp selected-chat connection

Connections → WhatsApp → Connect opens a dedicated chat manager. Open/sign in to WhatsApp for Mac first, then choose its shared data folder: ~/Library/Group Containers/group.net.whatsapp.WhatsApp.shared. The connector stores a security-scoped bookmark and selected chat identifiers locally. macOS may require Full Disk Access; Iris cannot grant that permission itself.

Iris opens ChatStorage.sqlite read-only and WAL-aware, checks required schema columns, and lists available chat names. Message queries bind only selected chat sessions. Known removed/hidden/locked flags and non-conversation session types are filtered when their columns exist. No chats are selected automatically. The user can choose up to 20 chats, save selection, refresh manually, or disconnect. It imports up to 400 recent text/link messages per chosen chat within the existing knowledge text limit. Media and participant-name resolution are not imported.

Deselection immediately removes unselected local copies before attempting refresh. A refresh failure preserves only still-allowed imported copies. Disconnect removes the folder bookmark, selections, local WhatsApp knowledge and AI-sharing permission. The generic source Remove control removes imported copies; Disconnect in Manage chats also revokes the saved folder grant. WhatsApp itself remains unchanged.

AI-sharing permission uses the existing Use in answers control. The manager explicitly indicates whether sharing is currently enabled. No network request, new linked device, message sending, or background import is added. This is a connection to the installed Mac app, not QR-based account pairing. WhatsApp's private local schema can change; unsupported formats produce a clear error rather than silently claiming success.

Validation: synthetic SQLite tests check chosen-chat isolation, chronology, read-only bytes, hidden/locked filtering, missing chats, bounds and unsupported stores. Knowledge-store tests verify revocation after failed refresh, empty selection and disconnect without affecting other sources. The real user's WhatsApp store was not read; macOS denied access before any folder grant. Live permission/connection validation remains user-dependent.

Implementation reference: https://github.com/djuan1998/whatsapp-parser/blob/main/docs/10-spec-macos-chatstorage.md (observed macOS schema and WAL behavior).
