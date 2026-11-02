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

## Rejected native row menu candidate

The unchanged-source close/reopen probe reproduced a missing New project action
while its admitted point remained inside the native menu cell. The cell and its
content were replaced during the touch; the editor action did not run. App,
window and native-element tap variants did not fix it. A SwiftUI Equatable wrapper
did not prevent menu reconstruction during accessibility work. Replacing Picker
choices with native checked actions also lost New project on its tenth reopen;
that alternative was discarded.

The rejected candidate used a native button whose menu was retained until the
editing owner, UTF8 selection or available options change. Current callbacks are
refreshed separately; old actions reject changed owners/configurations and disabled
controls. Checkmarks, fixed option order, unknown priorities, New project identity,
the existing popover and 44-point hit targets remain. Menu and non-menu pills
shared their appearance modifier. The label used a native content-configuration
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

## Presentation lifecycle diagnostic control

At `11826cb`, canonical smoke passed all four iPhone methods. The iPad passed
its workspace journey but rejected a valid enabled/hittable Select All sample
at 5.045723 seconds, beyond the unchanged five-second budget. The same native
query took about 0.3 seconds earlier in that journey; other reads also slowed
before validation. This remains separate from a missing menu or a proved
provider fault. No same-head retry or full run was spent.

The 60-second first-High animation-idle wait reproduced in canonical iPhone
smoke; it did not reproduce on iPad. The iPhone row journey passed in 431.957
seconds. This confirms that the local stall is not just a local toolchain gap;
functional smoke success does not establish performance acceptance.

The next head is a temporary observation-only control. A valid simulator UI-test
session explicitly enables bounded menu presentation/end callbacks, animator
completion timestamps, window/responder/keyboard observations and aggregate
layout/intrinsic/configuration counters. Public UIKit delegate overrides call
super. The recorder does not add AX queries, wait for a new callback, force an
animation to finish, replace the menu delegate or change input/deadlines. At most
256 event records persist in the existing participant-fixture artifact collection.
It is disabled outside Debug simulator sessions. This diagnostic must be removed
before final acceptance.

Two local controls were aborted before menu admission when the Mac developed
severe load and swap pressure. They provide no lifecycle verdict; owned devices
were shut down/deleted, and a pre-existing device was left alone. Canonical smoke
will provide the controlled phone/iPad comparison. Full dispatch is held until the
known stall is resolved or the UIKit candidate is rolled back. If this control
provides an actionable lifecycle boundary, permit one treatment at that boundary;
otherwise roll the candidate back while preserving independent CI/test fixes and
record the original SwiftUI lost-action problem as unresolved. Rollback itself is
not full-suite acceptance.


### Canonical control result at `7438dc0`

[Smoke 41329009190](https://github.com/Julesseg/tsk/actions/runs/41329009190)
passed all four iPhone and both iPad methods on attempt one. This was the only
workflow run at that head; no full suite was dispatched. Both consumer receipts
identify merge checkout `d47401733e3dd7b7734bb2467e5e69987cfaaf12`, tree
`6afb1631c6fafebd8a4b8dce54562b002f9c8bab`, identical to the head tree.
Products were built with Xcode 27.0 (27A266a), SDK 27.0 (24A430), and executed
on arm64 runtime 27.0 (24A434). The shared producer and both Linux lanes passed.

The control reproduced the blocking iPhone animation-idle warning: first High
tap entry 46.38s, warning 106.44s, synthesis 116.24s. The additional delay after
the warning includes slow accessibility operations; the whole 69.86s is not an
animation timeout. The durable-row method passed in 510.651s on iPhone and
367.653s on iPad. Smoke success does not establish performance acceptance.

Each raw lifecycle artifact contains 78 records from the original row-editing
process, below the 256-record cap. First iPhone presentation completed 85.682s
after `willDisplay`, after its choice action at 84.006s and dismissal. Later
presentations completed before their actions: High in 1.726s, Project in 1.427s
and 1.355s. On iPad the first High presentation completed in 2.742s, before its
action at 7.022s; later completions took 1.420s, 1.337s and 1.368s.

Before first iPhone presentation versus its choice action, button/window/menu/
superview identity and button/label geometry were unchanged. Intrinsic-size
reads stayed at two; layouts increased from one to two; size/frame changes and
menu/label assignments stayed at one. Representable updates rose from 15 to 89,
which alone does not establish sustained layout or configuration churn. No
attachment change was recorded during that interval.

`TaskKeyboardController` remained the observed native first responder on both
families. Keyboard show completion occurred 2.463s after first iPhone
`willDisplay`, versus 2.557s on iPad. The next phone keyboard events were hide
notifications immediately before the choice action. Thus the phone has a late
menu animator completion with stable measured attachment/geometry, while both
families show keyboard lifecycle activity. This does not prove that the keyboard
controller caused the stall or that all other app animation work was idle.
The iPad Select All sequence passed under its original five-second admission
budget; one pass does not resolve the earlier variable accessibility slowdown.

The raw participant artifacts and XCTest logs are retained with this run.
The rollback decision below supersedes the temporary hold. This control does
not establish performance or full-suite acceptance.


### Rollback decision

The control established a late first presentation callback without identifying
an actionable ownership or attachment transition. Both families and later phone
menus retained the same native keyboard-controller responder and keyboard
notification sequence. Making the button first responder would therefore test
a new hypothesis rather than repair an observed ownership change. No responder
or label treatment was applied.

The UIKit menu candidate and temporary lifecycle recorder are removed. Project
and Priority return to their original SwiftUI Menu/Picker implementation, with
the original label style, popover, unfocus gesture and hit targets. The existing
High and No project selected-state/reselection assertions remain, along with
all independent CI, full-suite journey, native-admission and geometry corrections.

This restores the known SwiftUI native-cell replacement/lost-action failure.
That defect remains unresolved; rollback is not a menu fix. New exact-head smoke
and full coverage on both families are required. Full will be dispatched only
when the rollback head passes smoke, with all native postconditions and original
deadlines intact. Source removal alone does not prove that the measured idle
stall is absent or that the full suite is reliable.

Rollback source verification: local generic-simulator `build-for-testing` passed
with Xcode 27.1 beta; all 22 selection/partition regressions passed. The restored
row editor is byte-identical to its pre-candidate `2acb582` version. These checks
did not boot a simulator and do not establish canonical runtime acceptance.

### Remaining native control at `d6c78dd`

[Smoke 41458894620](https://github.com/Julesseg/tsk/actions/runs/41458894620)
finished with iPhone 4/4 and iPad 1/2. The iPad failure occurred before the
rebase push: the selected High option was absent after reopening Priority.
It was a test failure, not a superseded/cancelled result.
[Regression 41458934757](https://github.com/Julesseg/tsk/actions/runs/41458934757)
finished with iPhone 2/5 and iPad 3/6. Every selected method ran exactly once;
Share ran in its installed-extension phase on both families. Both runs' producers,
Linux lanes and source/runtime admission passed. No full run or test retry was
requested at this source.

Smoke products identify PR merge `ed46fde488b512df7dd8b80f5d4115c1473ca460`;
regression products identify head `d6c78dd38012d8dd262e3bb5284420c7758e9ab7`.
Both trees are `9afe2e07d7ee063086a7f6caf690fa6bba008495`, matching the head.
All four workers identify arm64 runtime 27.0 (24A434), Xcode 27.0 (27A266a),
and SDK 27.0 (24A430). Immutable result artifact IDs are 13154451933 and
13155047634 for smoke, 13156477323 and 13156614265 for regression, ordered
by iPhone then iPad. An artifact-transfer HTTP 503 account-egress limit was
retried successfully; that was a read retry, not another test execution.

- Calendar's repaired iPad keyboard journey passed in 111.634s, including its
  native input and persistent reopen assertions. This is runtime evidence at
  this old source, not acceptance of a subsequent rebase.
- View reordering passed on both families in regression (82.227s/90.302s), and
  on iPhone smoke (134.557s). The native drag and persisted ordering assertions
  remain. Finite passes do not establish general reliability.
- Share failed both families before Select All. The first post-focus keyboard
  existence read exhausted the original five-second aggregate budget before
  the preparation callback could run. The phone recording shows the focused
  field and native keyboard education screen with Continue replacing ordinary
  keys. Requiring an ordinary keyboard before dismissing that screen prevents
  preparation. The correction runs the existing known-prompt callback after
  field focus, then requires the keyboard; all preparation, native input,
  dismissal and final reads remain charged to the same five seconds.
- The iPad durable row failed its second admitted New-project option tap at
  48.03s. The same process recorded the first action and expected dismissal,
  but no second action entry, parameter assignment or subsequent nil reset.
  This demotes action-then-reset for that failure. Event-time option ownership
  was not captured, so it does not establish which native delivery boundary
  failed and does not justify a UIKit/responder or presentation workaround.
- Scheduled's original twelve-drag failure was not reached: iPad stopped at
  New project. Passing/earlier scroll samples do not distinguish ancestor
  swipe actions, child menu ownership or content sizing. No scrolling treatment
  was selected.
- iPad typed attributes stopped at Effort before Review. Note has a binding
  update plus observed native valueChanged/up events; passing Score has a
  binding update without those callbacks, exposing incomplete replacement
  coverage. Effort has no setter event, but absence of native callbacks cannot
  establish lost input with that coverage gap. The phone recorded successful
  initial bindings for all five types, then exceeded its ten-minute method
  allowance after relaunch. Neither result proves a binding-reset defect.
- Phone organization stopped earlier at Select All admission, before the
  No-project reopening check. Its failure does not verify or reject that
  specific opener correction.

No behavioral treatment was selected from the inconclusive native controls.
Their raw per-session/PID participant JSON, registration metadata, eviction
counts, XCTest bundles and logs remain in the immutable artifacts above.
Temporary native observers, geometry callbacks, binding logs and launch flags
are removed before the next clean verification source. The concrete 44-point
inner hit area, 26-point capsule and fresh five-second reorder acknowledgement
remain. The next native run checks the Share ordering correction and all affected
journeys; clean exact-head smoke and full on both families still gate acceptance.
