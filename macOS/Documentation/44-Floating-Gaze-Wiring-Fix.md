# Floating eye movement wiring

Travel and manual drag now have a dedicated published movementGaze channel, passed explicitly through the actual FloatingIrisView into IrisAvatar. It takes priority over tutorial/cursor attention. Manual mouse events publish the new direction immediately; the common-mode motion timer handles continuous travel and the drag-pause decay.

Explicit direction no longer depends on the native invisible cursor anchor being attached, visible, or hosted in a window. Only cursor-position sampling needs that anchor. The existing frame-rate-independent eye smoothing still handles direction changes and release.

Validation: Debug build passed. An isolated native NSPanel used the actual FloatingIrisView and IrisAvatar sources. Pixel-centroid assertions verified visibly different rendered eye positions for left/right and up/down directions. A separate regression assertion used AvatarPointerProbe without any native anchor and verified explicit direction still applies. No accounts or model/voice requests were involved. This is a rendered integration check; it is not a full live Control–Option–F/physical-mouse automation test.
