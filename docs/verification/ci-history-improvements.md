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

### Alpha attribution inconclusive; focus prerequisite remains red

At `04ce1540e906c96d63d88c7714687ae8aea0f713`, focused41545609830
completed nineteen real New-project/Release/Done cycles on each family after
High selection/reselection. Both then failed the original focused-cycle20
keyboard-nonexistence prerequisite at line316, before option20. Phone elapsed
326.584s; iPad454.834s. There is no twentieth-option result and no reproduced
native option drop in this control. Nineteen successes do not establish repair
of the earlier intermittent action loss.

Phone PID6100/session529DDAE1 exported310 records and38 active-owner parameter
writes. iPad PID12925/session2D09A0E5 exported313 records and38 writes. Both
installed setter-v1, report zero record/origin/mutation drops and no evictions,
and contain nineteen pre-ended Project samples at collection model alpha1.
However neither contains any intercepted alpha mutation or symbol stack, even
a successful fade control. Installation therefore does not establish setter
coverage. Exports stop at phone title-began and iPad title-ended, before opener20;
zero evictions does not make those late exports complete. Do not infer missing
HID delivery, no close/save activity at opener20, or a negative alpha-writer
result. The probe did not select a production repair. Remove its setter hook,
image/stack machinery and close/save breadcrumbs; do not repeat it unchanged.

Smoke41545598882 passed all four phone methods. Its iPad durable method failed
High selected-state acknowledgement at line521 after132.023s, before Project
coverage. The independent adaptive method failed its original Project-field
keyboard requirement at line81 after44.616s. Its frame shows the field caret
and Hide-keyboard control but no software keyboard; native didBeginEditing is
recorded. This is separate from a native option drop and does not establish
why the keyboard was absent. Neither smoke method opts into the native trace.

Every job in exactly two terminal head workflows is audited. Producer/consumer
identities match tree`8fb69733b6c63377f8b801dbdb3407e575a145e3`,
Xcode27.0/27A266a, SDK24A430 and arm64 runtime24A434; smoke merge source
`fb52b349d5fa8c80d0c4550cb5ed1fe6a722315a` has the same tree. Both managed
terminals were captured and killed. No test retry, regression or full dispatch
exists. The repeated focused-opener keyboard failure is now the next distinct
repair target, with all assertions retained and intermittent action loss still
unresolved. No alpha/command/rebuild suppression or broad ancestor removal is
supported by this control.

The temporary sendEvent/weak-origin recorder, App-delegate installer, parameter
and expansion hooks, actual-registration/request instrumentation and test opt-in
are now removed as well. Retain the twenty real native cycles, original focus
prerequisite and selection/geometry/deadline assertions. Existing keyboard
verification receipts and functional registration deduplication remain. The next
focus repair will execute without these temporary runtime interceptions.

### Project menu activation clears text focus

The next single repair candidate replaces only Project's extra simultaneous
tap gesture with the public UIControl menuActionTriggered event. Apple defines
that event before menu presentation. A passive UIViewRepresentable in the
existing label background searches only its own bounded ancestor chain for
the nearest public UIControl, attaches its own target once, and keeps the
control/anchor weak. Update the current focus closure, remove only that exact
target on association changes/dismantle, and allow one weak deferred attachment
attempt per window lifecycle. No global/sibling/private-class search, geometry
cache, hit testing, gesture, event synthesis or responder call is added.

The event callback validates sender, live window and label ancestry, then clears
the same titleFocused/focusedNote bindings synchronously. Attachment/update and
teardown never clear focus. Priority retains its original gesture; native
Menu/Picker/options, styling44/26, popover/zoom/glass and scrolling remain.
The alternative ButtonStyle press-state trigger was rejected for this candidate
because a cancelled pill press or scroll start could clear focus before committed
menu activation. The documented semantic event fits the opener contract, but
this SwiftUI control's actual attachment and event emission are unverified.

Only small opt-in Debug/simulator attachment, delivery and before/after-focus
receipts remain, capped at256 with explicit drops. Serialization/atomic export
run asynchronously; failures report once and do not retry unchanged data. No
global touch/alpha/registration interception remains. Remove these temporary
receipts after candidate validation, before clean acceptance.

Keep the original High/reselection and twenty native Project cycles, including
focused-title cycle20 and its five-second keyboard prerequisite before option20.
Append a note-focused opener, the same real New-project/Release/Done checks,
draft-note retention and return to title/note editing. Do not replace existing
assertions or extend input/admission/acknowledgement budgets. Require one valid
activation delivery on the attached source and actual keyboard disappearance.
Missing/stale/duplicate delivery, absent source attachment, keyboard persistence
or new native interaction/geometry/timing regression rejects this mechanism;
there is no fallback. A historical option-drop recurrence still blocks readiness
and must be classified separately, without claiming that this focus candidate
caused it. A passing candidate does not identify the original intermittent
loss's cause or establish final smoke/full acceptance.

Primary API boundary: [menuActionTriggered](https://developer.apple.com/documentation/uikit/uicontrol/event/menuactiontriggered).

Generic arm64 build-for-testing and strict artifact admission pass on
Xcode27.1 beta with no local simulator boot. Source review found and corrected
missing Coordinator actor isolation and silent diagnostic export errors;
invalid callback associations are recorded before being rejected. The two
review axes found no other actionable defect. This remains source/build
evidence, with attachment, actual emission, keyboard effect, notes and native
selection/timing/appearance awaiting canonical execution.

### Activation attachment works; direct focused coverage was not reached

At `2337aba18e819b8b59f20d4b69de2e0b07c9657c`, focused41552148053
failed on phone after84.975s: High/reselection passed, two complete Project
cycles passed, then cycle3 failed its field appearance assertion at line322.
PID11321/sessionC4CA8B7C exported eleven focus receipts with zero drops. After
an initial sizing instance detached, the live anchor attached to the enclosing
SwiftUI.HostingUIButton. Three corresponding Project openings each emitted
one valid event on the same source/coordinator/generation/window, with title
false and note nil before/after. This verifies unfocused source attachment and
emission, not dismissal of active text focus. There is no current global touch
or alpha trace to identify the third lost option as the historical retarget.

The iPad worker timed out launching the app via Xcode after200.468s, with no
focus receipts or native journey. That provides no attachment/emission/focus
verdict. Smoke41552134153 passed all four phone methods; iPad durable failed
the High-row existence assertion after reopening at line547. Final hierarchy
retains Priority=Not set and no menu, with zero Project coverage. Its separate
adaptive journey passed. Missing High on reopen is distinct from the earlier
selected-state assertion failure; it must not be reported as a Project result.

Both head workflows and every job are terminal and audited. Exact tree is
`0e1837437983bb7087124ae8a15b3e591afb1806`, canonical Xcode27A266a,
SDK24A430/runtime24A434; smoke merge source`c1dd724a75c2d7066bb5afe29bb99de922c0425c`
has the same tree. Both managed terminals are captured/killed. No retry/full
was dispatched. The focused workers also spent time queued with runner_id0
after their producer completed; unassigned waiting is not UI execution.

Keep the activation-based focus candidate strictly unverified. The existing
intermittent action failure blocked its focused trigger; it does not by itself
establish that the focus bridge caused that older defect. The next changed
variable is test reachability: add one independent title/Notes focus regression
with a fresh fixture and immediate native title focus, followed by the original
Project opener, five-second keyboard absence before option, real New-project/
Release/Done checks, Notes focus/draft retention and actual returned text entry.
No High warm-up or repeated opens precede the first focused trigger in this new
case. The original High/reselect, twenty cycles/focus20 and appended Notes method
remain byte-identical and selected. Production bridge behavior/receipts stay
unchanged; this is new direct bug coverage, not an unchanged stress-test retry.

Menu now selects two independent methods per family; full discovers the added
case too, yielding76/67 methods and partitions41+35/33+34. No original selection
is removed, no native fixture ownership changes, and worker count stays four.
Assert both identifiers actually execute rather than assuming continuation after
an unrelated method failure. A focused callback/keyboard success can support
that focus substep even if a later option action fails; unreached Notes remain
unverified. Absent/stale/invalid delivery or keyboard persistence on a covered
focused opener rejects the mechanism. Launch/precondition/export failures remain
missing coverage. No fallback, new hook, app patch, budget change or full dispatch
is combined with this test addition. Native option loss still blocks acceptance.

The generic arm64 test build and strict artifact verifier pass on Xcode27.1
beta, with no local simulator boot. All24 selection checks pass, including
unchanged full-union/fixture ownership and the two exact menu identifiers.
Standards review caught an assertion that could accept duplicate returned text
input; it now requires exactly one inserted marker and exact prior text after
removing it, without assuming caret position. Spec review is clear. These are
build/source/selection results, not runtime focus evidence.

### Direct focused opener rejects the synchronous binding handoff

At `0613f58a21cb41d8d12e964af5d614df3844a782`, both menu identifiers
actually executed on both families. iPad stress failed its first New-project
field acknowledgement after57.928s; phone stress completed one cycle before
the second field failure after76.619s. The independent case reached actual
title focus and keyboard presence immediately, then failed its original
five-second keyboard-absence assertion before any option input on both families
(iPad33.713s; phone47.445s). Notes and returned editing were not reached.

iPad direct PID15633/session04B47D52 exported seven records with zero drops.
One valid native event was delivered on the attached source/window/generation;
titleBefore=true and the immediate titleAfter readback remainedtrue. Actual
keyboard presence persisted through the deadline. This rejects this synchronous
representable-owned FocusState handoff. Immediate Binding readback can be a
snapshot and does not alone prove that the setter was ignored, nor identify
where a focus request was lost or reset. Native event emission is established;
keyboard dismissal is not. No press/tap/responder fallback follows.

Phone direct PID15577/session1E210B82 exported only five attachment records,
without fresh opener events. Its keyboard failure is real, but event absence
is not meaningful without that late coverage. The separate phone stress
PID13075 emitted two valid unfocused callbacks. Do not conflate the two sessions
or infer native option routing from older global traces.

Producer source/tree and canonical Xcode27A266a/SDK24A430/runtime24A434 match
both families. Smoke is still being audited by its separate managed verifier.
No retry or full was dispatched. Retire/revert this failed app variant before
selecting another state-handoff treatment; retain both native regressions and
their unchanged assertions/deadlines. The native event seam can inform later
diagnosis, but the functional target does not stay merely because it attached.

Smoke41561707023 subsequently passed all four phone and both iPad methods.
Exactly two head workflows and every job are now terminal and audited, with
no full or retry. The verifier was captured and killed after final completion.
This green smoke does not cover or override the rejected direct focus result.

### SwiftUI-owned focus action candidate

The next single candidate restores the pre-B content-to-pill unfocus closure
API. TaskRowEditorContent.body forms the same false/nil focus assignment; the
pill stores that callback and the native adapter only forwards a generic action.
The adapter has no FocusState.Binding properties or TskCore/focus-field knowledge.
Its proven public event, bounded weak source attachment, exact-target lifecycle,
sender/window validation and synchronous invocation remain unchanged. Project
still omits the extra tap gesture; Priority and openPicker use the original
unfocus closure. Native layout/style/menu/presentation and both UI methods and
all deadlines remain unchanged. No owner onChange or additional hook is added.

This changes the focus action's formation/capture boundary, rather than another
event or responder mechanism. The original representable binding plumbing was
new; restoring the existing SwiftUI action contract is a falsifiable repair
hypothesis. Apple documents FocusState.Binding as writable, so do not claim
that bindings generally cannot cross UIKit or that a snapshot readback proved
a lost write. The failed variant has already been reverted.

Small request receipts now originate inside the actual SwiftUI closure, label
false/nil as requested values, and mark same-turn readback advisory. Native
delivery receipts still identify the source. A valid focused event and closure
request must lead to actual keyboard absence within the original five seconds
before option input, followed by native field/Done, Notes and returned typing.
A covered repeat keyboard failure rejects this closure candidate; do not stack
a delayed-focus patch, wrapper rename or fallback afterward. Missing launch/
attachment/event/export coverage remains unverified. A later option failure
keeps readiness blocked while any earlier focus substep is reported accurately.
Keep one changed-head canonical execution on both families, then remove all
temporary receipts before eventual clean exact-head smoke/full acceptance.

Generic arm64 build and both source-review axes pass; strict artifact admission
is checked before publication. No local simulator was booted. The production
focus effect and existing native option loss remain runtime-unverified.


### SwiftUI-owned action also fails; observe the actual focus owners once

At65a57dffd5cf0bcab575fc66d75cd3653c64a0f1, focused41564899779
actually executed both methods on both families. Phone stress failed its first
New-project field acknowledgement after72.056s. iPad completed eight cycles,
then the ninth field acknowledgement failed after195.429s. Both independent
direct cases reached title focus and keyboard presence, delivered the correct
native source event and invoked the SwiftUI-owned request, but failed keyboard
absence within the original five seconds BEFORE option input (phone37.132s,
iPad45.608s). Notes and returned editing were not reached.

Direct phone PID9561/sessionF4984635 and iPad PID51824/sessionD8D27ECC each
exported seven records with zero drops. Delivery6 has the correct live source,
window and generation; request7 asks false/nil with titleBefore=true. Immediate
readback remains advisory. The actual keyboard deadline rejects C on both
families. Restoring closure formation did not repair this contract; do not
retain C as an acceptance candidate or claim that a setter was ignored.

Smoke41564890924 passed all four phone and two iPad methods. Exactly two
head workflows and all producer/consumer jobs are terminal and audited against
the intended source/tree and canonical Xcode27A266a/SDK24A430/runtime24A434.
Both managed terminals were captured and killed. No retry or full ran. Smoke
does not cover or override the focused failures.

The next head holds failed C ONLY for one diagnostic observation of the same
known-red boundary. Passive onChange(initial:true) and appear/disappear receipts
are added at the actual TaskListRow title FocusState owner and TaskRowEditor
Notes FocusState owner. The existing rowGeometry reference supplies a labelled
application-owner proxy, not a FocusStore identity. Notes has a DEBUG State UUID
used only as a lifetime correlation token, never mutated or applied as an id.
Requests gain row/editing identity. Existing keyboard editing-notification text
gains native view/window identities and countN/32; its original window guards,
cap, forced query and synchronous legacy sink remain unchanged. Only the new
owner receipts use the existing bounded asynchronous focus sink.

Require a real observed title false-to-true transition after native Begin as
the positive control, matching row/owner/editing/session/PID and opener event,
zero drops and usable late export. Initial equal observations are not resets;
lifecycle reads are advisory. Never combine replaced owner tokens into one
reset. The notification cap and window guards limit meaningful missing End
claims, especially after repeated stress fields; the fresh direct-case PID is
the cleanest correlation. A last file/event timestamp alone does not establish
continuous coverage through five seconds. Notes remains untested if title fails.

Same-owner observed false then true selects restoration/reacquisition for
investigation, not its cause. Observed false while the keyboard remains selects
model/native association investigation, conditional on whether another native
input acquired focus. With positive owner-focus coverage but no later false,
say only that no persistent owner change was observed; coalescing prevents a
claim that the request was ignored or never accepted. Replacement, cap/drop/
export gaps or only green outcomes are inconclusive. Reading focus in onChange
can alter SwiftUI dependency participation, so a green diagnostic cannot
rehabilitate C or become an empty-observer production fix.

No focus setter, reaction, delay, input, target or global hook is added. Both
test bodies, selections and native five-second keyboard-before-option bar stay
unchanged. One changed-head observation per family only; no equivalent retry or
full on known red. Retire these owner diagnostics after the experiment, select
any production treatment from actual discriminating evidence, and remove all
temporary receipts before clean exact-head smoke/full/design acceptance.

The generic arm64 test build and strict artifact verifier pass without booting
any local simulator. These are build checks, not runtime owner-state evidence.
Both Standards and Spec source reviews report zero findings for the owner
observation delta. They explicitly preserve the coalescing, lifetime and graph
perturbation limits; no production repair claim is supported by this change.


### Actual owner clears and native editing ends; keyboard remains rendered

At22d127706eb5f09621d34b3a6e3a236277d2b567, both menu methods executed on
both families. Phone stress completed nine cycles, then the tenth field was
absent (204.904s); iPad failed the first field (63.132s). Direct title cases
failed the original keyboard-absence prerequisite before any option input
(phone34.166s, iPad38.517s). Notes/returned editing remain unexecuted.

The direct owner control has positive coverage on both families. Phone
PID13071/session164071BA has a real title false-to-true at uptime870.931,
valid source delivery/request at874.508, and same-owner true-to-false at874.884.
iPad PID4134/session0BBC2189 has false-to-true at401.317, delivery/request
at406.572, and same-owner true-to-false at407.064. Both packets contain21
records/zero drops; row/editing/proxy identity matches across each episode.
Initial equal values and earlier navigation-owner replacements are not resets.
No subsequent true transition is observed, but each export ends soon after
false: this does not establish five seconds of continuous owner-false state.

The same original native VerticalTextView/window emits Begin then End on each
family, at notification counts1/32 and2/32, with firstResponder=false at End.
A subsequent existing responder sample captures TaskKeyboardController. This
is positive evidence that the title's native editing ended; it does not make
that command host the cause or prove absence of every later native focus event.
The legacy fixture's window guards and event-driven export still limit silence.
Phone direct video at28s visibly shows both the native Project menu and keyboard
keys near the failing deadline, so this is not merely an AX-only inference.
The hierarchy names UIKeyboardLayoutStar Preview, but that private name does
not establish a snapshot mechanism or justify a private API intervention.

This selects the model/native presentation integration boundary for further
investigation and demotes the claim that the focus request never reached its
owner. It does not rehabilitate C, prove a root cause, or justify a delayed
write, responder workaround, keyboard command/rebuild suppression or empty
onChange fix. The owner observation can itself affect graph participation.
Retire its onChange/lifetime/notification-string additions after this one run.

Smoke41570381907 passed all four phone methods. iPad failed its first native
New-project field at line191 (63.432s), then its separate navigation method
failed app termination (169.458s); retain that termination classification.
Menu41570391642 and smoke are the only two exact-head workflows, all16 jobs
are terminal, no retry/full ran. Both producer/consumer trees match4f698b0;
smoke's synthetic merge contains the head and the same tree. Canonical
Xcode27A266a/SDK24A430/runtime24A434 and arm64 match both families. All managed
terminals were final-captured and killed. Full acceptance remains blocked.


### Finite minimal native-menu focus reproduction

No production correction is supported yet. The next diagnostic changes one
explicitly composite host factor: a DEBUG simulator-owned gate at WindowGroup
selects a minimal SwiftUI root instead of task storage, row/List ancestors and
the keyboard command host together. The gate requires isolated-simulator1,
a valid test session and matching fixture/replica UUIDs. Normal product
composition remains C, rejected and held only for this diagnostic comparison;
its completed owner onChange/lifetime/log-string probe has been removed.

The minimal root preserves vertical SwiftUI title/Notes fields with Boolean
title and optional UTF8String Notes focus, separate owner/binding layers, and
the same TaskMenuActivation implementation. A SwiftUI content closure requests
false/nil synchronously on the same public source event. Project uses the
shared label and26/44 style, native Picker with UTF8String tags and exact
No project/Release/New project ordering, matched source/zoom, and a real
340-point anchored popover with Release input/Done. Local fixture state avoids
storage/row/List/command hosts. The omitted composition and layout differences
are a group, not a claim of one precise ancestor ablation. No new observer,
global hook, timing change, responder operation or fallback is added.

Two independent fresh-fixture methods exercise title and Notes separately,
with actual focus/keyboard presence and retained draft, one native source-center
opener with fresh bounded admission, the original five-second absence/elapsed
assertion BEFORE option input, then exact native New-project/Release/Done and
returned typing. A title failure does not prevent the independent Notes case.
Both original product methods remain byte-identical and selected. Menu now has
four methods per family; temporary full inventory is78/69, partitions41+37/
33+36 with the same four workers. No original method is removed, and no full
is dispatched while known failures remain. The two diagnostic methods and
fixture must be retired after this finite comparison before clean acceptance.

Use the existing tiny source attachment/delivery/request receipts, actual
outcome and video/hierarchy. The fixture has no TaskKeyboardHost observer;
matching native End receipts there are neither required nor fabricated.
Product red plus a valid matching minimal red means omitted product composition
is not necessary for this phenotype; the adapter remains present, so this is
not proof of an Apple-only defect. Product red plus both minimal cases green
implicates the omitted composition as a group, not keyboard commands or one
ancestor. All-green, invalid focus/attachment/emission, launch failures or
unexecuted stages are inconclusive for this partition. An option failure after
successful keyboard absence stays a separate action outcome, not common cause
proof. Minimal-green never validates C in the product.

One changed-head comparison on both canonical families only; no unchanged
repeat/full. Remove remaining temporary diagnostics before eventual clean
exact-head smoke/full/design acceptance. The generic arm64 build and24 routing
checks pass without a local simulator boot; runtime reproduction is pending.
Both Standards and Spec reviews report zero findings. The final arm64 generic
test build and strict App/Share/Widget/Shortcuts artifact admission pass. These
are source/build/routing checks only; no canonical minimal-root outcome is yet
established and no local simulator was booted.


### Bare minimal focus passes on both families; product remains red

Atcc1617f05283168aaf780b8b7db6aedbc5608433, all four menu methods actually
executed on each canonical family. Bare Notes/title passed on phone58.689s/
36.454s and iPad48.597s/33.256s, including keyboard absence before option,
real New-project/Release/Done, retained draft and returned actual typing.
Each independent minimal packet has six events, zero drops, one matching
source/window/generation delivery, an active appropriate focus value in the
request and a later option-action request. Same-turn readback remains advisory.
The passing native keyboard assertion is the functional outcome.

Product direct title still fails its original five-second keyboard prerequisite
before any option on phone37.400s and iPad64.966s, with valid active-title
source/request evidence. Product Notes/return typing are not reached. Phone
stress fails its first field acknowledgement (59.381s). iPad completes twelve
cycles, then the thirteenth field/Release value is acknowledged after its
five-second appearance deadline by26.467s (298.947s total). That is a timing/
AX-read-budget failure, not missing action. Current traces have no global touch
observer and cannot label these failures with historical retarget signatures.

This satisfies the product-red/minimal-green branch on both families and
implicates omitted integration as a group. It does not identify one ancestor,
validate C, prove an Apple-only bug or compare intermittent option reliability
from one minimal selection against twenty stress selections. Source/runtime/
tree identities match. The iPad menu summary exporter timed out at20s; the
canonical runtime summary was recovered from its retained xcresult locally,
without a test retry. Keep that export limitation distinct from UI failures.

Smoke41573227989 passes all four phone methods; iPad navigation passes while
the durable row method fails app termination (396.560s). Exactly two head
workflows/all16 jobs are terminal and audited, with canonical Xcode27A266a/
SDK24A430/runtime24A434 and matching head/synthetic-merge tree. All watcher/
verifier terminals were final-captured and killed. No retry or full ran.

### Paired keyboard-host add-back, diagnostic only

The next single component add-back compares the same bare minimal root with
TaskKeyboardHost containing that exact root. This adds the existing controller
hosting/environment/lifecycle component as one group. Host source and adapter
remain unchanged. Do not add product ignoresSafeArea policy, NavigationStack,
List, storage, command scopes, dummy commands or a focus observer. The added
component naturally executes its existing conditional becomeFirstResponder
lifecycle and legacy fixture diagnostics; it adds no new/manual responder call,
but it must not be described as having no responder operations at runtime.

The owned simulator/session/matching-UUID gate now validates an immutable mode:
bare or keyboard-host. Unsupported modes do not silently select bare. Test
launch attachments and the existing request receipt identify mode; retained
hosted keyboard/appearance fixtures corroborate actual host construction and
empty command context, without a new observer. The fixture body, focus owner/
binding arrangement, menu/Picker/style/presentation and helper journey are
identical between arms.

Retain the two bare and two product methods byte-identical and selected, adding
two fresh independent hosted title/Notes methods. Six actual methods per family
must be audited on one changed head; no ordering or continuation assumption.
Temporary full inventory is80/71, partitions41+39/33+38, same four workers.
All native focus, one center opener,20s admission, original five-second keyboard
absence/elapsed BEFORE option, real field/Done and returned draft typing remain.

Bare passes plus hosted matching focus red with valid delivery selects the
whole host component as sufficient in this reduced setup/family, not commands,
AnyView, first-responder policy or one line as cause. Bare and hosted both pass
with product red shows host alone is not sufficient under an empty router;
it does not exonerate host-with-real-scopes/navigation/List integration. A bare
control failure, missing source/launch/admission coverage, family disagreement
or no product reference red prevents a clean contrast; report actual outcomes
without an automatic repeat or add-back chain. Later option failure remains
separate from successful keyboard dismissal. C and all fixtures remain
rejected for production acceptance. Retire the temporary fixture, four minimal
cases and all receipts before eventual clean exact-head smoke/full acceptance.
Standards and Spec reviews report zero findings for the paired add-back delta.
The generic arm64 test build, strict App/Share/Widget/Shortcuts artifact admission
and all24 routing checks pass. No local simulator was booted. This is build/
source evidence only; the paired canonical runtime comparison remains pending.


### Empty keyboard host is sufficient in the reduced focus fixture

Atb1b833064fd927885794a819ec15164ef7871e41 all six menu methods actually ran
on both families. Bare Notes/title pass on phone28.881s/29.552s and iPad29.430s/
30.202s. The unmodified TaskKeyboardHost arm fails the original five-second
keyboard-before-option assertion in both fields on both families: phone Notes/
title30.372s/20.560s, iPad49.723s/24.012s. No hosted option was attempted after
that failed prerequisite; field/Done/returned-typing coverage is absent there.

Each hosted packet has five events and zero drops, a valid matching live source/
sender/window/generation event and active expected title or Notes request,
with fixtureMode=keyboard-host. Each same-PID keyboard fixture corroborates
actual host creation: workspace appeared firstResponder=true, empty scopes/
hosts and installationCount0. With no registered scopes, the existing window/
controller guard omits editing notifications. Missing End in those packets is
not evidence of continuing native text editing. Bare packets have six events/
zero drops and complete passing native UI journeys. This establishes whole-
component sufficiency for the focused-keyboard phenotype in this fixture;
it does not identify one override, initial claim, AnyView, router or private
mechanism as cause. No actual commands or registrations are needed for this
reduced phenotype, while production command compatibility remains untested.

Product direct keyboard focus remains red on both families. Phone stress
completes ten cycles then fails the eleventh field (160.770s); iPad fails its
first field (43.984s). Those field failures remain separate from focused-keyboard
results and are not labelled with historical touch retarget evidence. Smoke
passes all four phone methods; iPad navigation passes88.070s while the durable
row method fails app termination350.832s. Both workflows/all16 jobs are terminal,
source/merge tree and canonical Xcode27A266a/SDK24A430/runtime24A434/arm64 match,
all terminals are final-captured/killed, and no retry/full was dispatched.

### Default-behavior controller decomposition, diagnostic only

The next finite control retains bare, custom-host and product references, and
adds a default-behavior host. It preserves the UIViewControllerRepresentable
construction contract: UIHostingController<AnyView> starts with EmptyView,
then receives the same AnyView(content plus router environment) assignment in
make and every update. A storage-only subclass keeps the same controller-owned
let router=TaskKeyboardRouter() lifetime/initialization, with ZERO lifecycle,
responder eligibility, action availability or presses overrides. It inherits
platform behavior; it is not literally an un-subclassed platform controller.
The coordinator-router proposal was withdrawn to avoid changing ownership too.

This changes the custom behavior group, including viewDidAppear's initial
claim AND its existing diagnostic, together. Do not replay that diagnostic or
claim on the default arm to equalize it. Existing TaskKeyboardHost/controller
and TaskMenuActivation code stays byte-identical. No safe-area, navigation,
storage, scopes, commands, manual responder call, focus observer, root-update
freeze, delay or global hook is added. The complete minimal fixture subtree
is byte-identical; the six existing test method bodies remain unchanged.
A new validated immutable mode and one bounded existing-sink factory receipt
identify the actual default controller/router construction without querying
responder state or adding an observer. Existing request receipts identify mode.

Two independent fresh default-host title/Notes cases reuse the exact native
journey: actual keyboard-present precondition, one center opener with20s
admission, original five-second absence/elapsed BEFORE option, actual native
New-project/Release/Done, retained draft and returned typing. Eight methods per
family must actually execute on one canonical changed head. Temporary full
inventory is82/73, partitions41+41/33+40, still four workers. No full is run
while known failures remain; retire all six minimal cases/fixture/receipts
before eventual clean product acceptance.

Bare/default pass with custom-host keyboard red selects the custom override/
lifecycle-diagnostic group as the measured difference, not one removed line
or permission to delete production responder support. Bare pass with both
host types keyboard red means custom overrides are not necessary; the retained
nested hosting/root/router-environment group remains sufficient. Mixed fields/
families, changed reference outcomes, missing mode/source/input/export coverage
or later option/ACK failures must retain their exact classification. No automatic
retry or stacked follow-up. A default-arm pass cannot establish real command
compatibility or twenty-cycle reliability. Any eventual production repair must
preserve actual keyboard-command ownership/availability in workspace/editor/
presentation scopes, plain versus Command input, title/Notes dismissal/return,
Project/Priority selected/reselect, repeated actions, popover/morph and all
remaining regressions, then pass observer-free exact-head smoke/full on both
families. C and these controls remain diagnostic only.
Standards and Spec source reviews report zero findings. The generic arm64 test
build, strict App/Share/Widget/Shortcuts artifact verifier and all24 routing
checks pass, without booting a local simulator. These are build/source results;
no canonical default-behavior outcome or production acceptance is established.


### Default behavior passes; custom lifecycle group remains the discriminator

At33f6c04f4adc884f9d97907ab20521789b14b6ed all eight methods were attempted
on both families. Bare and default-behavior title/Notes pass complete native
keyboard-before-option, field/Done and returned-editable-draft journeys. Default
phone Notes/title take86.256s/31.794s, iPad135.026s/53.609s; overall case time
includes startup/preparation/teardown and is not a speedup claim. No original
sixty-second app-animation warning was observed in retained logs. Custom-host
Notes/title still fail keyboard absence before option (phone26.097s/32.725s,
iPad37.133s/33.637s).

All four default packets have seven events/zero drops, actual storage-only
controller/router factory identities, valid active-focus source delivery and
later action requests. Bare packets have six events/zero drops; custom packets
have five events/zero drops with valid delivery/request and actual empty-host
appearance corroboration. This identifies the removed custom override/lifecycle-
diagnostic group as the measured difference. It does not identify the initial
claim, eligibility, diagnostic side effects or another override as cause, nor
validate production command compatibility. Nested hosting/root assignment and
preserved router/environment alone are insufficient in these controls.

Product direct focus remains keyboard-red on both families. Phone stress
completes eight cycles then fails field9 (143.080s). iPad stress cannot launch
an app process (177.137s); that method was attempted but has no native stress
input coverage. Direct product focus still provides the covered red reference.
Smoke passes all four phone methods; iPad first New-project field is absent
(59.953s), while navigation passes94.067s. Exactly two workflows/all16 jobs are
terminal with matching head/merge tree and canonical Xcode27A266a/SDK24A430/
runtime24A434/arm64. Both managed terminals were final-captured/killed. No retry
or full ran. Launch, field and focus failures retain separate classifications.

### First eligible lifecycle request only, diagnostic ablation

The next single ablation keeps the SAME TaskKeyboardController class, hosting
factory/root assignments, router lifetime, canBecomeFirstResponder eligibility,
canPerformAction/presses overrides and original workspace diagnostic. A fully
validated DEBUG simulator-owned minimal mode is frozen once per controller
lifetime. Only its FIRST eligible app-owned becomeFirstResponder request in
viewDidAppear is omitted. Ineligible appearances do not consume it; every later
eligible appearance issues the original request. This tests that initial request,
not an ongoing no-claim policy. The every-callsite suppression proposal was
withdrawn during convergence. No resign operation, alternate responder, delayed
focus or command/rebuild suppression is added. Ordinary product and existing
reference modes retain their original request behavior.

Every observed custom-fixture viewDidAppear reuses the original guard's one
computed result and emits bounded decision metadata with controller/router
identity, frozen mode and appearance/eligible-request ordinals. The receipt says
issued/omitted/guard-rejected, not that a request necessarily became focus.
No extra responder scan/query is added. The existing diagnostic still executes
in its original position after the request decision, including its existing
capture/availability queries and synchronous evidence write. Naturally changed
query values and downstream effects are not separated from the omitted request.
The new decision receipt uses the existing bounded asynchronous sink.

Require positive first-eligible omission coverage before native text focus,
one controller lifetime, matching active source request and native keyboard
precondition. Any eligible re-claim before/during the keyboard verdict contaminates
initial-omission attribution; stop that episode inconclusive rather than broadening
the omission. A later claim strictly after the completed verdict leaves that
earlier substep interpretable, while field/Done/returned editing may be affected
separately. Export ending at the opener cannot establish absence of later claims:
zero drops or one deduplicated workspace record is not complete late coverage.
Successful later action receipts can provide coverage after the keyboard verdict;
an uncovered negative tail remains inconclusive. No continuous FocusStore claim.

Retain all eight prior method bodies and fixture view subtree unchanged, adding
two fresh independent first-claim-omitted title/Notes cases with the same native
input,20s admission, original five-second keyboard absence/elapsed BEFORE option,
field/Done and editable-draft journey. Ten methods per family must be audited
on one changed head. Temporary full inventory is84/75, partitions41+43/33+42,
still four workers. No full or unchanged repeat while known red.

Passing omitted-call cases with admitted, uncontaminated operation coverage and
live bare/default-green/custom-red controls supports a contribution of the first
app request in this fixture/configuration. It does not establish private keyboard
retention mechanics, prevent other routes to first responder, or license deleting
production command ownership. Same covered red with adequate uncontaminated
coverage rejects initial-request necessity for that episode; missing tail,
changed references, mixed cases/families or later-stage reds retain exact limits.
No automatic eligibility/diagnostic fallback or stacked probe. Retire all fixture
gates, eight minimal cases and temporary receipts before eventual clean smoke/
full/design acceptance. Actual real-scope keyboard/HID command ownership,
availability, plain typing, selected/reselect, twenty-cycle/focus20/morph and
remaining regressions remain mandatory for any eventual production repair.
Standards and Spec source reviews report zero findings. Generic arm64 test
build, strict App/Share/Widget/Shortcuts artifact admission and all24 routing
checks pass without a local simulator boot. These are build/source results,
not a runtime omission outcome, command-compatibility result or acceptance.


### First-claim outcome and inherited-eligibility product candidate

At be2cc91, menu41582457487 and smoke41582447508 finished red with all10
selected menu methods attempted on both families. Bare/default title and Notes
passed; normal custom and first-claim-omitted cases failed the original
keyboard-before-option check. Each omitted-call packet proves eligible ordinal1
was omitted before actual focus and contains valid source/request coverage,
with6events/zero drops. Those packets end at the request, before the verdict.
They do not fence the late interval against a subsequent eligible claim, so the
initial-request causal comparison is INCONCLUSIVE; functional failure does not
establish that the initial request was unnecessary. Phone product direct failed
its keyboard-present precondition, while pad direct reached the covered
keyboard-absence failure. Stress completed3phone/1pad cycles before later field
absence; these are separate from focus and launch outcomes. Smoke finished
phone2pass/2fail and pad2pass; no unchanged retry or full ran.

The next bounded PRODUCT candidate restores inherited UIHostingController
responder eligibility by deleting only TaskKeyboardController's unconditional
canBecomeFirstResponder=true override. The original guarded viewDidAppear
request and legacy diagnostic ordering remain, as do router/command lifetime,
registration/rebuild, scoped actions, presses forwarding, root updates and the
native menu activation/SwiftUI-owned focus closure. The basis is the repeated
matched default/custom behavior-group contrast, not the unadmitted first-claim
negative. No inherited getter value, private keyboard mechanism or root cause
is asserted. The completed temporary root/modes/eight minimal methods and all
PR77 focus receipts are retired as diagnostic cleanup, separately from that
one functional policy change. Existing keyboard/HID harness diagnostics remain.

Command compatibility is a co-equal rejection gate. The focused menu manifest
retains both original product journeys, adds the existing standalone native
transport baseline and actual annotation modal/editor command case on both
families, plus a new cross-family real workspace/editor HID method. The iPad
broader workspace method is also retained on iPad without changing its skip
guard. The new method uses nine fixed owned phases, actual native input and UI
results, plain typing, selected-row edit/save/complete/view, Settings return,
recapture/save and persistence. No fallback app action qualifies. Existing nonce,
PID, expiry, phase order, byte and UP-cleanup checks remain; sequence bounds are
per registered case, preserving the old limits while admitting nine new phases.

Menu selection is5phone/6pad, keyboard12/10, permanent full77/68 across the same
four workers (42+35/34+34). No full is authorized while known red. Covered focus
or actual command regression rejects the candidate and restores the override;
launch/transport/unreached coverage remains unverified, not causal evidence.
Native option loss remains a separate blocker even if focus and HID pass. No
responder fallback, delay, command suppression or unrelated Share/reorder fix
is stacked. Clean exact-head smoke/full both families and design acceptance
remain required after supported repairs; no empty-fixture pass certifies these.

Source validation for this candidate: Standards0hard breaches/one deliberately
retained nonblocking adapter-metadata cleanup item, Spec0remaining findings and
design0blockers. Review caught and corrected a new-test readiness race: the
row-save acknowledgement now also requires the real row overlay to be enabled,
which fences editing lifetime beyond collapsed-field AX absence, within the
same10s budget. Selection24, execution-plan10, relay49, owner29, boundary3,
Swift command6 and registration5 checks pass. The final generic arm64 build
and strict App/Share/Widget/Shortcuts artifact check pass; no local simulator
was booted. Canonical product focus/command results are still pending.
