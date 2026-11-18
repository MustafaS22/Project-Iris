# Polished screen annotations — 1.5.12

The model previously positioned labels and arrows separately. Leaders could run through label text, boxes covered the diagram, and every mark appeared instantly.

The new callout mark places an anchor at the subject, with a short text label. Iris lays out balanced columns, preserves target order, separates crowded labels, clamps to the display and attaches leaders outside label edges. Legacy label/arrow pairs are matched and upgraded locally. Geometry is always painted below cards. Cards use compact white typography, a theme-colored number badge, quiet charcoal fill and a fine edge. Leaders use thin theme-colored strokes, softer contrast outlines and endpoint dots. The avatar moves aside if it overlaps a callout.

A bounded TimelineView draws paths progressively, staggers marks, then eases in labels. Replacing/clearing the drawing cancels the previous sequence and resets the view identity to avoid flashing a fully rendered frame. The animation stops scheduling frames after completion. System Reduce Motion draws the completed overlay immediately. The canvas remains click-through.

Validation: Release build passes; 21 focused tests pass, including 24 crowded callouts on a 900×600 display, legacy pairing, bounds, target order and finite monotonic animation timing. The real SwiftUI Canvas was rendered at multiple animation stages and visually reviewed. Preview files in the Codex workspace are native renderer fixtures, not an anatomy-identification test. The build is ad hoc signed and not Apple-notarized; macOS may require refreshing screen access after installation.

Installed /Applications/Iris.app 1.5.12, build 162. Public download verified against SHA-256 aebc66f2969f7111f00911f03892c1b5588bcc1b1fdfd7d6ed6a1e3909a7c812. Screen Recording refresh approved by the owner; System Settings shows Iris enabled. A native renderer preview verifies appearance and progression; a fresh live-model drawing was not requested for this styling-only update.
