# Floating Iris

## Use
- Choose Floating Iris in the menu bar for a compact, quiet desktop companion.
- Press Control–Option–F to show it and start listening. Pause after your question to send through the existing voice flow.
- Drag the avatar to move it. Hover reveals the voice, chat, pause/resume roaming, clear and hide controls. Replies and errors remain in desktop chat; floating mode never expands into a chat box.
- Roam can be switched off. Movement pauses during conversations, near the pointer, during dragging and with Reduce Motion.
- Ask for a diagram or on-screen explanation. Iris can request arrows, rectangles, circles and short labels using a bounded declarative drawing action.
- The eraser clears drawings. Close, Escape while focused, or Hide floating Iris in the menu bar hides it and stops listening/speech.
- Settings → Computer also provides Summon & speak.

## Behavior and limits
The drawing window ignores mouse events, so underlying apps remain clickable. Drawings use normalized coordinates on the display chosen at summon time. They do not change files, read the desktop, or control other apps. Actual app locations require an explicitly supplied screenshot; no screen capture happens automatically. Other computer actions retain their saved review policy. Drawing updates only Iris's own overlay and runs without a separate file/action approval. Paid image generation still requires review.

Spoken answers use the existing voice provider, microphone permission, speech recognition and silence detection. Full reply text is saved in chat. A configured AI provider is required for answers, and a working configured speech provider is required for natural audio. No model or speech calls were made during validation.

## Validation
Debug build and 139 core tests passed, covering drawing decoding and bounds, invalid data, negative-origin displays, automatic drawing actions, and existing review/billing behavior. The actual drawing renderer was rendered offline and visually inspected. Live launch through the computer-use service timed out, so global-key delivery and microphone/audio playback were not verified end to end in this session.
