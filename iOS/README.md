# Iris for iPhone — 1.1 preview

A separate iPhone companion by AriZe, requiring iOS 18+. OpenAI Responses and Gemini provide streamed chat through independently saved API keys. User keys are stored only in iPhone Keychain; no credentials are included. API billing is separate from consumer app subscriptions. Account OAuth login is not implemented in 1.1 (the owner selected API-key connections for now).

## Voice and themes

Choose iPhone speech or Gemini Flash-Lite TTS in Settings → Voice. Gemini voice uses the saved Gemini key even when OpenAI handles chat. Six voices have explicit previews; preview audio is cached in memory. Replies read up to 900 characters with a maximum of two speech requests, with the first sentence eligible to start during text streaming. Quota errors trigger a cooldown, without automatic retries. API playback and quota behavior still need a real-key/device test. Six themes include visual previews and apply to new Live Activities.

## Dynamic Island and Action Button

Open App and `iris://ask` intentionally open the full app. Use the registered App Shortcuts **Ask Iris in Island** (AudioRecordingIntent + LiveActivityIntent) or **Show Iris in Island** (no microphone) instead. Configure the chosen shortcut in Settings → Action Button → Shortcut. Initial key and microphone/speech setup must be performed in the app; unlock or foreground execution may still be required by iOS. The voice intent refuses to start if a visible Live Activity cannot be created. Recording lasts at most 30 seconds and ends after a pause. It can continue in the background only for a user-invoked Island session; normal foreground voice stops when leaving the app.

The bundled Apple-signed `Ask-Iris-in-Island.shortcut` is a fallback using four actions: URL `iris://island`, Open URLs, Wait 3 seconds, and Go to Home Screen. It briefly opens a compact summon view, then returns Home; it is not a zero-foreground-execution mechanism. It is available through Settings → Shortcuts and on the website. Review the actions and add it in Shortcuts yourself. Increase the wait if needed on a slow phone. No private API or fake suspension of the app is used.

Live Activities show only status, not the transcript. Their layout and lifetime are controlled by iOS. A Dynamic Island device is needed for that presentation; other devices use the Lock Screen. No continuous microphone, arbitrary screen overlay, or access to other apps' screens is provided. Microphone input, physical Action Button behavior and background audio must still be tested on the actual iPhone; compiling and registering an intent is not end-to-end verification.

## Connections

Calendar and Reminders use EventKit read-only operations. The OS full-access permission is required for reading, but the implementation never writes events or reminders. Sources start unchecked. Only user-checked calendars/lists are queried for each submitted question (next 7 days / incomplete reminders), with bounded context. Selected contacts use the system picker rather than full address-book access. Selected UTF-8 text or readable PDFs can be added through the Files picker; scanned PDFs are not OCR'd. Individual references can be disabled or removed. Context is sent to the currently selected provider only with a question, not synced in the background. There is no Mac account, file, Studio, WhatsApp, Notes, Mail, or Instagram sync in this version.

## Install without a paid Apple Developer membership

The published IPA is an **unsigned device build for re-signing**, not a Safari-installable enterprise app. Use AltStore Classic with AltServer on a Mac or PC, and your own Apple account. Follow https://faq.altstore.io/altstore-classic/how-to-install-altstore-macos (or its Windows counterpart). Download the IPA, then choose it in AltStore → My Apps → +. Keep extensions when asked. Trust your developer profile and enable Developer Mode only as instructed by Apple's prompts and the official AltStore guide. A free account normally requires refreshing apps every 7 days and is limited to 3 active sideloaded apps, including AltStore. Extensions consume additional App IDs. Neither AriZe nor this website asks for your Apple password.

Alternatively, open Iris.xcodeproj in Xcode, add your own Apple account in Xcode Settings, choose your Personal Team on both targets, connect your iPhone and Run. Bundle identifiers may need a unique suffix on both targets (the extension ID must begin with the main app ID). Do not enable a capability that your Personal Team does not support. If the signer cannot provision the extension, the full Dynamic Island build cannot be installed with that signer; use Xcode and report the exact provisioning error rather than removing the extension silently.

## Build

No package dependencies. Xcode with the iOS 18+ SDK is required.

```
xcodebuild -project Iris.xcodeproj -scheme Iris -configuration Release -destination 'generic/platform=iOS' -derivedDataPath Build CODE_SIGNING_ALLOWED=NO build
```

Put `Build/Build/Products/Release-iphoneos/Iris.app` inside a directory named `Payload`, then ZIP that directory as `Iris-iPhone-1.1.ipa`. The app must be signed for your own device by your sideloader before installation. No signing certificate or personal provisioning profile is distributed.

## Verification

Device and simulator builds are checked separately. A simulator build cannot be installed on a real phone. A physical-phone installation and Apple-account re-signing are not validated until completed on that device. Never claim an unsigned build is already device-installable.

Public guide: https://projectiris.lovelyabbey.chatgpt.site/iphone

## Tests

`swift test --package-path Tests` runs seven offline checks for Gemini/OpenAI text streaming, exclusion of reasoning fields, stream failures, and malformed audio rejection. These do not use a provider key or incur inference charges. Device and simulator builds are separate. Simulator theme selection and App Shortcut registration are inspected with the native UI. Physical sideloading, granted Calendar/Reminders data, provider inference, Gemini voice and Action Button behavior are not claimed as verified until tested on-device.
