# Nearby cursor gaze

The live avatar reads the cursor position relative to a passive view anchor in its own window. Both eyes track toward a nearby pointer, with bounded travel and a soft radial fade. Influence eases in and out over a 120 ms damping time constant, then returns to the existing thinking or writing gaze. Eye closure, angry lids, celebration and floating remain independent.

Only animated notch and desktop avatars read position. Static marks and previews do not track. Reduce Motion disables tracking. The anchor does not intercept clicks, create global event monitors, log cursor movement or request Accessibility/Screen Recording permissions.

Validation: native build passed; all 130 regression tests passed, including five cursor tests covering radius, direction, continuity, smooth release and expression preservation.
