# CI test tiers

Pull requests and pushes to `main` with non-documentation changes run all Core
and persistent Native tests, plus focused UI smoke coverage on both device
families. Existing check names stay unchanged for branch protection.

Each device family uses a workspace worker and a row-editing worker for smoke
and full coverage. The workspace worker retains the previous selection; the
row-editing worker runs the nine added row journeys. Their selections are
disjoint and their union is the complete selected suite. Every original native
keyboard case remains in the workspace worker with its existing HID owner,
identity checks and deadlines. The row journeys use XCTest text input and do
not select native HID command cases. Each worker builds once and owns one
isolated simulator. Share runs before the remaining workspace cases when
selected; Spotlight remains in that original workspace pipeline.

The existing `App · XCUITest (macOS)` and `App · XCUITest (iPad)` checks require
all workers for their device family to complete successfully. They inspect jobs
from the current run attempt, so a missing, duplicate, skipped, cancelled,
failed or still-running worker cannot produce a green gate. Artifacts keep the
existing workspace names and add a `-row-editing` suffix for the new worker.
Focused keyboard, text and diagnostic dispatches retain one worker per selected
family because their selections do not include row-editing coverage.

An independent peer verifies the uploaded UI task whenever the real-server
synchronization scenario is selected. The iPad smoke workspace selection does
not create that server task.

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

UI products build in a separate 20-minute step before creating/booting a test
simulator. Execution reuses those signed arm64 products with `--skip-build`.
The disposable simulator is pinned to iOS 27.0 with Xcode 27.0, rather than
selecting an unrelated newer installed runtime. Both device families preserve
the original shared-simulator test pipeline and its ownership cleanup.

Smoke execution retains a 45-minute step limit and a 60-minute overall worker
limit. The unpartitioned iPad smoke run on 08c5e4d spent about ten minutes in
preparation, passed 17 cases (including all nine row journeys), then hit the
step limit while the next case was progressing without an assertion failure.
Separating the added row journeys preserves every case and its 600-second
method limit and targets that cumulative timeout without increasing budgets. The workspace workers
run 13 iPhone or 10 iPad smoke methods; row workers run nine methods on either
family. Full coverage partitions the 73 declared iPhone methods as 64 + 9 and
the 63 selected iPad methods as 54 + 9. Full execution/job limits stay at
150/180 minutes; diagnostics keep 60/90-minute limits.
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
