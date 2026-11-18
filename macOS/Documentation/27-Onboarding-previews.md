# Onboarding previews and layout

- Replaced color-only swatches with named previews of the notch and desktop chat for all eight themes.
- Added visible hover and selected states; custom hue updates its preview immediately.
- Increased preferred setup size to 900×740, with resizing, an 800×620 minimum and initial screen fitting.
- Separated appearance, listening/quiet hours, and computer access to reduce visual density.
- Kept navigation visible; reset scroll position on step changes and disabled Back during authorization/imports.
- Added explicit role selection indicators and accessibility traits.
- Hid the existing imported-document library in the compact onboarding connection step, preserving it in the full Connections view.
- Preserved saved preferences, accounts, knowledge and permission behavior.

Validation: Debug build passes. Production theme tile rendered offline in SwiftUI and visually checked at the onboarding content width. Source reviewed across all six steps. Live inspection was unavailable because the computer-use service timed out.
