# Windows Iris 2.0 candidate

The release gate is a passing Windows 11 x64 install and real use of the core experience. The candidate and website changes remain local until that gate is met.

## Windows acceptance run

1. Build the Release x64 package with the locked [build script](../README.md). Sign with an authorized publisher certificate. Verify the exact installer using `signtool verify /pa <package>` and record its SHA-256.
2. Install on a clean, standard-user Windows 11 x64 account. Open from Start, minimize and restore with Ctrl+Alt+Space, and close and reopen. Inspect layout at 100% and 150%. Verify a foreground fullscreen app suppresses the Iris capsule.
3. In Settings choose a working loopback AI fixture. Send and stop a streamed reply. Send a second message and verify the exact answer. Close and reopen and confirm the correct conversation, settings and memory returned. Export Markdown to a selected path and open it.
4. Repeat setup with an authorized test provider if available. Save a key, restart and check a request works. Enter an incorrect credential and verify a usable error. Delete the test credential afterward.
5. Dictate a test sentence with and without Windows microphone permission. Play an answer. In Computer, request Notepad and check the observed/failed distinction. Select a disposable window for screen text and verify Iris does not send it until the user sends the message.
6. Run one text agent to completion and stop a second. Check settings and chat remain accessible. Record OS build, target architecture, package checksum, test fixture versions, screenshots and any missing feature information.
7. Uninstall and verify Start menu and package registration are removed. Ensure previous Windows 1.0 EXE remains available through the release history when publishing.

Full macOS feature parity is outside this release gate. Disclose current capabilities and known gaps in release notes. Website staging adds Windows 2.0 MSIX handling. Confirm actual signed Windows x64 MSIX package matches its structural upload requirements before deploying the staged site.
