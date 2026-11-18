# Compact floating typing

Control–Option–T opens a single-line capsule, up to 460 points wide and 60 points tall, with a small live avatar at its left and a send button at the right. It replaces the previous 210/320-point composer. The separate full-size avatar and hover controls are hidden while typing.

Return submits nonempty text when Iris is ready. The request starts immediately; the same face scales smoothly from the small input avatar into the full floating face while the capsule and text disappear. A cancellable 360 ms handoff then places the normal avatar at the same position and removes the composer panel. Escape performs the same fold without submitting or discarding the draft. Reduce Motion uses an immediate handoff.

The native composer has a transparent 112-point canvas to contain the morph without resizing native window bounds during animation. The visible input is 60 points tall. Roaming and hover controls pause during input and the morph. Reopening typing or hiding floating mode cancels pending handoffs, preventing a delayed avatar from reappearing. Placement is clamped to the current display bounds.

Screen guidance controls have moved into a popover on the hover toolbar's eye button. Selected-app sharing remains explicit, with the same capture and permission rules. Normal floating responses continue to use the standard assistant pipeline and spoken replies.

Validation: Debug build and an offline AppKit-hosted render of the real field and avatar endpoints. The final avatar scaling uses a transform rather than redrawing the face at changing sizes. Live keyboard/focus/animation behavior was not exercised through OS UI automation.
