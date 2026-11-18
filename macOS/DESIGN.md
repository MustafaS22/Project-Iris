# Iris interface

## Direction
Operate mode. The user selected a HeyClicky-like native desktop interface: true black notch, charcoal panels, compact mode controls, generous conversation space, polished pill actions. Preserve Iris's original eyes and selectable accent. System SF typography is deliberate native product UI.

## Tokens
Black #000000 notch; canvas #141414; raised #222222; control #303030; foreground #F5F5F7; secondary #B0B0B8; primary pill #B4D6FF with dark #101827 text. Accent preferences remain for avatar, focus and selection. Spacing 4, 8, 12, 16, 24, 32, 48. Radius 12 for groups, 24 for notch lower corners, capsules for small actions.

## Composition
Notch: compact mode control left, hardware clearance center, workspace/settings right. Home is a short greeting with two useful actions. Chat is a transcript over a voice button and text composer. Focus and capture remain reachable modes.
Desktop: charcoal sidebar, spacious conversation canvas, centered eye avatar and anchored composer. A collapsible sidebar and chat header expose saved conversations. The static eye mark and heavy rounded Iris wordmark identify the workspace. Studio contains saved flashcards and a local code/JSON scratchpad. Settings separates Appearance, Voice, AI, Computer and Privacy, with source logos, theme previews and a custom hue slider. App testing remains accessible from the sidebar footer.
Onboarding: 900×740 preferred, resizable standalone window (800×620 minimum), quiet left step rail, task content right, fixed navigation footer. Source and provider setup remain optional. Replay can start at a selected step.

## Motion
One 0.32-second spring animates the notch silhouette inside stable native bounds. Use opacity for content changes. Respect Reduced Motion. No idle decorative animation. Controls retain native keyboard focus and disabled state.

## Integrated desktop revision
Use one 56-point title row including native traffic lights. Reserve native button space in the sidebar header; place sidebar collapse inside that header. Use standard bold system type for Iris and a small static 24-point mark. Remove duplicate chat navigation rows. Use underline text tabs with a compact menu fallback. Studio task screens load bundled skills and render structured study outputs.

## Home and onboarding refinement
Separate the sidebar brand from native traffic controls with its own row below the compact title row. Subtle static accent gradients add depth across surfaces. Notch Home prioritizes new questions, voice, recent conversation continuation, quick notes and Studio. Onboarding uses a microphone-free preview, simple role rows, visual theme previews, optional connection steps and a readiness checklist.

## Knowledge library
Operate mode. Library, Notes and Attachments are separate underline tabs. Search covers all imported items; a source menu filters imports and links to connection management. Source logos and consistent document rows replace repeated context buttons. A reading pane appears when width permits; narrow windows use a focused preview sheet. New note and Add files stay at the top. Note capture opens only on request. AI-sharing status appears with imported item previews; explicit chat attachment remains a separate action.

## Form controls
Inputs and dropdown triggers use the same 44-point minimum surface, 12-point corners, 14-point text, inset spacing, subtle charcoal gradients and a quiet one-point edge. Focus uses the selected Iris accent; hover lifts contrast. Text editing and secure entry retain native semantics; dropdowns expose accessible custom choice buttons. Persistent labels identify profile fields and dropdowns. Human-readable names replace saved identifiers in folder, browser, voice and display selectors. Chat composers retain their dedicated surfaces.

## Custom dropdown lists
Every selection field opens IrisDropdownPanel in an anchored popover. The opened list is drawn entirely in SwiftUI, with charcoal surfaces, accent highlights, checkmarks, optional icons and detail text. Eight or more choices reveal a filter field. Lists are bounded and scrollable; arrows move the active row, Return commits it, Escape and the close button dismiss it. Outside clicks dismiss through the popover host. Neither Picker nor Menu renders selection choices. Knowledge source filters and narrow tab fallbacks use the same component.

## Avatar motion
Only the live notch face and the centered desktop assistant animate. Sidebar branding, message avatars and theme previews remain static. A monotonic frame-sampled motion model supplies gentle float and roll, a 15-second blink cycle, coherent thinking gaze changes and smoothly blended expressions. Error and warning eyes have inward-slanted lids. While desktop reply text streams, a cancellable schedule triggers a downward reading glance every random 10–30 seconds; each glance eases in, holds and returns over 2.2 seconds. Reduce Motion disables continuous motion while preserving clear state expressions. Layout bounds never animate.

## Nearby cursor gaze
The live notch and desktop faces ease toward a nearby pointer, using a soft radial influence rather than a hover threshold. The gaze fades to the current autonomous pose outside roughly 120 points for the notch and 192 points for the desktop face. Frame-rate-independent damping prevents snaps. Cursor proximity temporarily takes priority over thinking and writing gaze, while preserving blinking, expressions and float. Static marks and Reduce Motion remain unchanged.

## Onboarding theme previews and layout
Theme choices use an adaptive grid of named static notch and desktop compositions, with accent-colored selection edges and checkmarks. Custom hue updates its preview immediately. Listening and quiet-hour controls sit in an optional disclosure, separate from computer permissions. Content scrolls independently of the persistent footer and returns to the top on step changes. Back and step navigation consistently lock during active sign-in/imports. The connection step omits the imported-document library during setup; connection rows retain readable descriptions and full action labels. The setup window fits the available screen and can be resized.

## Guided onboarding
A persistent animated assistant lives below the sidebar brand, separate from the static logo and theme thumbnails. Short state-based guidance points to the next optional task. Real control bounds determine eye direction; offscreen tasks clamp to the scroll viewport edge and Show me reveals them. A successful or explicitly deferred step releases gaze to unrestricted cursor following. The same mounted avatar preserves blink timing, float and eased gaze across steps. Connection progress and errors take priority. Optional setup never forces microphone permission, an account connection, or a knowledge import. The step rail scrolls independently at short window heights. Reduce Motion keeps the assistant static and disables animated scrolling.

## Floating desktop mode
A separate nonactivating panel presents the live Iris face over the desktop. Compact mode keeps the face and a small control capsule; the reply surface expands for listening, streaming text and typed follow-ups. Drag the face to place it. Optional slow roaming stays inside the chosen display and pauses near the pointer, during conversation and under Reduce Motion. Control–Option–F summons the floating voice flow; Control–Option–Space keeps its notch behavior. A separate transparent mouse-ignoring panel renders bounded arrows, shapes and labels from the assistant's hidden action protocol. Clear and hide controls remove annotations. Opening workspace or notch hides the floating panel and drawings. Screen contents are not captured automatically.

## Minimal floating avatar
Floating mode contains only the animated face on a transparent 168×100 panel. Hover reveals a small control capsule below it, expanding the panel to 168×144 while preserving the face position. Controls provide voice, chat, pause/resume roaming, clear drawings and hide. A short exit delay keeps controls reachable. Listening, replies and errors never expand a floating chat surface; full text and details remain in desktop chat. Roaming pauses during conversation or interaction.

## WhatsApp connection
WhatsApp is a local read-only source in Connections with the installed app icon. A dedicated manager explains the folder grant, lists only chat names before selection, and provides search, explicit checkboxes, manual refresh and disconnect. No chat is selected by default. Saving allows up to 20 chats; deselection removes imported copies even if refresh fails. Text-only imports stay local unless source AI sharing is enabled. No account pairing, background sync, message sending or automatic screen reading is implied.

## Studio and Create workspaces
Studio uses equal Learn and Build modes, a compact workflow rail, and a focused task workspace. Explicit ideal widths keep the rail and workspace side by side when space allows; narrow surfaces stack. Practice, Scratchpad and Run projects are first-class secondary tabs rather than buried disclosures. Switching modes preserves active work. Recent Studio conversations resume with their skill and history. Task briefs persist per workflow, references can be inspected, and results can be copied or exported. Flashcard results reveal one answer at a time; deck saves persist their completion marker.

Create is an editor, not a prompt-to-chat detour. A brief pane contains style, length and optional references. The document pane provides editing, rendered preview, word count, local starter documents, persistent draft and explicit local export. Draft generation uses a dedicated cancellable model path with no action executor. A separate Image workshop contains its brief, visual style, destination, paid review, actual result preview and provider setup. Recent real files are accessible from a file shelf. Use the established charcoal, restrained accent gradients, SF typography and custom Iris controls; no fabricated outputs or activity counts.

## Expanded connections
Operate mode. Preserve the existing source rows, Iris controls and source logos. Search narrows app names and descriptions before four grouped lists: Google, On this Mac, Apps · API connections, and Social · file imports. Setup isolates provider credentials in a focused sheet with persistent field labels, clear bounded import scope, status and disconnect. Social sources say Import files and never imply live account connections. API sources say Set up or Manage. Installed application icons are used where available, with SF Symbol fallbacks.

## Study Spaces and creation library
Student Studio uses Study Spaces. A live Iris avatar and editable topic title introduce a single conversation-centered workspace. A collapsible Reading shelf sits above Explore, Study kit and Saved work. The previous three-column composition is retired. Space listings show real reading titles and saved activity rather than notebook-cover cards. Study kit explains the learning purpose of each tool; Saved work is a dedicated output collection with direct result viewers. The separate deck-practice tab is My deck. Preserve source grounding, evidence snapshots, existing saved data and earlier Studio tasks.

Library remains a separate sidebar destination with Study Spaces, projects, study outputs, files and draft snapshots. Search and category tabs expose the collection. Open original workspaces and files using existing grants. Preserve the established Iris charcoal, selected accent, SF typography and custom controls.

## Floating companion refinement
Keep only the face visible at rest. Fixed avatar bounds and a native screen-coordinate drag surface replace resizing and competing movement mechanisms. A separate hover dock exposes controls; Control–Option–T opens an anchored compact typing panel, with optional app-sharing setup and clear microphone-free entry. Companion panels choose a free side near display edges. Natural speech remains the primary floating output, with local speech fallback on provider failure. App guidance circles verified controls from a selected-app snapshot, clears stale annotations and directs the avatar's gaze toward the current target. Full assistant capabilities remain in the shared request pipeline. Motion is interrupted by user interaction and disabled by Reduce Motion.

## Selectable Iris character
Personality is a first-class Settings section, an optional onboarding entry, and a compact quick-change control beneath the main chat avatar. Six character choices use a quiet list with selected accent and a checkmark. A neighboring conversation preview compares the same three situations across styles, with a live Iris face and explicit local-example labeling. Narrow layouts stack choices and preview inside the existing scroll surface. Voice preview is opt-in and identifies normal provider usage; written previews require no inference. Character changes phrasing, humour, encouragement and optional Gemini delivery while preserving Iris identity, source grounding, format and action rules. Use the existing dark surfaces, SF typography, accent and custom Iris picker.
