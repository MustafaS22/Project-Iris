# Study Spaces

The student learning workspace is now called **Study Spaces** throughout Studio, Library, empty states, creation/search controls and removal dialogs. Existing sources, conversations and outputs stay compatible with the original storage format; no migration or deletion is required. Existing custom titles remain unchanged. The old default placeholder is displayed as “Untitled study space.”

## A different workflow
The previous three-column Sources / Chat / Studio composition has been replaced by one Iris-led workspace:

- A live Iris avatar accompanies the space title and current activity.
- **Reading shelf** is a collapsible material dock above the work area. It starts expanded for an empty space. Add files or pasted text, select reading and inspect excerpts here.
- **Explore** provides the main conversation canvas, citations and Save as note.
- **Study kit** focuses on learning outcomes. Each tool has an explanation: follow a topic's thread, find a route through it, connect ideas, practice retrieval or test understanding. Streamed prose remains visible while an output is being prepared.
- **Saved work** provides a separate collection of outputs and saved answers. Newly generated outputs open directly. Output viewers, quiz interaction, flashcard practice and exports remain functional.

The space index uses a reading/activity list with actual material names, saved-piece counts and dates instead of notebook-cover tiles. Library uses the same Study Spaces label and display titles. The separate saved flashcard practice tab is now **My deck**, keeping it distinct from a space's Study kit. Developer Studio and earlier study conversations remain available.

The established Iris avatar, charcoal surfaces, selected accent, custom controls and conversational writing provide continuity with the rest of the app. Source selection, model usage, citations, local persistence and existing sharing rules are unchanged.

## Validation
The macOS Debug build succeeded and the existing 174 core tests passed. Wide and narrow Explore layouts were rendered and inspected with synthetic study data. This revision changes presentation and navigation; no live inference, paid generation or user-file access was required. The backend's existing notebook keys and model names remain internal compatibility details.
