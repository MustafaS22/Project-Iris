# Computer-use reliability diagnosis

The reported task showed a Safari frame and zero actions. A frame is produced before the first planner reply. No trace from that original task identified which request stalled. Source inspection found two concrete startup dependencies: the session waited for all enabled MCP servers, then waited for the first planner decision before opening the named app.

The session now resolves explicitly named installed apps and verifies foreground activation before the first planner turn. Native actions can proceed while external tool discovery runs. Planner requests use a dedicated resource timeout, report provider failures, and can retry without a rejected image. The activity view distinguishes launch, provider, observation and action review. A task reaching its execution deadline reports the last stage.

Live testing exposed a second failure. Spotify had started playback, but rejecting its completion claim replaced the observation used for proof. The session now keeps verification feedback separate from tool evidence. An actual read of the interface after input can verify the result, and the model must still quote matching evidence before claiming success.

Accessibility and Screen Recording are checked when a tool requires them. The task offers the macOS request and settings link, checks for the grant, and re-observes before taking another action. A system-mandated restart requires retrying the task. Apple Events are outside the native execution path. Direct file tools require Iris folder grants.

To diagnose a live run, open Console and filter the subsystem `com.projectiris.Project-IRIS` and category `computer-use`, with info messages enabled. The events identify provider requests, responses, execution step and tool names. They omit screenshots, arguments, credentials and raw model output. The task's Action history shows user-facing failures alongside completed tool calls.

The live OpenAI test opened the real Spotify desktop window and used native coordinate clicks. The first run started Liked Songs but hit the old verification loop. The rerun resumed playback after a reviewed click and reported success. Spotify independently showed the playlist Pause control and an advancing playback timer. This path used neither a Spotify API nor a scripted planner. Coordinate clicks with unknown semantics still ask for review.

The live cross-app task entered 17 × 23 in Calculator, read 391, created a plain-text TextEdit document, and saved it in the requested temporary directory. A direct read verified the saved bytes. Iris ran out of wall-clock time waiting for approval during its subsequent reopen check. The watchdog now excludes pauses, approval and permission waits from the five-minute execution budget, with a 15-minute outer cap. This timeout adjustment is separate from the already verified file save.

The final signed Debug build passed real Notes creation and writing, Finder folder creation and rename, Safari search and result navigation, delayed controls, dialog handling, frame and stale-target checks, native and external MCP, and Escape during review. Those regressions used local test fixtures. The core suite reported 336 passing tests. See `Validation/results-2.1.2.json` for observations and limits.
