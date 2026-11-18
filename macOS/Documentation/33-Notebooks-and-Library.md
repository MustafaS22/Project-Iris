# Student notebooks and Library

## Student Studio
Open **Studio → Learn → Notebooks**. Create a named notebook for a topic, then add readable PDFs, Word documents, text/code files or pasted notes. A notebook stores up to 12 sources locally, each up to 18,000 extracted characters. Check source boxes to choose what Iris receives. Sources can be read or removed without changing original files.

The workspace follows a Sources / Chat / Study tools organization. Wide windows show all three columns; narrow windows show accessible section tabs. Questions use only selected source excerpts, at most 8,000 characters per source and 48,000 per request. These bounds are shown in the interface. Notebook chat is separate from the personal assistant and has no computer-action executor. Generation uses the selected model account; it is not a connection to Google's NotebookLM service.

Iris is instructed to ground claims in sources, use `[S1]` citations, and admit missing information. These are model instructions, not a guarantee of factual correctness. Citation buttons open the exact excerpt supplied for that response. Only known labels receive buttons. Historical evidence snapshots remain available after changing or removing current sources. Old answer citation labels are removed from subsequent request history so they are not reused as current evidence.

Study tools create summaries, study guides, flashcards, mind maps and practice quizzes. Flashcards and mind maps use the existing structured renderer; quizzes allow option selection and show explanations. Generated outputs save automatically in their notebook. Answers can also be saved as notes. Outputs can be exported locally; exported files appear in Library. An unreadable model output shows a regeneration message rather than raw study JSON. Notebook questions and outputs stream their visible prose, show progress and support Stop. Imports and generation failures preserve existing content. No model calls happen until requested.

Saved flashcard practice remains under **Practice**. Older Student Studio conversations remain under **Earlier tasks** and Library. Developer workflows remain available under **Build**.

## Library
A new **Library** sidebar destination collects:

- Topic notebooks, opening their source-grounded workspace.
- Studio projects and earlier study tasks, reopening their original conversation and workflow.
- Notebook study outputs, opening the study result viewer.
- Saved file references from assistant conversations, Create exports and Studio exports, with existing Open and Use in question actions.
- Generated draft snapshots and edited drafts saved when leaving Create or starting a new draft.

Library backfills file references already known to Iris and the existing saved Create draft. It does not scan disks, invent projects or grant file access. Files keep their original locations and existing folder/bookmark permissions. Unavailable or moved files use the existing file-access error handling. Draft previews support Copy and Edit in Create; reopening a draft keeps the previous editor text available through Restore. Search and category tabs narrow the collection.

Notebook and Library fields are optional additions to the existing persisted state, preserving compatibility with older state files. Original knowledge sources and chats are retained. Files still need to be saved/exported before they can be opened as files.

## Validation
All 162 core tests passed, including five notebook tests for selection isolation, context limits, immutable citation snapshots, quiz validation, old-state migration and Library reference persistence. The macOS Debug build succeeded. Wide and narrow notebook layouts and Library were inspected using synthetic local data. Live model-generated study outputs and account calls were not exercised, so provider-specific response quality remains unverified. No paid generation or real study material was used during checks.
