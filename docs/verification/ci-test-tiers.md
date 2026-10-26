# CI test tiers

Pull requests and pushes to `main` with non-documentation changes run all Core
and persistent Native tests, plus focused UI smoke coverage on both device
families. Existing check names stay unchanged for branch protection. The UI
runner builds once per lane and reuses that build and synchronization fixture.
The UI command records scoped host CoreSimulator unified and service logs and samples
memory, swap, disk and process usage every 15 seconds under
`.build/eventkit-fixture/host`. These diagnostics preserve the test command's
exit status and never shut down or restart a simulator. A simulator disappearing
mid-test remains a failure; its host evidence is uploaded alongside XCTest results.
Each selected Spotlight method runs first on its own newly created simulator,
matching the lane's device type and runtime. That simulator is shut down and
deleted after its result and diagnostics are collected, including on failure.
Share and the remaining UI methods then use the lane's original simulator.
An independent peer
verifies the uploaded UI task whenever the real-server synchronization scenario
is selected. The iPad smoke selection exercises workspace/keyboard behavior and
does not create that server task.

A lightweight Linux job classifies the complete pull-request diff from its merge
base, or the before/after range for a push. Documentation-only changes skip Core
and Native jobs; the iPhone/iPad check names still run on Linux and report the
skip without allocating an Xcode runner, building products or booting simulators.
The workflow itself is never filtered out, so its check contexts still appear.
The routing regressions run even for documentation-only changes.

The documentation allowlist is root Markdown files, nested `README.md` files,
root `LICENSE`/`LICENSE.txt`, and documentation/text/image/PDF files under `docs/`
(`.md`, `.txt`, `.rst`, `.adoc`, `.png`, `.jpg`, `.jpeg`, `.gif`, `.svg`, `.webp`,
`.pdf`). Unknown paths, mixed changes and executable examples run normal tests.
Renames inspect both old and new paths, so moving source into documentation does
not skip tests. Empty diffs, missing comparison commits and classification errors
also run tests. Nightly, manual and unrecognized event types always run tests,
including explicit smoke and diagnostic dispatches.

The installable Release workflow already ignores Markdown and `docs/` changes;
it also ignores the root license files so those documentation-only changes do
not allocate a signing/build runner.

| UI coverage | iPhone | iPad | Trigger |
| --- | --- | --- | --- |
| Smoke | 22 methods | 19 methods | PR, push, manual `ui_suite=smoke` |
| Full | All 73 declared methods | 63-method selection | Nightly at 02:00 UTC, manual `ui_suite=full` |
| Diagnostic | Existing 13-method subset | — | Manual `diagnostic_only=true` |
| Keyboard diagnostics | 11-method subset | 9-method subset | Manual `ui_suite=keyboard` |
| Text diagnostics | 5-method subset | 5-method subset | Manual `ui_suite=text` |

Full coverage on both families includes compact task rows, completion circles,
occurrence failure feedback and light/dark accessibility captures
(`TaskPresentationUITests`). Both families also cover morphing-row title/date editing,
picker dismissal, invalid/failing saves, Upcoming anchoring and accessibility overflow
(`TaskRowEditingUITests`).

Both device families check workspace control placement, every Settings destination,
Settings at the largest accessibility text size, persisted tab ordering and capacity,
and Projects drill-down. Both also hold an actual HTTP synchronization request open
to check title-adjacent progress and the absence of workspace synchronization footers,
then return a server failure and check that its details remain in Settings.
Appearance captures require visual confirmation of the
rendered mode. The iPhone smoke selection
checks capture/validation/cancel/reopen, durable
editing/completion, real-server synchronization, annotation toolbar saves,
native keyboard input, installed Share capture, installed widget behavior and
actual Spotlight opening/completion. The iPad selection checks keyboard-driven
capture/edit/completion/reopen, adaptive landscape/portrait views, custom views
at accessibility text sizes, modal annotation commands and native text input.
Share precedes the remaining workspace tests only when selected; the iPad smoke lane skips its separate
launch and host-fixture installation.

Calendar presentation, hidden missing-access/read-error states, and Settings access/Retry recovery run on both device
families in the full suite, including populated light/dark and largest-text
captures, saved start/end hours, source-calendar colors, empty Calendar/tasks and many-event scrolling. Controlled Calendar
sources establish presentation; actual EventKit authorization and read-only
local-source checks remain separate CalendarTodayUITests.

Native task actions, exhaustive typed attributes and filters, recurrence, Reminders copy/move and
permission changes, notification delivery/revocation, stale/peer Spotlight
results and repeated persistence/error journeys remain in the full suite.
Existing workflows enter their destinations through Settings. iPad-only methods still
skip on iPhone. Source selectors live in `scripts/ui-test-selection.py`; its
checks reject renamed selectors and empty UI selections.

Keyboard diagnostics retain native command delivery, installed Share capture,
Calendar failure capture, workspace creation, view ordering and automatic-sync
failure recovery. They also exercise annotation creation, real-server connection
entry and typed rating menus on both families, plus dependency navigation and
project text replacement on iPhone. This focused manual selection uses the smoke time limits and
does not change PR or nightly coverage. Keyboard-dismissal admission requires a
visible software keyboard, a control outside its occupied area, and two stable
geometry samples within the existing 20-second control deadline.
Its distinct check names prevent the focused subset from satisfying the
canonical XCUITest branch-protection checks.
Its separate concurrency group allows diagnostics to run alongside full coverage;
repeated keyboard dispatches replace only the earlier keyboard run.

Text diagnostics cover local attribute creation, series-rule and typed-value
replacement, Share editing and independent native text input on both families.
They use the smoke time limits,
separate check names and a separate concurrency group. They do not change smoke,
full or keyboard selections or satisfy canonical branch-protection checks.

One owned relay process performs the fixed UP-only initialization and then arms
the live log using the same client context. Client connection setup and the UP-only
RPC share the initialization budget; later commands reuse that context instead of
opening a client connection within each dispatch budget. Dispatch failure retains
the existing UP-only cleanup before the context closes, with no command replay or
added reconnect loop. The owner allows 30 seconds from child launch
for initialization and 10 seconds from its recorded completion for arming.
Sticky initialization proof survives the transition to waiting; both admissions
validate the owned relay PID, companion PID, session token, device and socket.
XCTest starts only after both phases succeed and both processes remain alive.
UP-only initialization does not establish native input acceptance. Existing
request, dispatch and recovery limits remain unchanged.

Native keyboard cases prepare the runner container in the background at case
start, with a 30-second discovery cap. Each request still keeps its original
12-second deadline and five-second dispatch reservation. A discovered path is
only cached for its device, runner bundle and process after checking the exact
owner, attempt and nonce request file; every subsequent request is checked too.
Outstanding discovery children are cancelled, reaped and recorded on exit.
An already timed-out background preparation is retained in diagnostics and does
not invalidate a later shortcut request. That request may perform one fresh
lookup using its original deadline and five-second dispatch reservation. A
pending preparation timeout, failed live lookup or mismatched request still
fails without command replay or an extended budget.

UI products build in a separate 20-minute step before creating/booting a test
simulator. Execution reuses those signed arm64 products with `--skip-build`.
The disposable simulator uses an available runtime matching the selected iOS
Simulator SDK's major/minor version. An unrelated newer installed runtime cannot
silently change the lane's device or OS; a missing matching runtime fails with
the SDK version in the error. Simulator selection has portable regressions in
`scripts/test-ui-test-simulator.py`, run by the routing job.
Spotlight phase selection honors the original include/skip filters and runs
each selected method exactly once. Its 600-second method limits, indexing/query
budgets and actual system Search/UUID/completion assertions are unchanged.
A failed Spotlight phase stops the lane before Share/main execution, preserving
the failure and uploading its diagnostics immediately after owned cleanup.
Successful lanes retain the complete selection. There is no automatic case retry.
Separate `TestResults-spotlight-*.xcresult`
bundles and `.build/eventkit-fixture/spotlight/<method>` diagnostics distinguish
simulator preparation, app launch and indexing/search failures. `phases.json`
records each owned simulator, result, exit status and cleanup outcome.
Timed guest log streams use `log stream --timeout` and expire inside the guest.
The method-aligned Spotlight stream covers its existing 600-second XCTest window
or stops when the method ends, so slow setup cannot consume the capture before
the first query. The separate workspace stream retains its 60-second cap.
The collector does not terminate the host `simctl spawn` client at its duration
boundary while XCTest is active. Explicit test completion and cancellation still
reap the owned logging process. This transport change requires CI verification;
the local forced-stop probe did not reproduce the hosted SimLaunchHost restart.
The runner regressions cover selection preservation, separate devices,
failure propagation, failed-boot cleanup and preservation of prebooted devices.
Smoke execution has a 45-minute step limit and a 60-minute overall job limit.
The expanded workspace selection exceeded the former 30-minute step limit;
the measured iPad run spent 10 minutes 33 seconds in simulator preparation
before starting `xcodebuild`. The additional budget covers preparation and
the selected journeys without changing individual test limits or assertions.
Full execution/job limits are 150/180 minutes; diagnostics have 60/90-minute limits.
These are ceilings, not measured completion times. Every method retains the
600-second XCTest limit. The later `always()` step removes the owned simulator
after a UI step failure or timeout. Runtime and signed-distribution acceptance
still require their actual results; a smoke pass establishes only its selected
workflows.

Run the full suite on a published branch before accepting changes to system
integrations or workflows outside smoke coverage:

```sh
gh workflow run ci.yml --repo Julesseg/tsk --ref <branch> -f ui_suite=full
```

Manual dispatch defaults to full coverage. The nightly schedule runs the
default branch once the workflow is merged. Manual, scheduled and PR/push
runs have separate concurrency groups, so dispatching full coverage preserves
an active PR run. Repeated dispatches on the same branch replace each other.
Verify the run's head SHA before attributing its result to a change. Existing
artifact names and ownership/cleanup evidence are retained.

Inspect the exact selection or verify routing without booting a simulator:

```sh
python3 scripts/ui-test-selection.py select smoke iPhone
python3 scripts/ui-test-selection.py select full iPad
python3 scripts/test-ui-test-selection.py
```
