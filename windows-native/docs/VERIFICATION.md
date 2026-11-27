# Verification and production readiness

## Evidence

- 13 portable .NET checks passed with a fake network transport, no user credentials or paid requests. Covers workspace load/save/interruption, corrupt preservation, atomic cancellation, memory relevance, endpoint restrictions, OpenAI/Gemini streams, oversized and interrupted streams, quota errors, Cloudflare envelope, MCP session lifecycle, and cancellation.
- Windows App SDK 2.7.0 and the selected Windows reference packs restore in locked mode on macOS. Reference resolution selected runtime packs for both x64 and ARM64. Native C# was compiled against the resolved references, substituting temporary field declarations for XAML-generated code. XML, control names and handler presence were checked. XAML compilation on the Mac did not generate the WinUI compiler output. This is not a Windows build, packaged result, or native runtime test.
- No Windows VM or attached Windows runner was available. A private GitHub Actions workflow was prepared. The available GitHub credential could not read the Actions allowance. No hosted job was dispatched and no source or package was published. An approved funded or free private runner, or a local Windows development machine, is required to proceed.
- macOS core regression suite passed 341 tests. The canonical macOS app, its user data, and the Electron test edition were kept separate from this project.

## Security assessment

| Boundary | Implemented protection | Remaining verification |
|---|---|---|
| Local credentials | DPAPI current-user protection, separate provider/token keys, plaintext input cleared from settings, HTTPS cloud destinations and no automatic redirects. | Windows profile migration, logout, corrupt credentials and unpackaged/MSIX filesystem behavior. |
| Screen and references | Windows picker, one in-memory capture frame, dimension limits and local OCR. OCR becomes explicitly attached untrusted context. | Graphics devices, WARP fallback, screen sharing indicators, screen picker cancellation and protected surfaces. Inspect provider request contents with inert fixtures. |
| External tools | MCP uses one selected endpoint, displays action details before execution, caps response sizes and has timeouts. Model text has no ability to call it. | Test trusted/nontrusted destinations, schema errors, expired sessions and protocol implementations. |
| Desktop actions | App initiation uses a fixed list and confirms foreground process matches. No arbitrary commands, desktop elevation or secure desktop input. | Negative foreground tests and machine policy, real app activation, cancellation after window launch. |
| Local stores | Bounded JSON reads, input validation and temp-file atomic replacement. Read failures preserve original data. | Dirty shutdown during writes, pre-existing data migration, antivirus/ACL behavior, and retention UX. |
| Software supply | Pinned .NET SDK and lockfiles, official Windows SDK packages, no application secrets in CI. | Advisory scan, final manifest review, reproducible output, action pin review and actual signing verification. |

## Performance assessment

Idle capture and inference are absent by design. The visible capsule uses a low-rate blink timer and reacts to foreground notifications. Chat windows display a bounded transcript, and agents have a two-request concurrency cap. GPU/CPU and working-set improvements are unmeasured. Compare cold/warm startup, 15-minute idle and active sessions, stream first token, response scrolling, UI animation, capture latency and memory on an x64 Intel/AMD machine and ARM64 Windows device. Test 100/125/150/200% scale, battery operation, two monitors, screen unplugging and sleep; record OS, GPU driver, model, Windows permissions and configuration.

## Release blockers

1. Follow the [build and install instructions](../README.md) on an approved Windows host, compile WinUI XAML, and verify Debug/Release for x64 and ARM64.
2. Run the full acceptance matrix using disposable Windows test data. Windows Speech, DPAPI, Windows Graphics Capture, app-launch verification, WinUI navigation, Narrator and high DPI are not runtime verified.
3. Finish parity gaps, especially general Computer Use, voice provider parity, advanced knowledge/connectors, drafting, native onboarding, and update infrastructure. Tenant credentials and OS grants must be explicitly authorized.
4. Verify user and administrator security boundaries and perform a threat-model review. Confirm packaging identity, get authorized signing, and test fresh install, signed upgrade, interrupted update, and uninstall.
5. Keep packages internal until separate release authorization. Current readiness is source checkpoint, not production.
