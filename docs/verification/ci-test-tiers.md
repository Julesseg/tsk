# CI test tiers

PRs and pushes to `main` run all Core and persistent Native tests plus smoke
coverage on both device families. `App · XCUITest (macOS)` and
`App · XCUITest (iPad)` remain the required checks. Nightly runs use full
coverage. The manual form defaults to smoke; choose coverage explicitly when
using the dispatch helper.

| Coverage | iPhone | iPad | Trigger |
| --- | --- | --- | --- |
| Smoke | 4 methods | 2 methods | PR, main push, explicit dispatch |
| Full | 72 methods | 66 methods | Nightly at 02:00 UTC, explicit dispatch |
| Diagnostic | 12 methods | — | `diagnostic_only=true` |
| Keyboard | 12 methods | 10 methods | Explicit dispatch |
| Text | 4 methods | 4 methods | Explicit dispatch |
| Regression | 5 methods | 6 methods | Explicit dispatch |
| Menu | 6 methods | 7 methods | Explicit dispatch |

Smoke covers capture, validation, cancellation, durable row editing/completion,
view ordering/capacity and real-server sync on iPhone, plus adaptive navigation
and row editing on iPad. Hardware keyboard, installed Share/widgets/Spotlight,
permissions, notification delivery and other system integrations retain their
full-suite assertions. Green smoke does not certify them. Full coverage on both
families is required before accepting workflow changes, system integrations or
behavior outside smoke. Moving frequency does not establish acceptance.

Custom-attribute editors/definitions and their dedicated cases are retired. The
built-in arithmetic saved-view test remains in Keyboard/Text. Share coverage now
checks automatic plain-description capture without an editor or extra fields.

Regression coverage retains the installed Share, durable/organization row editing,
and view-reorder journeys on both families, plus the
iPad keyboard/calendar journey. It is a focused diagnostic loop for the observed
failures, with original input, assertions and deadlines. It does not replace
smoke or full acceptance. Only its iPad worker needs the native keyboard fixture;
neither worker needs the synchronization server or peer.

The native menu regression opens and dismisses New project twenty times in one
process after the original High selection/reselection sequence. Each cycle
requires the actual field to appear and disappear within the original five-second
acknowledgements, without changing the selected project or replaying a touch.
The final cycle opens the menu from a focused title and requires native keyboard
dismissal, covering the native menu activation focus handoff.
After the twenty cycles, it also opens Project from a focused note, checks the
same keyboard prerequisite and native action, retains the draft text, and returns
to title/note editing. An independent title/Notes focus regression reaches the same native opener and
keyboard-before-option assertion immediately on a fresh fixture, then verifies
actual field/Done behavior and returned text editing. It does not replace the
repeated case. Menu coverage retains both product methods and selects actual
native HID compatibility on both families: the standalone native input baseline,
the annotation presentation/editor scope, and a cross-family workspace/row-editor
journey. The latter starts without focused input, captures and saves with actual
commands, checks plain typing and selected-row editing/completion/view commands,
then verifies capture/save after returning from Settings and durable results.
iPad also retains its broader injected workspace journey; its iPad-only class
cannot supply phone coverage. Both menu workers therefore require the native
keyboard fixture, but neither requires the synchronization server or peer.
Transport ownership and complete case-specific phase acknowledgements must match
the native UI outcomes; a fallback action or transport ACK alone is insufficient.
Diagnostic menu rollups remain distinct from required smoke/full checks. The
completed minimal-root/host/first-claim controls and temporary receipt sink have
been removed; their historical outcomes are recorded separately.

Menu coverage also retains an independent real-product retained-open Project-menu case.
It seeds 80 actual project values through the existing persistent fixture, opens
once, drags only within the freshly admitted native collection, and establishes
a distant fully visible settled neighborhood. Two matching fresh samples over at
least 300 ms distinguish settling from later movement. Ten seconds follow with no
input or accessibility reads while normal product polling stays active. A fresh
endpoint must retain two consecutive interior anchor rows and their viewport
within 2 points, plus the draft selection. Edge-clipped/virtualized rows are not
compared as an exact visible set. Missing anchors require fresh neighborhood/video
corroboration to classify a reset; an AX-only gap remains incomplete. Selection/reselection then uses newly admitted geometry and the
original 20s admission/5s acknowledgement bars; a reopened menu may legitimately
need native scrolling again. A reset stops the case without replaying input.
This interval tests the newly reported retention contract, not a timeout change
in existing methods. Permanent full coverage is 72/66 across the same four workers:
iPhone 39+33 and iPad 34+32. The three iPad-only workspace methods remain selected
on iPad and are excluded from iPhone rather than being counted as skipped phone
coverage. The cross-family workspace/editor HID case remains selected on both.
The completed isolated real-component fixture and
Action dispatch/rollup surface are removed; the production stress, independent
focus and retention regressions remain. Menu 6/7 includes the actual HID ownership
requirements on both families. The complete-status publication correction skips
only unchanged successful status assignments; every poll, manager read, error
path and fixture bookkeeping remains. Both canonical action comparisons and smoke
passed at 440b1a2, including 20 cycles, Title/Notes and retained-open selection on
both families. That focused result does not replace clean-head HID, broader
regressions, full coverage or physical-device verification.

## Build once, execute selected coverage

One Mac producer builds the simulator bridge, controller tests and signed arm64
UI products. It validates intent metadata and App Group entitlements before any
simulator is created. The selected coverage determines whether it also builds
the real synchronization server and independent peer. Rust caches already exist;
Core/Native Linux Swift builds have separate toolchain-specific caches.

A compressed artifact preserves executable permissions and bundle symlinks.
Workers verify its checksum, Git commit/tree, Xcode version, SDK version/build,
architecture, installed matching runtime versions/builds, and app signature
before installing anything. The producer's immutable artifact ID selects the
products, including on partial reruns. A worker cannot silently consume products
from another source or toolchain.

Smoke uses two Mac workers; full uses four. Full retains the `workspace` and
`row-editing` partition IDs/artifact names for compatibility. `row-editing` now
includes ordinary task, built-in filter, recurrence and automation journeys:

| Family | Workspace | Task/row editing |
| --- | ---: | ---: |
| iPhone | 39 methods | 33 methods |
| iPad | 34 methods | 32 methods |

The partition union is exactly the full selection, with no duplicates.
All native HID cases, installed system integrations and server/peer consumers
remain in workspace. Task workers require neither native HID nor a server.
iPad smoke also uses neither. Share still executes before the rest of its worker.
Portable selection and ownership regressions run once on Linux; controller
regressions run once in the shared producer.

The split uses historical successful method medians, approximately 66/65 minutes
on iPhone and 72/68 on iPad before setup. These are balance estimates across
source versions, not promised duration or passing evidence. Four workers are
retained rather than assuming additional runner capacity. Measure new timings
before changing parallelism or setting shorter full-suite budgets.

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

Transient GitHub jobs-API HTTP 429/500/502/503/504 responses and request timeouts
retain upstream retries, up to three attempts. Requests and backoff consume the
same 90-second run-ID convergence budget. Authorization errors, malformed responses
and terminal test failures fail immediately; API retries never replay tests.

## Dispatch and retries

Use the helper after publishing a frozen branch:

```sh
python3 scripts/dispatch-ui-tests.py --ref <branch> --suite full \
  --reason 'Verify workflow changes on both device families'
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
workflow is separately opt-in; see [release documentation](../../ci/README.md).

Inspect selections without booting a simulator:

```sh
python3 scripts/plan-ui-tests.py full
python3 scripts/ui-test-selection.py select full iPad --partition row-editing
python3 scripts/test-ui-test-selection.py
```
