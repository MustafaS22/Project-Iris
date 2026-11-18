# Live onboarding guide

- One persistent animated Iris face guides all six setup steps, separate from the static brand and theme previews.
- Guidance uses real completion state and explicit acceptance of defaults or deferred optional steps.
- The eyes look toward actual control bounds, with viewport clamping for content below the fold. Show me scrolls to that control.
- Once a step is ready, Iris smoothly follows the cursor at any distance, preserving its float and 15-second blink cycle.
- Sign-in/import progress and errors override normal guidance. No model or speech calls are used for guidance.
- The compact step rail scrolls at short window heights. Reduce Motion disables continuous animation and animated scrolling.
- Theme previews, source permissions and saved user data remain intact.

Validation: Debug build passed; 135 core tests passed, including five guidance and directed-gaze tests. Guide layout checked through an offline SwiftUI render. Live interaction verification was unavailable because the computer-use service timed out.
