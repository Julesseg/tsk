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

### Focus-gesture candidate after `01a0681`

The user renewed the instruction to continue until all failures are fixed. The
next app candidate changes one interaction rule: the Menu's simultaneous
unfocus tap gesture is enabled only while the row's title or note has text focus.
The callback remains active while it has focus to dismiss. Native Menu/Picker,
selection/reselection, popover presentation, styling and existing test inputs and
deadlines remain. This does not revive the rejected UIKit bridge or change
responder ownership.

The ranked explanations remain (1) redundant gesture competition during native
menu selection, (2) action/view replacement caused by another SwiftUI update,
and (3) another native presentation/touch-routing boundary. The candidate tests
only the first. Apple's public
[simultaneous gesture API](https://developer.apple.com/documentation/swiftui/view/simultaneousgesture(_:isenabled:))
permits disabling the added gesture; this documents the mechanism being changed,
not the cause of the observed failure. A failed native action rejects this
candidate before another behavior treatment is applied.

The new native regression retains the original High selected/reselected prefix,
then opens and dismisses New project twenty times in one process. Every cycle
requires its real input field within five seconds, its disappearance within five
seconds, and unchanged Release selection. The final cycle first focuses the
row title and requires keyboard dismissal after opening the menu. It neither
replays touches nor changes the existing durable method's two-opening assertions.
Full coverage now contains 75 iPhone/66 iPad methods; all previous methods remain.
The focused menu dispatch selects this case alone on both families without
server, peer, HID or installed-extension fixtures. Regression also includes it;
smoke remains 4/2. A passing focused run still cannot establish full acceptance.

An owned local simulator attempt used checksum/signature-verified CI products
from `01a0681`, runtime 27.0 and the local Xcode27.1-beta driver. Boot/migration
raised host load from14.88 to331.59. The attempt was interrupted for host health;
its device was shut down/deleted and no simulator remained booted. This supplies
no valid control verdict or native acceptance evidence. Generic builds do not
boot a simulator; canonical CI supplies the runtime verdicts.


### Focus-gesture candidate rejected at `890a4db`

[Focused menu run41498951963](https://github.com/Julesseg/tsk/actions/runs/41498951963)
rejected the candidate on iPad. The exact-head producer identifies tree
`657f8bbc49730a4d25e57835aa3ac153cfd8fb51`, Xcode27.0/27A266a,
SDK27.0/24A430 and arm64 runtime27.0/24A434. The consumer manifest selects
only the new twenty-cycle method, which failed at line322 in183.625s.

High selection/reselection and six New-project open/close cycles succeeded.
Cycle seven admitted the native option and requested its center at(172,262):
tap entry162.39s, synthesis163.43s. The input field remained absent through
171.73s after the original five-second wait began at165.69s. This is an absent
field failure, not rejection solely for a late elapsed-time sample. The
remaining cycles and final focused-title dismissal were not exercised. The
recording retains the native menu at the failure; it does not identify the
actual event recipient or prove a responder, animation or system-service cause.

The active-focus condition and its extra property are reverted before any
further behavior treatment. The App editor is byte-identical to its `01a0681`
version; the twenty-cycle regression and focused routing remain. Six passing
cycles cannot establish reliability or credit the rejected candidate as a fix.
No unchanged-head test retry or full run was dispatched. Other current-head
workers are audited separately as they finish; this record is not acceptance.

The iPhone consumer also failed this method at line322 in240.286s. High
selection/reselection and fifteen open/close cycles passed; cycle sixteen
requested(185,308), tap entry224.26s and synthesis224.71s, then the field
remained absent through231.07s. Neither family reached the final focused-title
cycle. Both manifests retain source `890a4db` and arm64 runtime27.0/24A434.
The producer source tree matches Git. The generic simulator test build passes
with the candidate removed; no local UI runtime verdict is claimed.


### Native touch-delivery control after the gesture rollback

[Smoke41498940040](https://github.com/Julesseg/tsk/actions/runs/41498940040)
finished with iPhone4/4 and iPad1/2. The iPad durable method again failed its
second New-project field check at line197 in75.457s; workspace navigation passed
in86.210s. Phone synchronization, durable row, capture and reorder passed in
77.891s/214.824s/36.556s/88.645s. Both consumers identify merge `f280ce6`, whose
parent includes `890a4db` and whose tree matches it, with the same canonical
Xcode/SDK/runtime as the menu run. Neither worker logged an animation-completion
warning. These finite passes do not repair the separately reproduced menu drop.
Only smoke and focused menu ran at this head; both workflows failed.

The next control keeps the reverted `TaskRowEditor.swift` unchanged. A temporary
observer exchanges the public `UIApplication.sendEvent` implementation only in
Debug simulator builds when isolated-simulator admission, replica UUID, matching
diagnostic opt-in and session UUID are present. Only the retained menu regression
opts in. The wrapper reads actual incoming touch view/window/phase/timestamps,
bounded native ancestor identities/attachment/geometry and existing associated
recognizer state before and after forwarding the original event exactly once.
It installs no recognizer or target, changes no delegate/gesture flags, calls no
hit test, and invokes no action or focus behavior.

Parameter old/new writes and expanded-owner identity are recorded at existing
`TaskRowEditing` seams. The trace retains scalar values in a512-record ring,
with an eviction count. One export can be in flight; changed evidence is
coalesced into the latest follow-up. Encoding and atomic writing run on a serial
background queue after input dispatch. The existing artifact collector preserves
`participant-fixture-pr77-touch-<session>-<pid>.json` without changing collection.
No view, touch, recognizer or editing object is retained by the recorder.

The unchanged focused test must capture preceding successful option touches and
the first failed selection on each family. Actual recipient/phase/attachment
plus parameter writes partition delivery, routing/cancellation, native action
and presentation failures; a touch recipient alone does not prove consumption.
Missing receipts or a pass-only run are inconclusive. The observed scrollbar AX
rectangle overlaps the failed iPad point, but this does not establish hit-test
ownership or justify moving the tap. Neither coordinates nor deadlines change.
The original High selected/reselected checks, all20 cycles and focused-title
cycle20 remain. No unchanged-source retry or full is requested. Remove this
observer and launch opt-in before clean exact-head smoke/full acceptance.

The generic simulator test build passes. Standards and Spec reviews cleared the
export backlog correction; no native runtime result is claimed for this control.
No local simulator was booted.


### Build-admission interruption at `60262af`

[Focused menu41509968846](https://github.com/Julesseg/tsk/actions/runs/41509968846)
ran no UI tests. Producer125499304156 compiled successfully, then the strict
verifier rejected the absent `Tsk.app/Metadata.appintents/extract.actionsdata`.
The extractor reported no AppIntents.framework dependency. Packaging and both
UI workers were skipped; there are no native touch receipts to classify and no
menu correctness/performance verdict. The separately requested smoke producer
125498761894 on the same head wrote metadata and passed admission. Its native
workers remain independently audited. Neither an unchanged-source test retry
nor a full run is requested.

Both producer linker logs show a Debug executor whose entry point loads
`Tsk.debug.dylib`; extraction names the executor as its binary input. Local
Mach-O inspection confirms that the executor depends on that dylib and libSystem,
while the dylib contains the AppIntents dependency. The passing producer uses
the same layout. Therefore Debug-stub dependency detection, dependency-file
ordering and extractor nondeterminism remain ranked hypotheses, not a proven
GitHub-infrastructure or source-code cause.

The bounded build candidate tests the first hypothesis by making the Tsk Debug
executable direct in CI. Only that target's `ENABLE_DEBUG_DYLIB` reads a custom
`TSK_APP_DEBUG_DYLIB` setting, whose default remains `YES`; the producer supplies
`NO`. Other targets and developer Preview defaults remain unchanged. This uses
Apple's documented [per-target Debug layout override](https://developer.apple.com/documentation/xcode/understanding-build-product-layout-changes).
No native menu, observer, test input, geometry, assertion or deadline changes.
If canonical extraction still fails with a direct AppIntents-dependent main
binary, that result rejects this layout explanation before another build
behavior treatment. A successful extraction is admission evidence, not proof
that layout caused the prior intermittent failure or that the native menu works.

The metadata/entitlement gate remains strict and precedes packaging. After a
successful compile but rejected admission, a separate seven-day
`ui-build-admission-diagnostics` artifact retains the rejected app and extraction
dependency inputs. Hidden `.build` files are included and an empty upload fails;
this artifact is never named or admitted as `ui-products`. This preserves the
next red build for inspection without retrying extraction or fabricating output.
Local build-setting queries confirm Tsk resolves `NO` under the CI override and
`YES` by default. Ten execution and twelve routing checks pass; fresh generic
build and real artifact-verifier results are recorded with this candidate.

The fresh-derived-data generic test build passed with Xcode27.1 beta and the CI
override. Its main executable directly links AppIntents, contains no separate
`Tsk.debug.dylib`, and passes the unchanged real metadata/App Group verifier,
including all four App Shortcuts and embedded Share/Widget checks. This local
result validates the candidate's layout and artifact contents, not the canonical
Xcode27.0 outcome or native UI reliability. Standards and Spec reviews cleared
the hidden-artifact inclusion correction. No simulator was booted locally.


### Recorder startup correction after `42d1041`

The direct-layout candidate passed canonical metadata/entitlement admission in
both smoke41512468845 and focused menu41512549122 producers. The focused product
identifies head `42d1041a4a7cc85b63b23c426e104bc471d484fb`, tree
`0118c3578c12a25d426e8f2c2fa29f09358b2c7f`, Xcode27.0/27A266a,
SDK27.0/24A430 and arm64 runtime27.0/24A434. Consumer identities/runtime match.
This is admission evidence, not proof of a metadata root cause or UI acceptance.

Both focused methods failed during recorder startup: iPad71.022s and phone45.136s.
No High/reselection or New-project cycle ran, and no touch receipt was exported.
The iPad crash shows `swift_getObjectType` with null x0, called by
`TaskNativeTouchDiagnostics.installIfRequested` from `TskApp.init`; x17 identifies
`+[UIApplication sharedApplication]`. The observer attempted `type(of:
UIApplication.shared)` before UIKit had created the application. This is an
instrumentation bug introduced here, not evidence of native menu failure or
missing touch delivery. First-red logs, result bundles and the crash are retained.

Installation now runs from the existing app-delegate
`application(_:didFinishLaunchingWithOptions:)` callback, using its nonoptional
application argument for the class receipt. The SwiftUI app initializer no
longer accesses the recorder. Isolation/UUID gates, idempotence, original-event
forwarding, buffering/export and native test contracts remain unchanged. The
App editor remains byte-identical to `01a0681`; no native behavior treatment is
stacked onto this correction. Generic direct-layout test build and the unchanged
real metadata/entitlement verifier pass; both review axes are clear. No local
simulator was booted. Native recording coverage remains unverified, and the
observer must still be removed before clean exact-head smoke/full acceptance.

### Valid touch control and project presentation ownership candidate

At `7e6ec5fa80fa91a0dac6975dd9549cbf1bef6419`, smoke41515274355 passed
all four phone and two iPad methods. Its PR merge source `3188492e` has the
same tree `73923571dcb5a5ff9d3a0598cc5493b5826b2882` as the head. Focused
menu41515362524 failed both families with different boundaries. Both products
and consumers match Xcode27.0/27A266a, SDK27.0/24A430 and arm64
runtime27.0/24A434. All head workflows are accounted for; no full or retry ran.
No matching-snapshot or animation-completion warning appears in these logs.

Phone PID11384 exported 48 records with zero evictions. Cycle1's actual
New-project touch remained in its option-cell ancestry through before-ended
dispatch, then wrote project on the active expanded editing owner. Its nil
touch view after successful dispatch is normal. Cycle2 began on the same native
option and point, but the same touch reported the menu container before ended
dispatch, with no project write. The method failed at field appearance, line322,
after 86.457s. This locates the captured defect before parameter assignment;
it does not prove cell removal, control consumption or a particular recognizer
as the cause. Private class names identify observations only.

iPad PID9331 exported 300 records, zero evictions and 38 parameter writes.
Nineteen complete New-project/Release/Done cycles passed. At cycle20 the focused
title remained first responder after the project opener, and the original
five-second keyboard-nonexistence assertion failed at line316, after 355.038s.
No cycle20 option tap occurred. This is a separate baseline focus blocker,
not evidence of an option drop. High selection/reselection passed on both
families. Missing later keyboard diagnostics do not establish absence of host
replacement because those receipts deduplicate host class names.

The next single treatment separates only the project popover presenter from
its native Menu source. An always-present passive background anchor owns the
project popover binding and parameter observation. The native Menu retains its
Picker, option order, UTF8 selection, New-project action, label, gesture and
44-point hit region. The visible source retains the same namespace and matched
transition source; the sibling presenter retains the original zoom, 340-point
content, bounds anchor, top arrow and compact adaptation. Nonproject controls
keep their existing path. No focus repair is combined with this experiment.
The generic direct-layout test build and strict artifact verifier pass, and
Standards and Spec reviews found no actionable source defects. This does not
establish runtime effectiveness or presented-content interaction.

Retain the existing temporary observer for one treatment execution on each
family with unchanged input, geometry, twenty cycles, High/reselection and
deadlines. Any repeated option drop rejects this candidate; revert it before
another ownership treatment. A repeat of the baseline iPad cycle20 focus
failure after nineteen completed cycles remains a separate blocker and provides
no cycle20 option coverage. Phone twenty-cycle success would be bounded positive
evidence, not proof of reliability; nineteen passing iPad cycles alone would
not distinguish treatment from control. Address focus separately after this
experiment. Remove the temporary observer before clean exact-head smoke and
full acceptance on both families. Share and Scheduled coverage gaps also remain.

### Presenter separation rejected at `1bb2f98`

Focused menu41520217565 reproduced the target defect on iPad cycle3, after two
complete New-project/Release/Done cycles. The method failed at line322 after
90.524s. Producer and consumer identify head `1bb2f984f2766e512be57806d1f09ae01228f221`,
tree `cc8338594475db8cb6f949414c402e107b05cbe7` and the same canonical
Xcode27.0/SDK24A430/runtime24A434 identity. PID5673 exported 62 records with
zero evictions. Successful cycles wrote project on the active expanded owner
and cleared it through Done. Failed cycle3 began inside `row-new-project` at
the admitted native center `(172,262)`; before ended dispatch the same touch
reported the menu container instead, with no project write. The first hit
was correct; no post-assignment reset explains this captured failure.

This recurrence rejects the project-only presenter separation as a sufficient
repair. Restore the original presentation path before selecting another seam;
do not combine it with another ownership, focus or gesture treatment. The
failure preceded cycle20, so it provides no new focused-title keyboard result.
Other family/workflow outcomes are audited separately as they finish. No
unchanged-source test retry or full suite is justified by this result.

The completed phone focused case failed after 225.123s at line324 on cycle12.
Eleven complete cycles passed; the twelfth option retained its native target
through before-ended dispatch and wrote project on the active owner. The field
and its Release value were observed, but the aggregate appearance/value read
crossed the unchanged five-second deadline. This is a separate read-budget
failure, not a missing twelfth action. Its trace has 189 records, 23 parameter
writes and zero evictions. Neither family reached the final focused cycle.

Smoke41520200036 also failed: phone2/4 and iPad1/2. The phone's first and iPad's
second New-project field did not appear. The phone reorder failed with a fresh
snapshot showing the custom view still below Today. The app's actual
`workspace.views.move` receipt moved index2 to4, taking Projects below the custom
view instead of moving the custom view first. Thus the fresh-snapshot correction
exposed an actual wrong-order result; a stale retained-cell acknowledgement is
not sufficient to explain this failure. Input target versus reorder callback
mapping remains to be diagnosed separately. Sync, capture and adaptive-navigation
methods passed. Both smoke consumers identify PR merge source `003e4bae`, whose
tree exactly matches head `1bb2f98`; all four workers match canonical runtime.
All two head workflows are terminal and retained. No full or retry was dispatched.

### Project-only matched zoom elimination experiment

After reverting presenter separation in `d8ba8c8`, omit the project pill's
matched transition source and its matching popover zoom destination together.
Both modifiers remain for every other fixed parameter kind, with the existing
namespace. The original project popover stays on its original owner with the
same binding, guarded reset, bounds anchor, arrow, width and compact adaptation.
Menu/Picker content, selected state, labels, actual input, unfocus gesture,
44-point hit region, glass/scroll ancestors and every deadline remain unchanged.
No focus correction or second behavior treatment is stacked.

This tests whether explicit project transition registration contributes to the
pre-action routing failure; neither the prior control nor detached-presenter
candidate removed that registration. It does not establish a private recognizer
cause, cell removal or an active animation during the failed touch. Both source
review axes found no actionable defects. Keep the same bounded observer for one
exact-head treatment on both families and compare began/before-ended/action
receipts with successful selections in that execution. A repeated missing action
rejects this treatment; revert it before another seam. Preserve all existing
timing assertions and classify any late read separately from absent action.

This diagnostic intentionally substitutes the system's ordinary anchored popover
transition for the project's explicit zoom. It does not satisfy the design
audit's source-pill morph requirement by source inspection alone. Inspect actual
opening/closing video and geometry; a functional pass is only bounded evidence
for transition involvement. Final appearance compliance, the baseline focused
keyboard blocker and clean exact-head smoke/full on both families remain
required. Do not silently waive the morph requirement or launch full coverage
while known controls remain red; remove the temporary observer before acceptance.

The generic arm64 test build and unchanged real App/Share/Widget entitlement and
four-App-Shortcut verifier pass with Xcode27.1 beta. The first local invocation
omitted the arm64 restriction and failed linking the unsupported Intel slice
against the arm64-only Native artifact; the corrected build uses `ARCHS=arm64`
as canonical CI does. This is build evidence only; no simulator was booted.

### Matched zoom elimination rejected at `c0eac67`

Focused menu41523293565 reproduced the native action defect on phone cycle8
after seven complete New-project/Release/Done cycles. The case failed at line322
after 162.209s. Its producer identifies head `c0eac67c386ea5013191fd33a372d2452f3d97a8`,
tree `ec2109785dfc5ea1aeade76263af8bc27fc4d4e3`, Xcode27.0/27A266a,
SDK24A430 and arm64 runtime24A434; consumer source and runtime match.
PID11012 exported 132 records and 14 parameter writes with zero evictions.
Cycle8 began inside the real `row-new-project` cell at `(185,308)`, then the
same touch reported the menu container before ended dispatch, with no project
write. High selection/reselection passed; focused cycle20 was not reached.

This rejects project matched-source/zoom omission as a sufficient repair of
the captured failure. Restore both original transition modifiers before any
next treatment, thereby also restoring the required project motion. The result
does not prove all transition machinery innocent or identify cell removal,
private recognizer behavior or control consumption. Remaining family/smoke
outcomes are retained and audited independently. No unchanged-source retry or
full dispatch follows this red diagnostic.

The completed iPad case failed at line322 after 352.997s on cycle16, after
fifteen complete New-project/Release/Done cycles. PID18978 exported 240 records,
30 parameter writes and zero evictions, but its final records cover the cycle16
opener only. XCTest reports the option synthesis at321.05s; there is no matching
captured option touch or assignment. This does not establish the same retarget
mechanism on iPad or prove missing UIKit delivery: the unmatched input/export
boundary remains unresolved. Both families passed High selection/reselection;
neither reached focused cycle20. Video samples show the successful ordinary
anchored picker and the still-visible native menu around failure, with the
keyboard visible. They do not resolve the short touch interval or establish
keyboard causality. No animation-completion warning appears in these logs.

Smoke41523270337 passed phone4/4, including the reorder that previously failed,
and failed iPad1/2. The iPad durable journey executed native project/tag editing,
Scheduled reveal/calendar selection, validation and relaunch persistence, then
failed the original five-second stable completion-circle geometry admission
after expanding the plain row, at line549. Accessibility reads were slow; no
specific ownership or geometry cause is established. Adaptive navigation passed.
These executions add Scheduled coverage on this diagnostic head but do not
resolve its historical intermittency on a clean candidate. The smoke product
uses PR merge source `1b384cde`, whose tree matches `c0eac67`. All four workers
match canonical source/tree/runtime. Exactly two head workflows are terminal;
no full or retry ran. The zoom omission is reverted in `42e847f`.

### Observe actual keyboard-command registration

With the original row editor, popover, zoom and glass structure restored, add
one observation seam at actual `TaskKeyboardRouter.applyRegistration` entry.
The existing opt-in bounded touch recorder receives router/apply ordinal,
effective scope, scope-to-controller identities, previous installed weak-host
liveness, current unique hosts and complete old/new declaration signatures.
Nil and empty titles remain distinct. Linked before/after records bracket only
the existing main-menu rebuild request; touch records carry cumulative apply
and request ordinals. No ordinary refresh polling, responder capture, hierarchy
scan, extra UIKit hook or forced synchronous diagnostic is introduced.

Apple distinguishes the [main and context menu systems](https://developer.apple.com/documentation/uikit/uimenusystem).
The app calls `.main.setNeedsRebuild()`. A request timestamp is neither a
context-menu rebuild nor UIKit completion. Reconciliation, key removal/addition,
scope resolution, focus, gestures and the original request order remain intact.
This control measures native mutations hidden by the older diagnostic's
class-name deduplication; it does not assume that such mutations cause the drop.

Use one canonical focused run on each family with the original native input,
twenty cycles, High/reselection, focused cycle20 and deadlines. Require matching
session/PID, startup apply coverage, complete request brackets, cumulative
ordinals and no relevant eviction before interpreting an absent registration.
A valid failed option with no apply from the previous Done through selection
demotes contemporaneous app registration; do not retain an unbounded theory
about an old main request. Temporal host/declaration churn selects a boundary
for further investigation, not permission to disable commands or menu rebuilds.
Only passes, unrelated focus/read-budget failures or missing trace coverage
remain inconclusive. Do not combine this control with glass removal or another
behavior change, and do not retry unchanged source or dispatch full on known red.

The generic arm64 test build and strict metadata/entitlement/App Shortcut
verifier pass with Xcode27.1 beta. Both source review axes found no actionable
defects. No local simulator was booted. Remove all temporary observation before
clean exact-head smoke/full acceptance on both families.

### Registration control result and outer-container candidate

At `1fb284434892fd662a59259c66f41253c70b48f2`, focused41527821188 reproduced
the iPad native option failure on cycle10 after nine complete cycles, at line322
after 202.339s. PID12066 exported 175 records, 18 parameter writes and zero
evictions. Startup applies1–5 have complete linked main-request brackets.
The last apply is at receipt uptime798.273; the failed option ends at941.810.
The same touch starts in `row-new-project`, reports the menu container before
ended dispatch and produces no project write. Apply/request ordinals remain5/5
through the preceding Done, opener and failed selection. No new apply occurred
for143.537s. This valid negative control demotes contemporaneous app registration
as the explanation for this failure. Do not disable keyboard commands or retain
an unbounded theory about an old main-menu request.

Phone native assertions completed fourteen cycles before cycle15 field failure,
at line322 after 417.377s. Its PID5974 trace has 223 records, 26 writes and zero
evictions, but stops after cycle13 Done at21:36:32, before a later passing cycle14.
Thus it lacks late observer/export coverage; it cannot establish the failed
phone touch route or absence of later registration. Zero evictions alone is
insufficient. Both families passed High/reselection and neither reached focus20.

Smoke41527798547 passed phone4/4 and failed iPad1/2: its first New-project field
was absent at line191 after 172.625s; adaptive navigation passed. The smoke merge
source `8253012e` has the same tree as the head. All four consumers match exact
product source/tree, Xcode27.0/27A266a, SDK24A430 and arm64 runtime24A434.
Exactly two head workflows ran, both terminal failure. No full or retry ran.

The next single treatment removes only the outer `GlassEffectContainer` around
the existing parameter HStack. Keep spacing6, horizontal padding4, child order,
both scroll views, capsule/hit geometry, focus callbacks, native Menu/Picker,
popover and both zoom modifiers unchanged. Keep the same diagnostic observer
for one treatment execution; no keyboard behavior or observer change is stacked.
This follows the preselected negative-control branch and tests an ancestor
participation hypothesis, not a proven glass cause. No explicit glass-effect
modifier was found on these pills; that does not establish container inertness.

Require the same native twenty-cycle/High/reselection/focus journey, geometry,
values, Done behavior and original budgets on both families. Recurring native
option loss rejects this treatment and requires reverting it before another
seam. Known focus/read-budget failures retain their own coverage boundaries.
Inspect actual layout, capsule/group appearance, anchors and opening/closing
motion; source equivalence does not establish visual compliance. Functional
success is bounded evidence, not cause proof or clean acceptance. The generic
arm64 test build and strict artifact verifier pass, both source review axes are
clear, and no local simulator was booted. Remove all temporary observation before
clean exact-head smoke and full acceptance on both families.

### Outer glass-container elimination rejected at `868b153`

Focused menu41531638666 reproduced the phone action failure on cycle7 after six
complete New-project/Release/Done cycles, at line322 after 115.893s. Product and
consumer identify head `868b15381baf5c14707df778b3a3f4c8e693e5a5`, tree
`7afa59667ea2e389d022753269d86ea85e575761` and canonical
Xcode27.0/27A266a, SDK24A430, arm64 runtime24A434. PID2774 exported 133 records,
12 parameter writes and zero evictions. Cycle7 begins in the actual option
cell at `(185,308)`; before ended dispatch it reports the menu container, with
no project write. Apply/main-request ordinals remain5/5 throughout the preceding
Done, opener and failed touch. No fresh registration explains this failure.

This recurrence rejects removal of the outer glass container as sufficient
repair. Restore the original container before another seam. High selection and
reselection passed, and focused cycle20 was not reached. The failure still does
not establish that the original cell detached, was deallocated or lost ownership
through a particular recognizer. Remaining iPad/smoke outcomes are audited as
they finish. No unchanged-source retry or full is dispatched for this result.

The iPad also reproduced the action defect, on cycle2 after one complete cycle,
at line322 after 83.476s. PID44017 exported 63 records and two parameter writes,
with zero evictions. Its actual option touch likewise retargeted before ended
with no write; apply/main-request ordinals stayed5/5. Neither family reached
focused cycle20. Actual video samples retain the native option menu and the
successful Project/Release/Done popover; they provide no final appearance credit
for this rejected candidate or resolution of the short touch interval.

Smoke41531541490 passed all four phone and two iPad methods. Its PR merge source
`bcb39f07` has the head tree. Both products and all four consumers match exact
source/tree and canonical Xcode/SDK/runtime. Exactly two head workflows ran;
no full or retry ran. Green smoke does not rescue the failed repeated-menu
candidate. The original container is restored in `01c84f3`.

### Observe original native-view lifetime

Extend only the existing opt-in sendEvent trace while the complete original row
editor, glass, popover, zoom and gesture implementation remains restored. At the
first before-began receipt, keep weak boxes for the original leaf, public
`row-new-project` content, nearest public UICollectionViewCell/UICollectionView
and original window, with scalar capture sequence/generation/IDs/frames and
index path. Keep at most four active touch identities and four prior UIControl
breadcrumbs. Breadcrumbs are unverified source candidates associated offline
through their original sequence and native opener point, not guessed from
private class names or an absent native accessibility identifier.

Resample those same original weak references at began and terminal boundaries
on both sides of dispatch. Record liveness, attachment, window-relative geometry,
visibility, current public identifier, bounded ancestry and public original-cell
index/slot association. A nil cell returned for a slot is not deallocation.
Unavailable public class matches remain unavailable. Export only strings and
values; temporary strong view arrays die before original dispatch. Clear active
entries after terminal dispatch and expose dropped/truncated capture flags.
No extra weak-origin work runs during moved events. There is no new global hook,
recognizer, hitTest, AX read, forced layout, input variant or synchronous I/O.

One exact-head canonical focused observation on both families keeps all twenty
cycles, High/reselection, focused cycle20 and deadlines. Require an actual
original capture, matching generation/sequence across phases, pre-ended samples,
adjacent successful controls and complete late export coverage. Original view
loss/detachment/replacement before a failed action selects a lifetime boundary,
not its cause. Intact original objects at failed pre-ended dispatch demote
persistent destruction/reparenting and point toward routing/arbitration;
they do not prove gesture consumption or exclude a transient change between
samples. After-ended loss following a successful write is normal. Green-only,
nondiscriminating lifetime changes, missing roles/drop/eviction or stale export
remain inconclusive and do not authorize another identical retry or guessed
ancestor removal.

The corrected generic arm64 test build and strict artifact verifier pass with
Xcode27.1 beta. An initial compiler expression limit was fixed by splitting the
diagnostic sample dictionary. Standards review also caught moved-event sampling;
that work is now restricted to the planned boundaries, and both review axes
are clear. No simulator was booted locally. This remains diagnostic-only; remove
all temporary observers before clean exact-head smoke/full/design acceptance.

### Weak-origin result and project gesture-composition experiment

At `3cbc079e3e499283cf52691cf270c009e915ca3e`, focused41536761171 captured
a complete phone failure on cycle18 after seventeen complete cycles, at line322
after 296.334s. PID30410 exported 287 records, 34 parameter writes and zero
evictions, drops or relevant touch truncation. Capture284/after285 retain the
original option recipient. Before-ended286 reports the menu container with no
assignment; the original leaf/content/cell/collection remain alive, attached,
in their original frames, and the original collection slot still returns the
same cell at `[1,0]`. The preceding opener control280 matches the captured
candidate at `(100,194)` and retains its direct attachment and frame.

Crucial correction: this is not fully unchanged visibility. The original
collection's model alpha is1 at284/285 and0 at286/287, while its child views'
own alpha remains1. All seventeen successful pre-ended selections have
collection alpha1 and deliver the project write. The first audit summary
incorrectly called the entire original subtree visible; it checked attachment
and hidden/enabled state but missed the ancestor alpha. This corrected public
property observation demotes persistent destructive replacement and establishes
a pre-action opacity/routing discriminator. It does not measure presentation-
layer opacity, establish the ordering of fade versus retarget between samples,
prove rendered pixels disappeared, or identify a consuming gesture.

iPad PID7176 exported 315 records and 38 parameter writes with zero evictions.
Nineteen complete native selections passed, then the original focused-cycle20
keyboard-nonexistence assertion failed at line316 after 328.423s, before option20.
High selection/reselection passed on both families. Registration/request ordinals
remain5/5. Product and consumers identify the exact head/tree, Xcode27.0/27A266a,
SDK24A430 and arm64 runtime24A434. Smoke41536609400 passed all four phone and
two iPad methods; its merge source has the identical head tree. All four workers
are accounted for. Exactly two head workflows ran, with focused failure and
smoke success; no full or retry ran.

The next single treatment structurally omits the extra simultaneous TapGesture
from the fixed Project Menu branch only. Priority retains the original gesture.
This is different from the rejected `890a4db` enabled-condition experiment,
which still invoked the gesture modifier; neither source proves native
recognizer topology. Keep Menu/Picker/options/bindings, styling/hit region,
popover host/anchor/zoom, namespace, glass, scrolling and observer unchanged.
`openPicker` still unfocuses before assigning project after actual selection.
No alternate gesture, new focus mechanism, responder operation or input variant
is combined with this experiment.

Use one exact-head focused treatment on each family. A recurring attempted
native option drop rejects omission and requires reverting it before another
seam. Track collection alpha, routing and action separately; alpha0 with a
successful action would change the proposed mechanism, not fail correctness.
Every existing admission, value/Done and timing assertion remains. The project
opener's unfocus callback is intentionally absent in this diagnostic, so keep
focused-cycle20's keyboard prerequisite asserted before option selection.
If ordinary selections pass but only that prerequisite fails, record nineteen
attempted passes and no option20 result; provisional retention is experimental,
not proof of repair. The phone control never reached focus20, so do not relabel
a newly exposed phone focus failure as proven baseline behavior. Final repair
still requires opener dismissal before native option selection using an
evidence-selected public mechanism, followed by the complete native journey.

The generic arm64 test build and unchanged strict artifact verifier pass with
Xcode27.1 beta, and both source review axes found no unintended defects. No
local simulator was booted. The expected opener-focus deficit is explicitly
diagnostic and remains an acceptance blocker until the full native focus journey
passes. Keep observers only through controlled diagnosis, then verify clean
exact-head smoke/full on both families before final acceptance.

### Structural Project gesture omission rejected

At `8d627bc4a73076003a4e75d9654a5bacb1f64ac2`, focused41540993369
failed on both families. The phone completed five native New-project/Release/Done
cycles, then the sixth admitted native option failed to open its field at line322
after132.177s. PID6685 exported119 records, ten parameter writes and zero
evictions or origin drops. Records116/117 begin on the real option;118 before
ended has the menu container as recipient, with the original collection model
alpha changing from1 to0 and no project assignment. Original leaf/content/cell
and collection remain attached with the original cell still occupying its slot.
High selection/reselection passed; focused-cycle20 was not reached. This target
recurrence rejects Project-only gesture omission as a sufficient routing repair.
Restore the original Project opener gesture before choosing another seam.

The iPad stopped earlier in the unchanged Priority prefix: the first High tap
did not yield a selected High row after reopening, failing line521 after56.318s.
PID37630 exported33 records with zero evictions. Its first option touch also
retargets to the container with original collection model alpha0 before ended;
the original cell remains attached. Priority retained its gesture. There are
zero attempted Project selections and no focused-cycle20 coverage on this
worker. The Project parameter-write hook cannot establish whether a Priority
binding setter ran. Keep this failure distinct from the phone Project drop.

Product identity matches head tree`c45d657bd6b35396e30aa0935282840a7f7e3672`,
Xcode27.0/27A266a, SDK24A430 and arm64 runtime24A434. Smoke41540858329
is being audited separately. No full or test retry was dispatched. Collection
model alpha and actual routing are measured; their exact ordering between
samples, rendered opacity, and initiating operation remain unresolved. No
keyboard-command suppression, input change or wider ancestor treatment follows
from this result.

Smoke41540858329 passed all four phone methods. The iPad durable case reached
detail completion, then failed to terminate app PID8718 at232.87s for its final
relaunch; the method failed after359.467s. That termination failure does not
establish a native option drop or its cause. Final durable reopen was not
verified. The independent iPad adaptive-navigation method passed. Both smoke
consumers used merge source`e6e12f12a261a911613ea815d693e7017f6f2c4b` with
the identical candidate tree and canonical toolchain/runtime. Every job in both
terminal head workflows is accounted for; no separately dispatched regression,
full or test retry exists. The verifier was captured and killed.

### Alpha writer and close/save attribution control

The next single observation keeps restored production gestures, focus, menus,
popover/zoom, glass, scrolling, input and deadlines unchanged. The opt-in
Debug/simulator trace now intercepts the public UIView alpha setter. Every
call forwards its original receiver/value exactly once. A constant-time lookup
checks a bounded weak collection target and live receiver identity; generic
public cell/collection captures are classified against the actual native option
journey offline. No private class predicate identifies a target. Keep at most
four recent weak targets so successful post-action fades remain observable.
Record up to four mutations per capture and64 total, exposing dropped counts.

For a tracked alpha decrease or subsequent restoration, buffer old/requested
values and pre-call state/timestamp, then forward the setter. After it returns,
record actual model alpha, return time and at most24 raw return addresses, with
observation duration. No symbolication, file I/O, layout, AX, responder, gesture
or animation mutation runs in the setter. The existing serial export queue
resolves address symbols; a startup asynchronous snapshot supplies public Mach-O
image UUIDs/load addresses outside input dispatch. The setter hook is removable
diagnostic instrumentation, not a supported UIKit extension point or repair.
Subclass/direct-layer bypass remains possible: observed alpha0 without a
matching setter receipt means incomplete interception, not absence of mutation.

Minimal correlated breadcrumbs cover the existing outside-tap callback and
its guard, close request and scheduled task, and save entry/guard, saving before
its first await, and exit outcome. They preserve original guards, state writes
and asynchronous ordering. Weak editing/store context supplies state at each
alpha receipt. Absence of earlier expansion/parameter writes did not rule out
a queued or unsuccessful close/save operation. A callback that starts during
ended dispatch cannot explain an alpha change already sampled before it.

Use one canonical focused execution on each family after auditing the completed
8d workflows. Compare a failed pre-ended mutation with passing selection fades
and app requests in the same process/session/generation. An earlier accepted
close/save operation or a synchronous app caller can select a concrete repair
boundary; a framework-only asynchronous endpoint does not establish its earlier
initiator. Same paths/order in passing and failing cases, missing/bypassed
setter coverage, relevant cap/drop/eviction, stale export, green-only or focus
prerequisite failure remain inconclusive. Do not suppress native alpha, commands
or main-menu rebuild requests, change input/deadlines, or retry unchanged source.
Remove every temporary observer before clean exact-head smoke/full acceptance
on both families.

The final generic arm64 test build and strict artifact verifier pass with
Xcode27.1 beta; no local simulator was booted. Review identified and resolved
an off-main Objective-C actor-thunk forwarding hazard and bounded the Mach-O
load-command parser. Both source-review axes are clear. This is build/source
evidence only; canonical execution must establish interception coverage and
measure any new timing disturbance before interpreting the trace.
