# Iris 2.1.1 — computer-use reliability report

## Causes established

- The global event monitor paused on ordinary mouse movement, leaving a task indefinitely paused before any action. A key guard also skipped global Escape handling during review.
- Unfocused field selection and a bounded AX tree could omit the active editor. Closed menus contributed hundreds of invisible controls and hid real web content from inspection.
- The initial planner received app metadata rather than an actual interface observation. Native mutations refreshed only semantic text, not screenshots. Capture's secure-field scan replaced AX IDs after callers had already assembled an observation.
- All clicks and typing required review, including routine local editing. Completion could rely on a generic successful inspection rather than objective evidence.
- Scroll input had no explicit target location. Short-lived frames could expire during planning/review, while moved windows needed stronger rejection.

## Changes

The executor prioritizes the focused editor, filters closed zero-size menus, synchronizes image and AX observations, refreshes enabled task screenshots after meaningful actions, validates frame/window/display geometry, and locates the scroll target. Pointer targets animate through a click-through Iris indicator with click and drag feedback. Supported Accessibility actions leave the user pointer alone. Raw application-targeted events are available explicitly; verified foreground system input is the reliable default where those events are ignored. The indicator identifies the route honestly.

Routine native navigation/local editing uses actual target metadata. Unknown and consequential actions, external tools and file operations retain review. Hovering no longer interrupts work; clicks/typing/scrolling invalidate stale work and replan after a quiet period. Explicit Pause and immediate Stop remain. Escape works during review. The loop refreshes observations after failures, permits bounded recovery and requires a separate read/inspection with matching completion evidence.

## Validation

336 core regression/policy tests passed before release. Signed Debug integration checks used normal Launch Services and existing Screen Recording/Accessibility permissions, without resets. Real Notes writing, Finder creation/rename, Safari local form search and result navigation, actual menus, two-app switching, delayed controls, unexpected dialog recovery, frame transforms, stale target rejection, unchanged physical pointer during AXPress, ignored targeted-click recovery, Escape during pending approval, stdio and HTTP MCP, reconnection, Playwright Chrome and a mixed native/MCP/file objective passed. Full results are in `Validation/results-2.1.1.json`.

## Limits

macOS does not supply Iris with a second universal system pointer. Native actions currently target the allowed foreground app. Raw targeted events may be ignored; shared pointer input remains necessary for some controls. Screen awareness needs the task screenshot setting and a vision-capable configured model; custom sensitive controls cannot all be detected through AX. External MCP calls and ambiguous inputs remain supervised. One Retina display was available; physical multi-monitor behavior, Blender/Pages/VS Code workflows and arbitrary live-model planning were not validated. The Achieve3000 assessment was not completed; a harmless local article exercised the Safari interaction path. The scripted planner tests used no cloud AI quota. Windows 1.0 and iPhone code are unchanged.
