# Local integration validation

The Debug-only `--iris-computer-use-validation` entry point exercises actual native AppKit controls, window screenshots, file operations, MCP transport/discovery/reconnect, and a mixed native/MCP task. The planner fixture deliberately supplies deterministic JSON decisions; it does not simulate the operating system or fabricate tool results. It uses no cloud AI quota. Browser validation runs real headless Chrome through Microsoft's official Playwright MCP server against a local page, not personal tabs.

Use a disposable development session. Build Debug with the canonical Xcode project. Preserve the normal signing identity and installed bundle path if testing existing TCC grants. Never reset privacy permissions to make a test pass. Missing permissions are reported as blockers.

1. Create `/tmp/IrisComputerFixture.app/Contents/MacOS`, compile `NativeFixture.swift` as `IrisComputerFixture`, and supply a normal app Info.plist with executable `IrisComputerFixture`, identifier `com.arize.iris.computer-fixture`, and package type `APPL`.
2. Run `python3 http_mcp_fixture.py` (localhost port 5198) and `python3 planner_fixture.py` (localhost port 5196). Both touch only their isolated test files.
3. Serve this directory's `index.html` on localhost port 5197, for example `python3 -m http.server 5197 --bind 127.0.0.1`.
4. Install `@playwright/mcp@0.0.86` in a disposable npm cache and locate its `cli.js`. Node.js 20+ and Google Chrome are required for this particular test fixture. Production users can configure other supported Playwright browsers.
5. Launch the signed Debug app through Launch Services:

```sh
open -n /Applications/Iris.app --args --iris-validation --iris-computer-use-validation --iris-test-playwright-cli /absolute/path/to/@playwright/mcp/cli.js
```

The harness writes `results.json` and `activity.png` below `FileManager.default.temporaryDirectory/IrisComputerValidation`, which may differ from `/tmp` on macOS. It uses temporary folder bookmarks only in memory, keeps production task history separate and does not change existing TCC permissions or AI accounts. The modal-dialog trigger and HTTP fixture files live under `/tmp/IrisComputerValidation`. Stop the local servers after validation. The native fixture is terminated when the harness exits.

`swift test --package-path IrisCoreTests` runs the portable policy, model-protocol and existing regression tests. Synthetic coordinate tests complement the actual connected display test; they do not establish real multi-monitor hardware coverage. Live AI planning quality across every supported model and arbitrary third-party applications requires separate user acceptance testing.
