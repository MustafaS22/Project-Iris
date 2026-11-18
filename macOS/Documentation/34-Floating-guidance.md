# Floating Iris: movement, typing and app guidance

## Controls
- **Control–Option–F:** summon floating Iris and start voice input.
- **Control–Option–T:** summon the avatar with a focused, compact typing panel. No microphone starts. Return or the send arrow submits the question.
- Hover over the avatar for voice/Stop, typing, guidance setup, roaming pause, eraser, full chat and Hide.
- Drag the avatar to move it, including between displays. The avatar window stays the same size. Controls and typing occupy separate, screen-constrained panels and disappear when unused.

The default surface remains the floating face alone. The typing panel is temporary; app-sharing setup is visible only when requested. Escape closes typing. Full chat keeps all text and file references available.

Floating questions use the normal assistant pipeline: conversation, approved knowledge, attachments, live data and supported app/file/project actions. Computer permissions and folder grants remain in force. Floating replies use the chosen voice even when general spoken replies are disabled. If the natural voice provider fails, a local Mac voice reads the reply. Overlay actions do not interrupt the spoken teaching step. Other completed actions can speak their actual outcome. Hide stops listening and audio; Stop cancels the current request/task.

## App guidance
Open the typing panel or eye control, turn on **Guide in an app**, and choose a running app. Bring that app to the front, then ask a question by voice or typing. The panel explains that this shares the chosen app's visible screenshot with the selected model on each question. Sharing resets when floating mode closes. No screen capture runs while idle, roaming, or clicking around.

macOS Screen Recording permission is required. Iris requests it when a guidance question is sent; it never grants that permission automatically. If already available, Accessibility adds UI labels and control bounds; OCR text positions provide a fallback without requiring Accessibility. Failed capture leaves existing chat and files intact and explains how to retry.

Each request captures only the chosen app on the avatar's display, not other apps or the whole desktop. The screenshot and up to 100 visible target labels are supplied to the selected model for that question, held in memory, and not saved as screenshot files. The model can request:

- `guideControl`: circle a verified target and show its label.
- `focusControl`: look toward a verified target without drawing.
- `drawOnScreen`: draw conceptual diagrams, arrows and explanations as before.

Guidance target IDs are unique to a snapshot. Invented IDs, an app switch, changed window bounds, missing windows or snapshots older than two minutes are rejected. External clicks and scrolling clear guidance and require a new question for updated positions. Keyboard-only changes within the same stationary window may not be detected immediately; ask again or clear the overlay after navigation. Guidance is snapshot-based, not continuous visual tracking or automatic clicking. The user performs the indicated step.

The avatar looks toward the relevant target and can move beside it while keeping its own frame away from the highlighted control. Nearby cursor attention takes priority. Annotations use a click-through full-display canvas with coordinates shared by the screenshot and control bounds. The overlay never clicks, types into, or changes another app.

## Movement and responsiveness
Native window-background dragging and SwiftUI local-coordinate dragging previously competed with animated roaming and hover resizing. The new controller owns movement alone. A native drag surface uses a fixed screen-pointer anchor; repeated events cannot accumulate movement. Controls do not resize the avatar window. A cancellable, time-sampled flight interpolates from the current position without AppKit animator conflicts. It pauses for pointer proximity, dragging, typing, listening and Reduce Motion. Ambient roaming mixes nearby movement with occasional longer journeys; screen edges and negative-origin displays remain bounded. Typing controls can move to a side when vertical space is insufficient.

A live check also found an unrelated startup hang: `SecItemCopyMatching` ran on the main thread during automatic model discovery. Account credential reads and refresh writes now run off the UI thread, including account-status refresh. macOS authorization rules remain unchanged; no Keychain permission is bypassed. Accessibility inspection and OCR also run off the UI thread.

## Validation
The Debug build succeeded and all 170 core tests passed, including eight floating tests for stable drag deltas, interpolation without overshoot, multi-display coordinate conversion, stale-target rejection, normalized highlights, non-overlapping companion placement and overlay permission policy. Compact typing/guidance layouts were rendered and inspected with synthetic data. The live app launched, but the UI automation shortcut check was blocked by the main-thread Keychain wait; its stack sample identified the responsiveness fix above. Live dragging, provider speech and real app-guidance capture were not fully verified after that fix. Restart Iris to load the new executable. No real screen content or paid model/speech requests were used during validation.

Implementation references: [Apple ScreenCaptureKit content filters](https://developer.apple.com/documentation/screencapturekit/sccontentfilter), [Apple Accessibility attribute reads](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue).
