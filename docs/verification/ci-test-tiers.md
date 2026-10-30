# CI test tiers

PRs and pushes to `main` run all Core and persistent Native tests plus smoke
coverage on both device families. `App · XCUITest (macOS)` and
`App · XCUITest (iPad)` remain the required checks. Nightly runs use full
coverage. The manual form defaults to smoke; choose coverage explicitly when
using the dispatch helper.

| Coverage | iPhone | iPad | Trigger |
| --- | --- | --- | --- |
| Smoke | 4 methods | 2 methods | PR, main push, explicit dispatch |
| Full | 71 methods | 62 methods | Nightly at 02:00 UTC, explicit dispatch |
| Diagnostic | 12 methods | — | `diagnostic_only=true` |
| Keyboard | 11 methods | 9 methods | Explicit dispatch |
| Text | 5 methods | 5 methods | Explicit dispatch |

Smoke covers capture, validation, cancellation, durable row editing/completion,
view ordering/capacity and real-server sync on iPhone, plus adaptive navigation
and row editing on iPad. Hardware keyboard, installed Share/widgets/Spotlight,
permissions, notification delivery and other system integrations retain their
full-suite assertions. Green smoke does not certify them. Full coverage on both
families is required before accepting workflow changes, system integrations or
behavior outside smoke. Moving frequency does not establish acceptance.

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
includes ordinary task, filter, attribute, recurrence and automation journeys:

| Family | Workspace | Task/row editing |
| --- | ---: | ---: |
| iPhone | 41 methods | 30 methods |
| iPad | 33 methods | 29 methods |

The partition union is exactly the previous full selection, with no duplicates.
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
requires the real long-press menu, a unique visible enabled native menu item or
button within five seconds, and actual clear/readback assertions; a single app
snapshot supplies admitted geometry without re-querying the disappearing menu.

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
