# Persistent notch avatar

Removed the controller's explicit orderOut calls when collapsing in full-screen spaces, switching to floating mode, or opening the desktop workspace. These transitions now leave the compact avatar visible. The gear and normal expanded content still collapse normally.

The notch remains above ordinary app windows, joins full-screen spaces, and does not hide when the app deactivates or its ordinary windows are hidden. Space changes bring it forward; display changes and wake reanchor it using the current display layout. No polling timer was added.

Clicking the compact avatar while floating Iris is active returns to the notch through the existing return callback. Hover does not unexpectedly expand a second interface while floating mode is active. The hover target still updates so the avatar remains clickable.

Onboarding and quitting still close the notch intentionally. macOS lock screens and protected system overlays remain under OS control. This change does not promise visibility over those surfaces.

Validation: Debug build and a source audit of all notch visibility paths. Full-screen/display-wake behavior was not exercised through a live UI automation run.
