# CI test tiers

PRs and pushes to `main` run all Core, Native, Apple-framework and controller
tests plus three iPhone smoke journeys. `App · XCUITest (macOS)` remains the
required iPhone rollup; its name refers to the Mac runner. Native iPad support
and coverage are retired under [ADR 0007](../adr/0007-iphone-only.md).
The manual form defaults to smoke.

| Coverage | iPhone | Trigger |
| --- | --- | --- |
| Smoke | 3 methods | PR, main push, explicit dispatch |
| Full | 32 methods | Nightly at 02:00 UTC, explicit dispatch |
| Diagnostic | 27 on-demand methods | `diagnostic_only=true` |
| Keyboard | 2 methods | Explicit dispatch |
| Text | 3 methods | Explicit dispatch |
| Regression | 5 methods | Explicit dispatch |
| Menu | 5 methods | Explicit dispatch |

`full` means the reviewed nightly selection, not every UI test in the target.
[scripts/ui-test-selection.py](../../scripts/ui-test-selection.py) lists exact
methods for every suite. Each of the 59 retained methods has exactly one primary
cadence: nightly or on demand. Smoke is a subset of nightly; focused suites may
combine both. An unregistered, duplicated or missing method fails routing, so a
new test cannot silently expand PR or nightly coverage. Inline actor attributes
are included in source discovery.

Smoke covers inline capture/cancellation/save/relaunch, row validation/native
pickers/outside-save/durable completion, and actual hold/drag selection with
held-touch refresh stability, scrolling recovery and a staged dates/completion
Apply. The gesture also runs without native list accessibility identifiers.
Smoke needs no synchronization server, independent peer or native HID transport.

Nightly keeps bulk reset/cancel/mixed dates, failed Apply and valid/invalid editor
handoff; row notes, tag validation and dependency navigation; saved views/native
reordering; occurrence success/failure; series preview/cancel/commit; manual and
automatic-failure sync; real EventKit Calendar and Reminders; destructive move
source-change/interruption safety; installed Share/widgets/Spotlight; actual
closed-app and received-sync notification delivery; native HID command/focus
routing; external add/callback URLs, structured Find results/callbacks and draft-safe navigation. Full coverage is
required for workflow/system changes and behavior outside smoke. It does not
certify on-demand scenarios. Run the relevant focused/on-demand suite when a
change touches those contracts. Moving frequency does not establish acceptance.

On-demand coverage retains genuine lower-priority UI contracts: appearance and
large text, exact row geometry and animation drift, native Project-menu stress,
focus and retained-open scroll, Calendar display settings, notification Settings
revocation, detail activity/annotation controls, recurring authoring/copy, stale
Spotlight results and undeliverable callbacks. These do not run automatically at
night or on PRs. Their original assertions and deadlines remain. See the
[consolidation record](test-suite-consolidation.md) for the deletion rationale,
baseline and accepted gaps.

The Menu suite retains three native Project-menu journeys plus product annotation
and workspace/editor HID cases. Its stress case still opens and dismisses New
project twenty times with five-second acknowledgements, including title/note
keyboard handoff. Its scroll-retention case still uses 80 real project values,
a settled distant neighborhood, ten untouched seconds and two-point endpoint
geometry. The animation case still requires one-point presentation-frame
stability. These contracts moved out of scheduled coverage without relaxed bars.

The nightly HID workspace/editor journey retains all thirteen input phases and
native outcomes, including selection Escape/Return behavior and capture after
returning from Settings. The annotation case runs on demand. The standalone
UIKit keyboard-control UI test is retired; protocol/ownership host regressions
remain. The Menu, Keyboard, Text and Diagnostic suites need native HID but no UI
sync server or peer. Regression retains Share, row editing, native menu stress
and view ordering without HID/server/peer setup.

Green smoke does not certify extensions, permissions, system delivery or native
HID. Historical reports before ADR 0007 include retired iPad cases and do not
establish current iPhone acceptance. Neither simulator UI nor direct intent
`perform()` tests prove external Shortcuts/Siri or physical-device invocation.

## Build once, execute selected coverage

The Linux Native job runs `TskNativeTests` with a pinned Taskwarrior 3.5.0 client,
the real synchronization server and the native probe. The Mac producer runs
`TskNativeAppleTests`, including App Intents, EventKit, item providers,
notification content and owned Spotlight indexing, using the same fixture
versions. Apple tests have their own SwiftPM target so Linux compilation cannot
silently stand in for their execution. Both jobs use
`scripts/build-taskwarrior-fixture.sh` to verify the official release archive's
SHA-256, build its executable target and install the CLI with its runtime data
under `.build/taskwarrior-install`. Release sources retain the exact `3.5.0`
version contract used by conformance tests. Each discovered sync test runs with a
fresh server/client/secret/database; other tests run together. The test runner
records selections, logs and outcomes, requires an exact completed-method receipt
without skips, rejects missing/ambiguous sync selectors,
and preserves a failing batch while continuing independent cases. Diagnostic-only
dispatches retain their focused UI path and do not run either Native target.

The owned Python proxy and multiprocess fixture unblock inherited `SIGTERM`
before publishing readiness or spawning helpers;
Swift 6.0.3's Linux test runner can otherwise leave it blocked in children and
hang synchronous cleanup after synchronization has finished. A focused regression
requires the actual proxy to terminate after readiness. UTF-8 export assertions
project raw JSON through Python into an array of fields before decoding in Swift,
preserving both canonically equivalent key spellings that the Linux Foundation
JSON-to-dictionary observation path collapses. The byte-exact field, tag and
project assertions remain on actual Taskwarrior exports.

The common UI launcher suppresses animations for functional checks. The row-editor
launcher and explicit animated workspace cases restore them. Results from
suppressed-animation journeys do not certify transition timing or performance.
Direct intent fixtures call the actual `perform()` implementation; their app
readback does not certify external Shortcuts/Siri discovery or invocation.

Ordinary smoke/full runs leave expensive participant and keyboard traces off.
Focused diagnostic, keyboard, text, regression and menu selections explicitly
forward `TSK_UI_DIAGNOSTICS=1` to the app. An isolated replica alone does not
enable them. Receipts coalesce by file on a utility queue, outside input dispatch;
Share's explicit request-scoped fixture flushes before completing the extension.
Diagnostic snapshots remain best-effort if a process is killed before the next
flush. Transport acknowledgements and UI outcome assertions are independent of
these optional traces.

One Mac producer builds the simulator bridge, controller tests and signed arm64
UI products. It validates intent metadata and App Group entitlements before any
simulator is created. The selected coverage determines whether it also builds
the real synchronization server and independent peer for UI workers; ordinary
builds also produce them for the unchanged Native tests. Rust caches already exist;
Core/Native Linux Swift builds have separate toolchain-specific caches.

A compressed artifact preserves executable permissions and bundle symlinks.
Workers verify its checksum, Git commit/tree, Xcode version, SDK version/build,
architecture, installed matching runtime versions/builds, and app signature
before installing anything. The producer's immutable artifact ID selects the
products, including on partial reruns. A worker cannot silently consume products
from another source or toolchain.

Smoke uses one Mac execution worker; full uses two, after the shared producer.
The retained full partitions are:

| Family | Workspace | Task/row editing |
| --- | ---: | ---: |
| iPhone | 21 methods | 11 methods |

The partition union is exactly the full selection, with no duplicates or skips.
All native HID cases, installed system integrations and server/peer consumers
remain in workspace. The task worker requires neither native HID nor a server.
Share executes before the rest of its worker. Portable selection and ownership
regressions run once on Linux; controller regressions run in the producer.

Measure the complete iPhone-only workflow, including build, setup, queue and
cleanup, before deciding whether full coverage belongs in PR checks. Removing
iPad reduces runner work; it does not automatically halve elapsed time because
the previous device workers ran in parallel. PR coverage remains smoke until a
measured result supports changing that policy.

Every execution worker owns one disposable simulator. Existing isolated
ownership, cleanup traps and `always()` deletion remain. During Share and main
execution, an asynchronous monitor checks only the owned device. A positively
observed `Shutdown` stops the owned process group and reports infrastructure
exit 74. Missing/slow/invalid queries do not assert device loss. Monitor queries
are bounded and killed/reaped without blocking native keyboard request delivery.
Ordinary test assertions still allow independent methods to finish. The first
failure is annotated immediately, rather than waiting for the suite's last case.

## Results and gates

Each worker uploads its original xcresult bundles and runtime/transport receipts,
plus `.build/ui-execution.json` with source, attempt, device family, suite,
completed method durations and failures. Job summaries show XCTest duration and
slow methods. Family gate summaries separately show runner queue and occupied
time; unassigned cancellations contribute zero occupied time.

Gates read only the current run attempt. GitHub materializes retained successful
jobs in later attempts; repeated timestamps do not represent new execution.
Missing or nonterminal API results refresh with backoff under a 90-second
monotonic deadline. Actual failed/cancelled/skipped workers and duplicate results
fail immediately. Failure to converge remains red. A stale gate can be rerun
alone; rerunning all UI workers to refresh API state is unnecessary.

Build limit is 35 minutes, including a 20-minute UI build step. Smoke retains
45-minute execution/60-minute worker limits; full retains 150-minute execution
with a 165-minute worker limit after moving builds out; focused diagnostics have
60/90-minute execution/worker limits. Each XCTest method retains its 600-second
allowance. These are ceilings, not performance targets. A polling deadline does
not interrupt a blocking XCTest accessibility call.

Native HID initialization, fixed case/phase sequences, nonce/PID/device/socket
checks, request deadlines, UP cleanup and public XCTest acceptance remain
unchanged. Keyboard dismissal still requires visible geometry and two stable
samples within 20 seconds. It prefers keyboard frames from the same app snapshot. If that hierarchy omits
the keyboard, the original query against the same owning application supplies
the geometry; absence still fails rather than inventing a keyboard frame. Native Select All still
requires the real long-press menu, a unique visible enabled/hittable native menu
item or button within five seconds, and actual clear/readback assertions. Each
sample binds the unique native candidate from one scoped query; its observed
geometry supplies the touch without re-querying the disappearing menu. Empty
application frames require containment in an actual owned window.

Keyboard geometry comes from one snapshot traversal without visiting individual key
contents. Geometry diagnostics print after admission and input, so log output
cannot consume the readiness deadline. Password prompts require valid geometry
from their owning application before querying a native hit point.
Capture typing resumes after a confirmed password interruption only when the
entered text remains an exact prefix; complete readback and durable save are
still required.

Transient GitHub jobs-API HTTP 429/500/502/503/504 responses and request timeouts
retain upstream retries, up to three attempts. Requests and backoff consume the
same 90-second run-ID convergence budget. Authorization errors, malformed responses
and terminal test failures fail immediately; API retries never replay tests.

## Dispatch and retries

Use the helper after publishing a frozen branch:

```sh
python3 scripts/dispatch-ui-tests.py --ref <branch> --suite full \
  --reason 'Verify the reviewed nightly selection at this source revision'
```

It reuses queued/running manual work only for matching source, branch and suite.
To reuse completed successful evidence, supply `--identity <manifest.json>` with
the expected exact source/toolchain/runtime identity from the
`ui-execution-identity` artifact. Without it, success on a matching SHA alone is
insufficient. Failed matching coverage requires diagnosis and a targeted job
rerun; `--force` is reserved for an explicitly reasoned new experiment. Verify the
resulting run SHA. A branch move during admission fails rather than dispatching
an unintended source.

PR/push, nightly, full/manual and focused diagnostics have separate concurrency
groups. Repeated manual requests queue instead of cancelling in-flight evidence;
the helper avoids sequential duplicates. Direct Actions-form requests and
simultaneous clients still need inspection: concurrency is not a global cache
or a guarantee against all duplicate dispatch races.

Classify failures before retrying. Refresh a stale gate alone. Fix compilation,
metadata, repeat assertions and changed-code defects. At most one targeted
same-source retry for evidenced infrastructure failure; keep the first verdict
and stop repeated retries if the cause persists. Focused results supplement full
acceptance and cannot satisfy canonical branch protection by themselves.

Documentation-only changes run routing and named UI workers on Linux without
Xcode or simulators. Unknown/mixed/empty/invalid diffs run normal tests. Nightly
and manual dispatch always request real coverage. The installable Release
workflow runs automatically for every PR, with manual rebuilds also available;
see [release documentation](../../ci/README.md).

Inspect selections without booting a simulator:

```sh
python3 scripts/plan-ui-tests.py full
python3 scripts/ui-test-selection.py select full iPhone --partition row-editing
python3 scripts/test-ui-test-selection.py
```
