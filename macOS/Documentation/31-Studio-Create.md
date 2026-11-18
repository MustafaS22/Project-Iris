# Studio and Create overhaul

## Studio
- Equal Learn and Build modes with a focused workflow rail and responsive workspace.
- All eight existing skills remain available. Task briefs persist per skill; optional reference text is inspectable before generation.
- Depth/approach controls, flashcard count and optional approved project destination shape real requests.
- Recent Studio conversations resume their saved history and skill. Changing Learn/Build mode no longer resets the conversation.
- Practice, Scratchpad and Run projects are separate visible tabs. Manual flashcard entry is collapsed; practice adds self-assessment and reset.
- Generated flashcards use a reveal/previous/next study interface. Saving to a deck is remembered per response to prevent accidental duplicate saves after reopening.
- Results can be copied or exported as Markdown or structured study JSON. Computer actions retain the existing permission policy.

## Create
- Dedicated brief and document editor, with editable streamed drafts, rendered preview, word count, local starter templates and persisted content.
- Draft generation calls the configured model directly without an action executor. It cannot execute generated computer commands or save a file automatically.
- Optional references, writing style, length and complete-draft revision are supported. Drafting is cancellable and partial work is preserved locally on stop/navigation.
- New and Restore retain one previous version locally, protecting edits when starting over or requesting an AI revision.
- Native Save As exports PDF/RTF/HTML/Markdown/text/CSV/JSON locally after the user edits/reviews content. JSON export validates content.
- Exported files get saved chat-style file cards in a persistent recent-file shelf.
- Image creation has a separate visual brief, style, destination, paid-generation review and actual PNG preview. No image is generated until explicitly run through the existing review.

Validation: 149 core tests passed, including draft fence extraction, internal-action filtering, safe filenames and existing document conversion regressions. Debug build passed. Production Studio landing was rendered offline with empty synthetic data in both modes; the wide-layout defect found during inspection was corrected. AI generation and billed image requests were not invoked during validation. Live app interaction remains unverified because the app inspection/launch tool has repeatedly timed out in this session.
