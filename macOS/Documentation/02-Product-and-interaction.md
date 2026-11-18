# Product and interaction specification
Written before implementation. Full vision is larger than the first build; readiness is reported separately.

## 5. Product specification
Iris is a notch-resident personal assistant with study as its strongest workflow. One orchestrator owns focus, context, conversation, preferences and available capabilities. Local utilities remain useful without a model. Knowledge responses always come from a configured real provider. No seeded conversation or fabricated progress. Desktop workspace opens only on explicit request from the notch or menu bar.

Primary jobs: begin a concrete goal, sustain a session, capture a thought, read selected material, ask about it, and get a useful next action. Developer and everyday profiles change starter guidance without claiming tools that are absent. Onboarding records name, profile, interests, appearance, quiet preferences and source configuration; permissions are individually optional and explained in context. Skip model setup keeps local utilities available.

Design hypotheses: (A) quiet ink surface with warm ivory type and apricot eyes; (B) editorial paper workspace with serif headings; (C) dense developer console. Select A for the persistent notch and B for the secondary workspace; C would overemphasize developer identity. Original brand: ink #111110, paper #F5F2EB, secondary #8E8B83, apricot #E8B889, sage #AABAA4. Display New York/system serif; body SF Pro; timer SF Mono. Spacing 4/8/16/24/32/48; controls 36–44 pt on desktop, clear focus rings; no decorative neon. User may choose apricot/sage/ice accents. Native semantic colors support workspace light/dark.

## 6. UX flow map
Launch → notch + first-run workspace → profile/interests → appearance → permissions → source/test → learn shortcut → done.
Collapsed notch → hover/click/Control-Option-Space → expanded presence → Focus / Ask / Capture → actual action → live activity → collapse.
Focus: goal + duration → start → pause/resume/end → completion → persisted factual summary → user starts break or next session.
Ask: optional explicit file/image/screen context → review preview → submit to selected provider → processing/cancel → response or actionable error → optional speak answer.
Capture: type note → save locally → knowledge workspace → copy/delete with confirmation. Read selected file → local extraction → preview → explicit send.
Settings: source → edit server/model → test exact model → confirm only when tested → invalidated by edits. No cloud key field.

## 7. State and interaction model
Surface: dormant, collapsed, peek, expanded. Activity ranking: urgent > user action > communication > focus > deadline > thinking > media > system > passive. Stable ordering for ties, expired activities removed. Current slice registers focus, processing, capture, completion and errors. No fabricated media activity.

Inputs: hover opens after a short delay; pointer exit collapses after grace period unless composing/listening; click toggles expansion; Escape collapses; Control-Option-Space toggles via Carbon registered hotkey without keylogging; vertical swipe collapses/expands; drag selects a different display, then reanchors to its top center. Hardware notch remains fixed at center; arbitrary bezel positions are not offered. Displays are selected explicitly in settings and recalculated on display-change notifications. No idle display polling.

Full-screen policy: automatic peeks suppressed on a display whose available area indicates presentation/full-screen mode. Explicit shortcut may reveal Iris. OS-owned secure/full-screen contexts can still prevent overlays; no screen-saver-level bypass. Minimize menu-bar occlusion. No global transparent full-screen hitbox.

## 8. Avatar state specification
Original procedural paired soft apertures (not a borrowed character). Idle: steady eyes, no perpetual frame loop. Dormant/sleep: short horizontal lids. Listening: widened eyes plus explicit microphone badge. Thinking: asymmetric small apertures with a bounded state transition, progress text. Answering: open calm eyes, optional speech indicator. Encouraging/studying: attentive eyes plus actual session progress. Celebration: happy arcs. Concern/error/disconnected: tilted apertures and readable explanation. Confusion: unequal eyes. Permission waiting: neutral eyes + lock state. Camera/screen active: explicit icon and label; never rely on color alone. Distraction/stress states reserved for future opt-in inference; do not claim sensing emotions. Reduced motion uses static states.

## 9. Motion specification
One connected black silhouette, anchored at the top edge. Expansion spring ~0.38 s, damping ~0.86; content fades in ~0.16 s after the boundary begins moving; collapse ~0.24 s. Eye changes ~0.18 s; no restless idle looping. Timer updates once per second only during an active session; no idle TimelineView. Hover delayed ~0.22 s, exit grace ~0.65 s. Respect system Reduce Motion by disabling spatial animation; no audio cues by default. Accessibility labels describe the state and key actions. VoiceOver users have menu bar and desktop alternatives.
