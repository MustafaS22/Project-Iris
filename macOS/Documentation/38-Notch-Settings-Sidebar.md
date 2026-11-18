# Settings attached to the notch

Replaces the compact quick-settings layout from revision 37. The gear now expands the notch into a settings surface up to 1,000 points wide. Regular Home, Chat and Capture views retain their 580-point maximum width; the live header avatar stays mounted.

A left sidebar switches between General, Appearance, Personality, Voice, AI connection, Computer and Shortcuts. The content area scrolls independently. Existing preference storage and provider/voice components are reused. Appearance includes the same theme previews as onboarding and the Custom hue slider. Shortcut rows describe the existing registered shortcuts, rather than offering unsupported rebinding.

General includes name, summon listening, focus-session peeks, quiet hours and replay onboarding. Computer includes the existing always-allow option and Screen Recording setup. Desktop settings remains an explicit footer link; changing categories does not open the desktop interface.

The canvas is display-bounded. Settings content height is capped at 610 points; the header, padding and status remain inside the notch canvas. Native window bounds do not animate; the SwiftUI surface handles width changes and respects Reduce Motion.

Validation: Debug build; offline AppKit-hosted previews at 1,000 and 680 points. Preview review found narrow sidebar labels needed more width and the General switches needed trailing alignment; both were corrected. No paid model or speech requests were made.
