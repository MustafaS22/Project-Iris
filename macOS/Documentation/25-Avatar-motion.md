# Iris avatar motion

The live notch face and centered desktop head use a shared monotonic motion clock, sampled up to 60 times per second. Blinks begin every 15 seconds, closing quickly and reopening softly over a 270 ms cycle. A low-amplitude float and sub-degree roll move the face without changing layout dimensions.

Thinking uses matched eye shapes, held gazes and eased side-to-side movements. Error, warning and disconnected states use inward-slanted lids; attention uses a milder version. State changes interpolate from the currently displayed pose over 420 ms. Errors take priority over voice expressions so a problem remains visible.

Desktop down-glances run only while visible response text is streaming. A cancellable task waits a fresh random 10–30 seconds between glances. Each glance eases down, holds, then returns over 2.2 seconds. The scheduler stops with writing, view removal or Reduce Motion. It does not request model responses or voice generation.

Sidebar marks, saved-message avatars and settings previews stay static. Reduce Motion disables blinking, floating and gaze travel while retaining each expression.

Validation: Debug build succeeded; all 125 regression tests passed, including 10 motion tests for blink timing, eye coherence, continuity, bounded float, attention expression, glance intervals and reduced motion. Production Canvas rendering was exported and inspected for idle, thinking left/right, angry attention, writing glance, blink and celebration states.
