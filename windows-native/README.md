# Iris for Windows

AriZe’s native WinUI 3 application source. Its standalone package targets maintained Windows 11 x64 and ARM64 systems. This source checkpoint has passed the portable test harness and Windows SDK reference checks. A Windows host is still required to finish the app build, launch it, and verify the package. [Parity matrix](docs/FEATURE_PARITY.md) · [Verification and release gates](docs/VERIFICATION.md)

## Build on a Windows development host

Use PowerShell 7 and a supported Windows 11 host. Install the Windows application development workload for Visual Studio, Windows SDK 10.0.26100 or a compatible newer SDK (including MakeAppx and SignTool), and the SDK pinned in `global.json`. Installers and SDKs must come from the supported Microsoft sources. [Windows App SDK](https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/downloads) · [MakeAppx](https://learn.microsoft.com/en-us/windows/msix/package/create-app-package-with-makeappx-tool)

```powershell
./scripts/Build-Windows.ps1 -Configuration Release -Architecture x64 -Msix
./scripts/Build-Windows.ps1 -Configuration Release -Architecture arm64 -Msix
```

Use `-Configuration Debug` for diagnostics. Build outputs and logs are under `artifacts/<configuration>/<architecture>/`. Each build runs the portable checks and publishes self-contained files, then creates a test ZIP. `-Msix` also produces an MSIX package for signing. For a licensed certificate already in the authorized Windows certificate store, pass `-CertificateThumbprint` and `-TimestampUrl` with `-Msix`. The signing certificate’s subject must match the manifest publisher, and the certificate chain must be trusted by the target machine. Until signing is configured, use the ZIP for internal testing. [Sign an MSIX package](https://learn.microsoft.com/en-us/windows/msix/package/sign-app-package-using-signtool)

## Internal Windows test

1. On the matching architecture, compare the archive hash with the build's SHA-256. Extract the entire ZIP and launch `Iris.exe` from the extracted folder. Keep Windows security controls enabled. The test ZIP has no installer registration.
2. In Settings, enter the provider and model. For a compatible local server, start the server and use its loopback URL, such as `http://127.0.0.1:1234/v1`. Cloud providers require your own developer key. A Cloudflare Account ID and Workers AI token enable the Images page. Use an approved test account for quota-sensitive requests.
3. Try a chat, Stop, New, export, memory recall, and simultaneous text agents. Open Computer and select Notepad. Use Screen text to choose a test window and attach its extracted text. Try dictation and Read aloud with system permissions granted. Add a trusted MCP fixture and confirm the endpoint, tool, and arguments before calling.
4. Test Ctrl+Alt+Space, capsule visibility, DPI, fullscreen and multi-monitor placement. Deny a capture or microphone prompt and verify that chat stays usable. Close and relaunch. History remains available and interrupted agents do not restart. A corrupt workspace should be preserved.
5. For the signed MSIX, verify the publisher and then open it in App Installer or run `Add-AppxPackage -Path '<signed-package>'`. Check Start menu launch, repeat setup, update and uninstall from Settings. The unsigned MSIX is a staging artifact. This project does not require changing execution policy or disabling Windows protection.

## Private CI

Copy this source tree into an approved **private** GitHub repository. Keep `.github/workflows/windows.yml` at its root and verify GitHub Actions entitlement or connect a Windows runner. Push the source, open **Actions / Iris Windows internal build**, and run it for your architecture and configuration. Artifacts contain ZIP, MSIX, SHA-256 and logs when their steps succeed. The workflow is manual, read-only with respect to repository contents, and has no public release step. Hosted jobs can use paid minutes beyond an account’s inclusion. Verify the budget before dispatch. [GitHub Actions billing](https://docs.github.com/en/actions/concepts/billing-and-usage)

## Code and storage

`Iris.Core` is platform-neutral .NET. It owns provider codecs, bounded event streams, memory selection and workspace storage. `Iris.Windows` owns WinUI, DPAPI, local OCR, selected-window capture, native speech, and desktop presence. macOS retains its Swift implementations. There is currently no automatic sync or import between editions.

Workspace files and DPAPI-encrypted credentials use the current user's Local AppData under `AriZe/Iris`. Profile files include conversation text and memories. Review them before sharing diagnostics. Cloud chat sends the selected history, matching memories and explicit attachments. Screen capture runs on demand and supplies extracted text to the composer. The user chooses when to send it. MCP tokens are session-only and results are displayed in the connection page.
