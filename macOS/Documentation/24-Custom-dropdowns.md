# Custom Iris dropdowns

Selection controls now use an Iris-drawn dropdown panel instead of Apple's native menu. Typed options supply labels, icons and optional detail text. Selected and active rows use the current Iris accent. Lists scroll within a bounded height, and eight or more options show a case-insensitive filter. Empty search results have a dedicated message. Arrow keys navigate, Return selects, and Escape or the close button dismisses. The native popover host handles positioning and outside-click dismissal; its contents are custom SwiftUI.

Applied to model, voice, speech configuration, browser, folder, document format, project task, theme, timing, display, knowledge-source and compact section selectors. Existing preference bindings remain attached to the selected typed value.

Validation: Debug build succeeded. The running model selector was opened and visually verified as a custom Iris panel, with CPU icons, the selected row and a filter input. UI inspection became intermittent during further filtering checks, so those interactions were not fully verified live. No inference was requested during validation.
