# Chat files, private action transport and Iris identity

## Files in conversations
Messages can now persist local file references. File cards provide Open and Use in question in desktop chat, notch chat and Studio task results. Explicitly uploaded chat files also retain a card after sending. Opening launches the default document application; it does not send file contents to a model. Use in question reads supported document text into the existing attachment preview; Send remains explicit. Attachments clear after sending instead of silently being reused in later questions.

The action contract adds attachFile for an existing file and findFiles for a bounded filename search within an approved folder. Searches inspect at most 2,000 entries and return at most 30 cards. Listing, reading and saving files also return cards for actual files. Cards are created from validated filesystem results, not invented Markdown file URLs.

Folder-backed references resolve through the current grant every time they open. Revoked, stale, missing or escaped paths fail with an error. Picker-selected files use read-only security-scoped bookmarks. Cards do not send bookmarks or file contents into conversation history sent to the provider. Installers, app bundles, command files and shortcut files require manual opening rather than executing through a document card.

## Internal command handling
Execution still recognizes only valid tagged iris-actions blocks. Presentation filtering separately removes reserved action blocks, including malformed/unclosed blocks, untagged fenced action JSON and bare recognized action objects. Untagged examples never become executable actions. Ordinary source code and unrelated JSON remain visible.

New messages store cleaned prose. The same filter covers old assistant messages, history previews, outgoing model history, Studio prose and spoken replies. Dedicated action reviews retain the exact proposed file changes or Terminal commands needed for informed approval, with readable action names.

## Iris.md
The bundled Iris.md is loaded into every provider's instruction channel alongside the current task skill and action contract. It defines Iris's assistant-first identity, tone, formatting, mathematical notation, file privacy, action honesty, user control and Studio behavior. It instructs Iris not to expose backend schemas or fabricate completed work. It is an instruction document, not a model fine-tune. A reviewable copy is included in the delivery outputs.

## Validation
The final Debug build succeeded. All 52 focused tests passed before the final label/read-aloud refinement, which compiled successfully. New tests cover the reported leaked-command example, malformed reserved blocks, valid tagged actions, bare JSON filtering, preservation of ordinary source code and unrelated JSON, persisted file references and older-message decoding. Existing traversal/symlink tests remain passing. Iris.md is present in the built resources. Strict code-signature verification passed. No private files were opened and no model allowance was used during validation. Native file-opening and new search/card flows still require a live walkthrough with user-granted folders.
