# Chat history and Studio refinement

## Changes
- Chat history is accessible from the sidebar and the main chat header. Conversations save locally as messages change and survive relaunch. Search matches message text. Users can start a new chat, continue an existing chat, or delete one after confirmation. New history fields are optional so existing profiles and notes remain readable. Earlier builds did not save chat messages; previously discarded conversations cannot be recovered.
- The Iris wordmark now uses heavy rounded lettering. The top-left mark is static and optically balanced. The notch and central face retain state expressions.
- A persistent sidebar toggle is available in the workspace header, including when the sidebar is hidden.
- Back to the notch hides the desktop window and explicitly reveals the pinned notch.
- The notch composer has a compact centered layout, plain circular send/stop controls, a quieter border and an accent focus state. The oversized native button background is removed.
- Google source logos load explicitly from bundled PNG files using NSImage and original rendering, with visible system-icon fallbacks.
- Student Studio includes a saved flashcard deck, question/answer entry, answer reveal, next-card practice and card removal. Focus sessions remain available.
- Developer Studio includes an automatically saved local scratchpad, line and byte counts, JSON validation, JSON formatting and native text-file export. Code is not executed or sent to a model.

## Validation
The Debug build succeeded. All 43 focused tests passed. New tests cover older-state compatibility, conversation/deck persistence, flashcard parsing and JSON preservation/error handling. No paid model calls were made.

Live UI inspection confirmed the Chat history entries and sidebar toggle in the rebuilt workspace. The native inspection service then closed its pipe, preventing the screenshot and remaining visual checks. Back-to-notch, logo appearance and Studio interactions were compiled but not fully exercised live in this pass.
