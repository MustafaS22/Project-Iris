# Iris — audit and research
Research date: 31 October 2026. This document precedes implementation.

## 1. Current-project audit
The existing Xcode 27.2 project uses the new `project.xcproj` format, a folder-synchronized SwiftUI macOS target, generated Info.plist, sandbox enabled, and a macOS 27 deployment target. The two application files are untouched template views. No model, persistence, tests, entitlements, permissions, overlay shell, or provider integrations exist. There are pre-existing staged Source Material additions and project edits; preserve them. The reference projects are indexed as nested projects, causing unrelated package resolution. Remove only their navigator entries, retaining all files on disk, and document this decision. Build Iris with Apple frameworks and no third-party package dependencies. Set deployment to macOS 15 for a useful compatibility floor.

## 2. Feature-status matrix before implementation
| Capability | Existing | Planned vertical slice | Remaining product work |
|---|---|---|---|
| Notch shell | absent | Native panel, geometry, fallback, hover/click/shortcut/gesture, monitor changes | Real multi-display/full-screen hardware validation |
| Avatar | absent | Original procedural eyes with state semantics | Motion usability study |
| Study | absent | Persistent goal/timer/pause/resume/history/break | Scheduled sessions and curriculum |
| Proactivity | absent | Opt-in completion/break attention, cooldown/quiet policy | Distraction/stuck inference |
| Assistant | absent | Real LM Studio HTTP requests; deterministic local tools | Cloud sign-in validation and robust agent planning |
| Voice | absent | Explicit Apple speech + speech synthesis | Streaming interruption and device QA |
| Vision | absent | User-selected image OCR and explicit screen capture | Camera streaming and vision model routing |
| Notes/files | absent | Local notes, selected text/PDF/image reading | Semantic retrieval and folder bookmarks |
| Devices | absent | Security design, no pretend pairing | Companion and authenticated transport |
| System | absent | Event-driven battery/network/foreground metadata | Calendar, reminders, media, Bluetooth |
| Onboarding/workspace | absent | Native survey, themes, permissions, provider test, guide | Larger specialist workflows |

## 3. Source Material analysis
**Rome OS** (`Source Material/rome-main`, MIT). Inspected `packages/desktop/src/main/floating-pill-state.ts`, `packages/host-helper/README.md`, `packages/mobile/src/origin-allowlist.ts`, `packages/core/src/profile-memory.ts` and package structure. Electron desktop, TypeScript core, React Native mobile, Go Linux host helper. Strong separation of model harness, persistent memory, desktop surface and execution boundary. Its floating-pill code explicitly documents macOS 27 Electron nonactivation trouble: use AppKit. Preserve the concept of explicit capability/policy checks and validated origins, but do not transplant root shell execution, Docker host authority, browser credentials, or its blocking memory locks. Tests and architecture documentation are strong evidence of engineering investment; no runtime performance was measured. Code is reusable under MIT with notices, but Iris uses original implementations.

**Taskhomie**: not found under Source Material, including a case-insensitive filename search. No repository supplied. Do not invent an analysis or claim to reuse it.

**Ghost OS** (`ghost-os-main`, MIT, Swift/macOS): inspected package structure and README; native accessibility-first computer interaction is preferable to constant screenshots. AX/event-tap permissions are powerful; scope and confirm every write. Its optional vision sidecar should remain independently sandboxed. Study only in this slice.

**Clicky** (`clicky-main`, MIT, Swift + Cloudflare worker): inspected README/license and native project layout. Useful voice/screen teaching pipeline, but its hosted speech/LLM dependencies require credentials and explicit disclosure. Public README says further development moved to private HeyClicky; do not assume continued public maintenance. Do not copy character or voice.

**Sentient OS** (`sentient-os-main`, GPL license file; Swift, macOS): local inference/context, native permissions and deferred approval are useful architectural ideas. Copyleft and vendored models require separate review; no code/assets incorporated. Large codebase and active distribution do not establish its security or performance.

**Companion** (`companion-main`, FSL-1.1-ALv2; Go/Linux, other desktop work pending): source-available, with competing-use restriction. Study the voice-first guidance and explicit local privacy boundary; do not incorporate code in a competing Iris product.

Other source folders (Aiden, Clacky, Bytebot, agent-desktop, computer-agent, OpenClicky) remain reference-only, outside Iris's build and dependency graph. No claim of full security audit.

## 4. Research method and limits
Public GitHub metadata, recursive paths, README, license, and selected implementation files were fetched. Repository-specific evidence below records exactly what was inspected. Push timestamps and tests are maintenance signals, not proof of quality. No reference executable was installed or benchmarked. Do not repeat README CPU claims as measurements. GPL projects are study-only; no-license projects are not licensed for copying; MIT reuse would require notices. All application source in this implementation is original.

## Public reference inventory

### [nicoo-o/SpaceNotch](https://github.com/nicoo-o/SpaceNotch)
License: MIT. Main language: C#. Last push: 2026-10-19T16:59:37Z; archived: False. Files indexed: 676.

Windows C#/native shell. Study activity arbitration and demand-driven frame clocks; Win32 overlays do not map directly to AppKit. Notification and plugin execution are sensitive boundaries.

Inspected: `samples/SpaceNotch.SamplePlugin.Weather/IWeatherSource.cs`, `samples/SpaceNotch.SamplePlugin.Weather/OpenMeteoWeatherSource.cs`, `samples/SpaceNotch.SamplePlugin.Weather/WeatherCodeMap.cs`, `samples/SpaceNotch.SamplePlugin.Weather/WeatherFeature.cs`, `samples/SpaceNotch.SamplePlugin.Weather/WeatherPlugin.cs`, `samples/SpaceNotch.SamplePlugin.Weather/WeatherSnapshot.cs`, `src/SpaceNotch.App/Animations/ContentTransition.cs`, `src/SpaceNotch.App/Animations/FrameClock.cs`, `LICENSE`, `README.fr.md`, `README.md`, `tests/SpaceNotch.Core.Tests/PixelAvatarTests.cs`, `tests/SpaceNotch.Core.Tests/FrameRunStatsTests.cs`, `tests/SpaceNotch.Core.Tests/ActivityManagerTests.cs`, `src/SpaceNotch.Core/Scenes/NotchGeometry.cs`, `src/SpaceNotch.Core/Motion/PixelAvatar.cs`.

Compatibility: Interaction/capability concepts only; platform code not imported. Reuse: MIT permits reuse with required notices, subject to per-file/assets review.

### [fiveneurals-max/Agentic-Island](https://github.com/fiveneurals-max/Agentic-Island)
License: MIT. Main language: TypeScript. Last push: 2026-10-03T13:41:45Z; archived: False. Files indexed: 88.

Windows Electron/React. Study state-driven expressive avatar; avoid perpetual renderer animations and renderer-side privileged bridges. OCR must be consented and excluded for sensitive contexts.

Inspected: `src/renderer/avatar/Avatar.tsx`, `src/renderer/avatar/index.ts`, `src/renderer/main.tsx`, `LICENSE`, `README.md`.

Compatibility: Interaction/capability concepts only; platform code not imported. Reuse: MIT permits reuse with required notices, subject to per-file/assets review.

### [Snzy09/NexIsland](https://github.com/Snzy09/NexIsland)
Unavailable at research time: FETCH ERROR HTTP Error 404: Not Found. License, structure, platform and reuse permission unverified. No code used.

### [techuila/top-notch](https://github.com/techuila/top-notch)
License: MIT. Main language: Swift. Last push: 2026-08-27T05:33:26Z; archived: False. Files indexed: 105.

Swift/macOS 26+. Modular NotchCore/NotchShell, notes and pomodoro. Hardware-only assumptions need an artificial-notch fallback. System-wide media integration has extra native dependencies; do not use private APIs.

Inspected: `Sources/NotchCore/Components.swift`, `Sources/NotchCore/Metrics.swift`, `Sources/NotchCore/Motion.swift`, `Sources/NotchCore/NotchImage.swift`, `Sources/NotchCore/NotchPane.swift`, `Sources/NotchCore/NotchSilhouette.swift`, `Sources/NotchCore/Style.swift`, `Sources/NotchShell/ExpandedView.swift`, `LICENSE`, `README.md`.

Compatibility: Native architecture concepts are applicable; source not imported. Reuse: MIT permits reuse with required notices, subject to per-file/assets review.

### [jinkun1998/another.notch](https://github.com/jinkun1998/another.notch)
License: GPL-3.0. Main language: Swift. Last push: 2026-10-30T02:08:17Z; archived: False. Files indexed: 278.

Swift/AppKit/SwiftUI. Borderless notch window and coordinator; XPC helper for privileged integration increases attack surface. GPL study only. Device/status observers are preferable to broad polling.

Inspected: `AnotherNotchXPCHelper/AnotherNotchXPCHelper.swift`, `AnotherNotchXPCHelper/AnotherNotchXPCHelperProtocol.swift`, `AnotherNotchXPCHelper/ScreenBrightnessDisplaySelector.swift`, `AnotherNotchXPCHelper/main.swift`, `anotherNotch/AnotherNotchViewCoordinator.swift`, `anotherNotch/Clipboard/ClipboardHistoryStore.swift`, `anotherNotch/Clipboard/ClipboardViews.swift`, `anotherNotch/ContentView.swift`, `LICENSE`, `README.md`, `anotherNotch/managers/BatteryActivityManager.swift`, `anotherNotch/components/Settings/SettingsWindowController.swift`, `anotherNotch/components/Notch/AnotherNotchWindow.swift`.

Compatibility: Native architecture concepts are applicable; source not imported. Reuse: No code copied; license review required before incorporation.

### [TheVinizzz/Isle](https://github.com/TheVinizzz/Isle)
License: MIT. Main language: Swift. Last push: 2026-09-16T03:19:21Z; archived: False. Files indexed: 59.

Swift/AppKit. One nonactivating borderless window with status-bar-relative level, full-screen auxiliary collection behavior, safe-area geometry, pointer hit gating. Full-canvas transparent windows require careful click-through. Distributed app media notifications avoid private media frameworks.

Inspected: `Isle/Features/NotchShape.swift`, `Isle/IsleApp.swift`, `Isle/NotchCoordinator.swift`, `Isle/NotchLayout.swift`, `Isle/Presenter/NotchPresenter.swift`, `Isle/Utils/NSScreen+Notch.swift`, `Isle/Welcome/WelcomeWindow.swift`, `Isle/Window/NotchWindow.swift`, `LICENSE`, `README.md`, `Isle/Window/NotchWindowController.swift`.

Compatibility: Native architecture concepts are applicable; source not imported. Reuse: MIT permits reuse with required notices, subject to per-file/assets review.

### [HSUNEH/Dynamac-Island](https://github.com/HSUNEH/Dynamac-Island)
License: MIT. Main language: JavaScript. Last push: 2026-10-05T16:09:32Z; archived: False. Files indexed: 194.

Electron plus optional native Swift overlay and pure geometry tests. Explicitly tests nonzero monitor origins. Native shell is a better fit; renderer transparency/OS clamping is a risk.

Inspected: `Sources/Dynamac-Island/Dynamac_Island.swift`, `Sources/DynamacIslandCore/IslandState.swift`, `Sources/DynamacIslandCore/NotchGeometry.swift`, `Tests/DynamacIslandCoreTests/IslandStateTests.swift`, `Tests/DynamacIslandCoreTests/NotchGeometryTests.swift`, `Tests/DynamacIslandCoreTests/main.swift`, `native/DynamacIslandNative.swift`, `LICENSE`, `README.md`.

Compatibility: Interaction/capability concepts only; platform code not imported. Reuse: MIT permits reuse with required notices, subject to per-file/assets review.

### [quietapps/QuietNotch](https://github.com/quietapps/QuietNotch)
License: GPL-3.0. Main language: Swift. Last push: 2026-06-17T20:19:28Z; archived: False. Files indexed: 285.

Swift native overlay/managers. License metadata and actual LICENSE are GPL-3.0 despite a README MIT badge: treat as GPL. Study display geometry and event-driven battery activity. Media/camera/system HUD permissions need clear disclosures.

Inspected: `QuietNotch/ContentView.swift`, `QuietNotch/MediaControllers/AppleMusicController.swift`, `QuietNotch/MediaControllers/MediaControllerProtocol.swift`, `QuietNotch/MediaControllers/NowPlayingController.swift`, `QuietNotch/MediaControllers/SpotifyController.swift`, `QuietNotch/MediaControllers/YouTube Music Controller/YouTubeMusicAuthentication.swift`, `QuietNotch/MediaControllers/YouTube Music Controller/YouTubeMusicController.swift`, `QuietNotch/MediaControllers/YouTube Music Controller/YouTubeMusicModels.swift`, `LICENSE`, `README.md`, `QuietNotch/managers/BatteryActivityManager.swift`, `QuietNotch/components/Settings/SettingsWindowController.swift`, `QuietNotch/components/Notch/QuietNotchWindow.swift`.

Compatibility: Native architecture concepts are applicable; source not imported. Reuse: No code copied; license review required before incorporation.

### [tukuyomil032/Perch](https://github.com/tukuyomil032/Perch)
License: Apache-2.0. Main language: Swift. Last push: 2026-08-15T02:37:37Z; archived: False. Files indexed: 464.

Read metadata, README and selected files listed below. Its platform-specific overlay strategy is reference only; inspect actual source before reuse. Do not infer tested performance or permission safety from feature lists.

Inspected: `perch/App/PerchApp.swift`, `perch/App/SettingsWindowSelector.swift`, `perch/Core/IslandCard.swift`, `perch/Core/IslandPresentation.swift`, `perch/Island/IslandChromeStyle.swift`, `perch/Island/IslandHost.swift`, `perch/Island/IslandSurfaceDriving.swift`, `perch/Island/NookBridge.swift`, `LICENSE`, `README.md`.

Compatibility: Native architecture concepts are applicable; source not imported. Reuse: No code copied; license review required before incorporation.

### [ethantiller/macisland2](https://github.com/ethantiller/macisland2)
License: not detected. Main language: Swift. Last push: 2026-10-09T16:30:56Z; archived: False. Files indexed: 368.

Swift package, one borderless NSPanel and modular features. No license grant detected: no reuse. Explicit docs distinguish rendered view pictures from real runtime behavior, a useful validation practice. Onboarding/settings are auxiliary to the island.

Inspected: `Sources/MacIsland/Agenda/AgendaMonitor.swift`, `Sources/MacIsland/Agenda/AgendaView.swift`, `Sources/MacIsland/Agenda/RemindersView.swift`, `Sources/MacIsland/Agents/AgentActivity.swift`, `Sources/MacIsland/Agents/AgentLimits.swift`, `Sources/MacIsland/Agents/AgentLogParser.swift`, `Sources/MacIsland/Agents/AgentLogWatcher.swift`, `Sources/MacIsland/Agents/AgentMark.swift`, `README.md`, `Sources/MacIsland/App/SettingsWindowController.swift`, `Sources/MacIsland/App/OnboardingWindowController.swift`.

Compatibility: Native architecture concepts are applicable; source not imported. Reuse: No code copied; license review required before incorporation.

### [niyamvora/ILoveNotch](https://github.com/niyamvora/ILoveNotch)
License: MIT. Main language: Swift. Last push: 2026-10-10T15:20:35Z; archived: False. Files indexed: 409.

Swift modular NotchCore/NotchSurface/NotchFeatures. FeatureLifecycle and priority engine are useful separations; performance tests exist but their results were not run. Broad transfers/calendar/camera capabilities expand the permission surface.

Inspected: `App/ShowInNotchIntent.swift`, `App/main.swift`, `Sources/NotchCore/FeatureLifecycle.swift`, `Sources/NotchCore/Log.swift`, `Sources/NotchCore/NotchEngine.swift`, `Sources/NotchCore/NotchPreferences.swift`, `Sources/NotchCore/NotchState.swift`, `Sources/NotchFeatures/Calendar/CalendarFeature.swift`, `LICENSE`, `README.md`, `Tests/PerformanceTests/NotchEnginePerformanceTests.swift`, `Tests/NotchCoreTests/NotchEngineTests.swift`, `Sources/NotchTransfer/QuickShare/Frames.swift`, `Sources/NotchSurface/NotchWindow.swift`.

Compatibility: Native architecture concepts are applicable; source not imported. Reuse: MIT permits reuse with required notices, subject to per-file/assets review.

### [BySergiMM/OmniMac](https://github.com/BySergiMM/OmniMac)
License: MIT. Main language: Swift. Last push: 2026-10-12T15:58:29Z; archived: False. Files indexed: 282.

Swift native utility, artificial-notch support, geometry tests and event observers. Advertised CPU numbers are unverified. Calendar/media bridges must remain optional. Pure display geometry translates well to Iris.

Inspected: `Sources/OmniMac/App/SettingsWindowController.swift`, `Sources/OmniMac/Features/Notch/AirDropPresenter.swift`, `Sources/OmniMac/Features/Notch/BatteryMonitor.swift`, `Sources/OmniMac/Features/Notch/CalendarBridge.swift`, `Sources/OmniMac/Features/Notch/HeadphonesWatcher.swift`, `Sources/OmniMac/Features/Notch/MediaBridge.swift`, `Sources/OmniMac/Features/Notch/MusicPlayer.swift`, `Sources/OmniMac/Features/Notch/NotchControls.swift`, `LICENSE`, `README.es.md`, `README.md`, `scripts/dev/frame.swift`, `Tests/OmniMacTests/NotchGeometryTests.swift`, `Sources/OmniMac/Features/Notch/NotchGeometry.swift`.

Compatibility: Native architecture concepts are applicable; source not imported. Reuse: MIT permits reuse with required notices, subject to per-file/assets review.

### [aliihsaad/WinDock](https://github.com/aliihsaad/WinDock)
License: MIT. Main language: JavaScript. Last push: 2026-10-30T09:32:24Z; archived: False. Files indexed: 286.

Windows/Linux host with Android remote dock. Not a macOS notch implementation. Study explicit LAN device setup and command routing; never expose unauthenticated local command endpoints. Native Linux bridge is not portable to AppKit.

Inspected: `native/linux/src/main.rs`, `LICENSE`, `README.md`.

Compatibility: Interaction/capability concepts only; platform code not imported. Reuse: MIT permits reuse with required notices, subject to per-file/assets review.

### [POX-project/disland](https://github.com/POX-project/disland)
License: GPL-3.0. Main language: Kotlin. Last push: 2026-10-31T04:54:13Z; archived: False. Files indexed: 192.

Android Kotlin/Compose overlay service. Draw-over-apps, notification listener and accessibility access are special permissions, not Mac equivalents. Study event routing and focus utility; GPL study only. Android background restrictions affect companion reliability.

Inspected: `app/src/androidTest/java/com/agupta07505/smartisland/IslandOverlaySmokeTest.kt`, `app/src/main/java/com/agupta07505/smartisland/MainActivity.kt`, `app/src/main/java/com/agupta07505/smartisland/SmartIslandApp.kt`, `app/src/main/java/com/agupta07505/smartisland/data/INotificationHistoryRepository.kt`, `app/src/main/java/com/agupta07505/smartisland/data/INotificationRepository.kt`, `app/src/main/java/com/agupta07505/smartisland/data/LaunchableApp.kt`, `app/src/main/java/com/agupta07505/smartisland/data/NotificationHistoryDbHelper.kt`, `app/src/main/java/com/agupta07505/smartisland/data/NotificationHistoryEntry.kt`, `LICENSE`, `README.md`, `app/src/main/java/com/agupta07505/smartisland/service/SmartIslandOverlayService.kt`.

Compatibility: Interaction/capability concepts only; platform code not imported. Reuse: No code copied; license review required before incorporation.

### [EvanKoe/expressive-cutout](https://github.com/EvanKoe/expressive-cutout)
License: GPL-3.0. Main language: Kotlin. Last push: 2026-10-20T06:45:47Z; archived: False. Files indexed: 194.

Android Kotlin/Compose. IslandEventBus and IslandMotion separate events from expressive transitions. README states no internet permission: adding a relay would change that privacy contract. Notification/overlay permissions remain sensitive. GPL study only.

Inspected: `app/src/main/java/com/ekoehler/expressivecutout/core/IslandEventBus.kt`, `app/src/main/java/com/ekoehler/expressivecutout/core/IslandPreviewBus.kt`, `app/src/main/java/com/ekoehler/expressivecutout/core/PermissionDotPreviewBus.kt`, `app/src/main/java/com/ekoehler/expressivecutout/data/IslandLayout.kt`, `app/src/main/java/com/ekoehler/expressivecutout/data/PermissionDotPreferences.kt`, `app/src/main/java/com/ekoehler/expressivecutout/overlay/DynamicIsland.kt`, `app/src/main/java/com/ekoehler/expressivecutout/overlay/IslandEvent.kt`, `app/src/main/java/com/ekoehler/expressivecutout/overlay/IslandMotion.kt`, `LICENSE`, `README.md`.

Compatibility: Interaction/capability concepts only; platform code not imported. Reuse: No code copied; license review required before incorporation.

### [ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp)
License: MIT. Main language: C++. Last push: 2026-10-30T05:51:01Z; archived: False. Files indexed: 2105.

MIT C/C++ local transcription with SwiftUI example. Optional future embedded voice engine; model downloads, binary provenance, memory/battery use and microphone consent require explicit handling.

Inspected: `examples/whisper.swiftui/whisper.swiftui.demo/WhisperCppDemoApp.swift`, `LICENSE`, `README.md`, `README_sycl.md`.

Compatibility: Interaction/capability concepts only; platform code not imported. Reuse: MIT permits reuse with required notices, subject to per-file/assets review.

### [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift)
License: MIT. Main language: C++. Last push: 2026-10-30T22:24:46Z; archived: False. Files indexed: 853.

MIT Swift/C++ Apple-silicon compute. Native local model candidate; inference memory, weights licenses and cancellation must be budgeted separately. Iris initially delegates model hosting to LM Studio.

Inspected: `LICENSE`, `README.md`.

Compatibility: Interaction/capability concepts only; platform code not imported. Reuse: MIT permits reuse with required notices, subject to per-file/assets review.

### [kdeconnect/kdeconnect-kde](https://github.com/kdeconnect/kdeconnect-kde)
Unavailable at research time: FETCH ERROR HTTP Error 404: Not Found. License, structure, platform and reuse permission unverified. No code used.

## Motion references and primary documentation
- [Gooey liquid effect](https://www.inspora.design/posts/4-5), [Wafer page](https://www.inspora.design/posts/wafer-page), [Motion collection](https://www.inspora.design/?category=Motion): pages resolve, but text extraction does not expose actual animation timelines. Treat liquid joins, continuity and short reveals as brief-directed hypotheses, not a claimed frame-by-frame study. [Wafer](https://app.wafer.ai) is client rendered; no implementation copied.
- [LM Studio compatibility](https://lmstudio.ai/docs/developer/openai-compat): real `/v1/models` and `/v1/chat/completions` endpoints, user-supplied server URL and exact model ID.
- [OpenAI sign-in quickstart](https://developers.openai.com/siwc/quickstart): eligible open-source/local clients have supported ChatGPT-plan sign-in; selected commercial clients have different availability. Do not borrow Codex client IDs or scrape browser sessions.
- [Google Gemini OAuth](https://ai.google.dev/gemini-api/docs/oauth): requires configured Google Cloud project, enabled Generative Language API, OAuth consent and desktop client registration. A Gemini consumer subscription alone is not a generic API credential.
