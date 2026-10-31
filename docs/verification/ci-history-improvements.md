# CI history improvements

Baseline: main `5f38f3a`. The [historical audit](../research/ci-history-2026-10-30.md)
contains the frozen run ledger and distinguishes queueing, execution, cancellation,
unchanged-source outcome changes and known infrastructure symptoms.

## Implemented changes

- Family gates poll missing/nonterminal GitHub API results for at most 90 seconds;
  duplicates and terminal failures remain red. A synthetic replay of the old
  checker reproduces the stale-state false red. New tests cover convergence,
  deadline expiry and terminal-failure precedence.
- One shared producer builds signed UI products and selected synchronization
  tools, and validates intent metadata/entitlements before creating simulators.
  Consumers verify checksum, source, SDK/toolchain/runtime and signatures.
- Full coverage remains four execution workers with every previous method once
  per family. Historical successful-median weights balance iPhone at 66/65 minutes
  and iPad at 72/68 before setup. Partitioning alone cannot promise sub-hour full
  execution; improved snapshot/layout behavior must be measured separately.
- Selection determines server, independent peer and native keyboard requirements.
  Task workers and iPad smoke no longer build/start unused fixtures. Core/Native
  Linux builds gain toolchain-specific Swift caches; Rust caches remain.
- Dispatch requires a named suite/reason and checks matching active work.
  Completed evidence reuse additionally requires the exact execution identity.
  Manual runs preserve in-flight evidence rather than cancelling it. Direct form
  requests and simultaneous-client races remain visible operational limits.
- Installable PR builds are explicit requests. Signing admission happens on Linux
  before claiming a Mac. Archives build only the device Rust target, including
  the existing App Store lane. Archive/provisioning acceptance still requires an
  actual requested release; simulator results cannot substitute for it.
- Worker and gate summaries distinguish method durations, first failure, queue
  and runner occupation. A nonblocking owned-device monitor stops execution only
  after a positively observed shutdown; inconclusive probes do not fail tests.

## Targeted instability experiments

Two title/header geometry transforms normalize equivalent heights to display
pixels before SwiftUI compares them. This addresses the previously observed
subpixel feedback mechanism without importing the separate `fixedSize` or
supporting-information changes from the issue #43 branch. Existing geometry,
large-text, completion and durable-edit assertions remain.

Run `41022221277`, iPad job `123952080434`, source `8d38e65a`, captured a native
Select All menu that was visible/enabled even though its accessibility lookup
consumed 5.64 seconds and failed the unchanged five-second deadline. Selection
now finds both supported native control types through one unique control query,
validates enabled/hittable/contained geometry and performs one native tap. Actual clearing
and final value assertions remain; no Command-A fallback or model mutation was
introduced.

Run `40976426566`, iPad job `123805621484`, source `4ad146b7`, recorded a 63.98-second
keyboard snapshot after a full application snapshot had already returned. Keyboard
geometry prefers that same captured hierarchy. Canonical smoke at `44598ec`
showed that some app snapshots omit keyboard descendants; those samples retain
the original owned keyboard query. Missing geometry still fails, and the
20-second deadline and two stable samples remain.

Recent inspected annotations and two Spotlight journeys were passing. Their
ownership protocol, exact native-input assertions and system-delivery checks
remain. A residual Spotlight UUID reveal failure is distinct from indexing and
is unresolved until a current controlled run exercises it; no blind index-wait
increase was made.

## Evidence and acceptance

Local Core: 180 tests passed. Portable routing/selection/shard, build-transfer,
fixture admission, monitor cleanup, native transport and provisioning regressions
passed. Workflow syntax passed actionlint with the repository's custom runner
label declared. The four native-menu geometry host tests passed, including the empty application/visible window regression. Modified Swift files passed syntax parsing. Later focused local simulator probes are recorded below; those runs do not
replace canonical CI. These initial checks establish portable behavior and syntax only.

Canonical evidence must include the actual shared build, smoke gates and full
coverage on both families at the PR head. Record their run links and method/job
measurements after completion. Product-transfer tests use temporary synthetic
products; they do not establish an actual signed iOS runner can launch transferred
bundles. Likewise, source-level release checks do not establish signed archive,
profile or physical-device acceptance.

## First canonical run

[Smoke run 41142040573](https://github.com/Julesseg/tsk/actions/runs/41142040573)
proved shared-product installation and execution on both families. The phone
passed row editing, capture and view ordering, but failed synchronization because
its app snapshot omitted keyboard descendants. The corrected sample retains the
owned keyboard query when captured geometry is absent.

The iPad artifact records `(-1, -1)` as XCTest's computed Projects-tab hit point
after a successful durable task save. That interaction now uses the validated
center coordinates from the same readiness sample. Its original project/task
assertions remain. An independent native picker snapshot timed out with its menu
visible; its deadline remains unchanged and diagnostics retain prior sample state.

The first full run was deliberately cancelled after discovering the keyboard
regression, rather than spending four more worker executions on known-bad code.
The revised head still requires smoke/full canonical results.

## Row query isolation

At `8a6f31a`, the iPad smoke lane passed. The one targeted phone retry made
the earlier row-editing failure pass, but capture failed at the same information
helper after a fresh relaunch, before any row editor had opened. Its selected
control had valid enabled/hittable geometry: the broad label/UUID-pattern snapshot
took 14.8 seconds, then the same query's hittability read took 22.2 seconds. The
application snapshot took 1.7 seconds. This does not support an expanded-editor
layout loop as a common explanation for those two failures.

The next controlled revision resolves the original row once and binds subsequent
readiness checks and the actual native tap to its exact full accessibility
identifier. Task and Upcoming identifiers retain their UUID and appearance context;
malformed identities fail. The same 20-second deadline starts before broad-row
resolution and is forwarded to readiness, so preparation cannot hide outside the
budget. Hittability, containment and actual information/editor assertions remain.
36 readiness/menu/row-identity host tests passed. Runtime benefit still requires
the next canonical smoke result; no further same-source retry was requested.

## Full-suite findings at 2acb582

[Smoke run 41149065954](https://github.com/Julesseg/tsk/actions/runs/41149065954)
passed both families after one targeted phone retry. The exact-row identity
reads took about 0.12 seconds on iPhone and 0.15–0.22 seconds on iPad. This
establishes those executions, rather than a guarantee for every later query.

[Full run 41153213953](https://github.com/Julesseg/tsk/actions/runs/41153213953)
failed: 99 methods passed, 31 failed and three iPad-only methods were skipped on
iPhone. Its shared build passed in 5m30s. Four workers occupied roughly 4.68 Mac
hours; the complete run took 83m01s including queueing. No successful full-suite
speedup is established. The artifacts identify source `2acb58296d9468de5a9291d01802ceb00c2b3ba4`,
tree `f90cb501836f2285207a5c39252337a09f5f3770`, Xcode 27.0 (27A266a),
SDK 27.0 (24A430), arm64 and runtime 27.0 (24A434).

The follow-up changes address observed boundaries without removing selected
methods or widening acknowledgement/admission deadlines:

- Calendar journeys require the current Today title and task list, retain absence
  of the removed section heading, and reach information through the expanded row.
- Compact-row assertions require the current Deadline wording and Scheduled clock
  time while retaining status exclusions, full identities and durable completion.
- Completion waits observe disappearance rather than requiring absence at the
  instant an existence wait first samples the still-visible feedback row.
- Scheduled picker reveals account for the actual keyboard toolbar inset. The
  failing drag had dismissed the sheet before reaching its date control.
- Save acknowledgement captures editor absence and a unique, full-UUID saved row
  in one application snapshot. The affected synchronization journey first admits
  keyboard dismissal and the actual Save control.
- Native Select All admission queries its unique control rather than traversing
  the entire app on every sample. It retains the five-second budget, enabled and
  hittable checks, visible containment, one native touch and actual value readback.
- Date switches bind the native child to the observed accessibility element once.
  The failing anonymous descendant query had blocked for 94.6 seconds. Binding,
  diagnostics and readiness share the original 20-second budget; native thumb
  targeting, hittability and the five-second outer-switch acknowledgement remain.
- Notification fixtures save expected requests, actual native pending requests,
  decoded payloads, trigger dates, content agreement, preferences and the last
  registration report before the unchanged failing guards. These are diagnostic
  additions; they do not establish a registration fix.

A separately dispatched failed full run must block acceptance even when the PR's
smoke rollup remains green. Audit every CI run at the exact head, including its
execution manifest and both families' complete selections, before reporting
verification.

## Retained native row menu candidate

The unchanged-source close/reopen probe reproduced a missing New project action
while its admitted point remained inside the native menu cell. The cell and its
content were replaced during the touch; the editor action did not run. App,
window and native-element tap variants did not fix it. A SwiftUI Equatable wrapper
did not prevent menu reconstruction during accessibility work. Replacing Picker
choices with native checked actions also lost New project on its tenth reopen;
that alternative was discarded.

Project and Priority now use a native button whose menu is retained until the
editing owner, UTF8 selection or available options change. Current callbacks are
refreshed separately; old actions reject changed owners/configurations and disabled
controls. Checkmarks, fixed option order, unknown priorities, New project identity,
the existing popover and 44-point hit targets remain. Menu and non-menu pills
share their appearance modifier. The label uses a native content-configuration
view with matching erased view types, rather than an unattached hosting controller.

The first local retained-menu build passed 20 New project close/reopen cycles.
Its compact-label revision passed the full iPhone durable-edit journey (252.676s)
and installed Share journey (206.137s). The native content-view revision passed
High plus three New project opens. These are local treatment evidence, not
canonical acceptance or quantified flake-rate improvement.

**Known performance risk:** the retained-menu local builds incur one approximately
60-second XCTest animation-idle timeout before the first High selection. Changing
label hosting, pressed-opacity animation and a no-op focus assignment did not
remove it; the latter two changes were reverted. The focus receipt was false
before and after the callback. The delay is not repaired by widening an admission
budget or disabling XCTest idle checks. Canonical Xcode 27.0 must establish this
candidate's behavior and cost before acceptance; local probes use Xcode 27.1 beta
against runtime 27.0. A passing smoke/full conclusion alone must not be described
as a measured performance improvement. Probe methods and instrumentation are
excluded from the branch. Existing durable journeys now check that reselecting
High and No project preserves their native selected state and saved value.
