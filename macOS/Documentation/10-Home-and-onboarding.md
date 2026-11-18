# Notch Home and onboarding refinement

The notch greeting now reads local time from a minute-based TimelineView, independently of focus timers. It uses morning (05–11), afternoon (12–16), evening (17–21) and night (22–04), with whitespace-trimmed names. Boundary tests cover all four periods.

Home now provides a new-question action, microphone entry, continuation of the most recently updated conversation, Focus, Quick note, Studio, a recent-note preview when available, and AI connection status with a setup/settings link. These are local navigation actions; Home does not make background model requests.

The desktop sidebar moves its brand into a dedicated row below native traffic controls. Collapse remains in the top sidebar row. Gentle accent gradients are applied to the desktop, sidebar, notch, onboarding, grouped panels and mind-map branches. They remain static and do not add motion or reduce text contrast intentionally.

The remaining AI provider segmented selector now uses the shared underline tabs with a menu fallback. The unused legacy theme selector uses a menu. No segmented picker styles remain in the app source.

Onboarding now includes an explicitly labeled microphone-free listening preview, role choices as simple rows, visual theme swatches and a custom hue slider, a shortcut-listening preference, step progress, navigable setup steps, clear deferred AI/knowledge setup actions, a readiness checklist and a choice to open desktop chat after completion. Existing accounts and data remain intact during replay. Changing previews does not request microphone access or call a model.

Validation: Debug build succeeded; all 48 tests passed. Strict code-signature verification passed. A live screenshot confirmed the night greeting, current date, recent-chat continuation and Home actions without overlap. Onboarding and the revised desktop brand spacing were compiled but not fully exercised live in this pass. No paid provider calls were made.
