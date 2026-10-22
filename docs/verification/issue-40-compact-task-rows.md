# Minimal task rows — issue 40

Today, Upcoming, project and custom lists share `TaskListRow`. The user's
refinement replaces the original compact summaries with only the description,
project and a flag followed by a deadline relative to today. Project and
deadline share one metadata line, with the deadline right aligned. Today has
no task-section title. Rows use plain
list styling, no separators or colored backgrounds, and horizontal insets of
8 points leading and 12 trailing. Descriptions use the smaller Dynamic Type subheadline font and wrap without a fixed height.

The deadline uses local calendar-day boundaries: Yesterday, Today, Tomorrow,
N days ago or In N days. Core tests cover midnight and daylight-saving changes;
the display refreshes every minute. A planned day is never used as a deadline.
Upcoming keeps its existing order, day groups and task identities, with
Planned work and Deadlines labels outside the task rows. Full dates, tags,
activity, availability reasons and diagnostics remain in task detail.

A separate completion button has a 44-point minimum target and grows with
Dynamic Type. It calls `TaskStore.completeFromList`, which immediately saves through the existing `TaskStore.complete` operation. The label
opens detail; context menus retain valid Start/Stop, Edit and Complete actions.
Trailing swipes offer Edit only. There is no completion Undo. Filtering,
ordering, recurrence generation and stored task attributes are unchanged.

## Runtime journeys

`TaskPresentationUITests` uses canonical iPhone/iPad XCUITest with real
TaskChampion storage and completion. Its fixture has a long title, project,
active start marker, future waiting date, two prerequisites, distinct planned
and deadline dates and an opaque attribute. Calendar is injected empty.

- Today, Upcoming, project, custom and blocker detail are captured in light,
  dark, default text and accessibility XXXL modes. Row labels exclude the
  removed metadata; geometry assertions check the reduced horizontal margins.
- Ordinary completion removes both Upcoming appearances. Relaunch verifies
  durable completion, and Done shows the task without a completion circle.
- Recorded occurrence completion preserves its sibling. An incompatible parent
  mask produces a genuine failure, visible feedback and a retained occurrence.
- Activity and waiting regressions check state in detail while rows stay minimal.

Row baseline captures use `83ff10c4` (app UI unchanged in `a632410`).
Notification-settings baseline captures use isolated `209aafe` with test-only
instrumentation; its notification UI is unchanged from main. The initial
missing-circle check used `83ff10c4`. Devices, fixtures, appearance, text size and navigation match.
The fixed clock changes between Today and Upcoming to exercise both views.
The original completion journey failed at its missing circle before the fix.
The custom view is created at normal text size and reopened across modes,
keeping unrelated large-text editor keyboard focus out of the row matrix.

## Verification limits

Simulator evidence covers the exercised app paths. Physical touch, VoiceOver,
account behavior and distribution provisioning were not verified. Long rows can require scrolling. Matched completed-history
captures are omitted explicitly, while persistence and circle absence are
asserted at runtime. External Native tests remain skipped where Taskwarrior,
sync or Spotlight configuration is absent.

The PR records final test results, source revision and the local HTML report.

Host verification after rebasing onto `a632410`: Core 161 passed; Native
175-test run passed with external integrations and two fixture probes skipped; controller packages 51 Swift Testing and 6 XCTest
passed; UI selection routing 14 passed. Native included the independent probe.
Both Standards and Spec reviews reported zero findings.


## Alert-review removal

The review banner, attention-state aggregator, registration diagnostics and
manual retry workflow are removed. Notification settings retain permission,
midnight alert-time preferences and ordinary operation errors. Automatic
foreground/task-change reconciliation, scheduled delivery and missed-alert
processing remain unchanged in Core/Native. The controller keeps authorization
rather than exposing the diagnostic report to the UI. The real missed-alert
UI journey now checks automatic foreground permission refresh without a retry
button. Debug fixture controls remain gated to isolated simulator verification.

The notification-preferences capture journey checks permission/preferences
remain available and the review/registration controls are absent, across both
device families and all appearance/text-size modes.

The notification-preferences journey previously passed on both families at
`56e184c`; its captures are reused because this refinement does not alter that
screen. The latest row matrix and occurrence journeys passed on each family:
`/tmp/tsk-issue40-motion-phone-matrix.xcresult` and
`/tmp/tsk-issue40-motion-pad-matrix.xcresult`. These still captures preceded the
animation-only modifier correction; title, layout and checked-state behavior
are identical. The corrected completion journey passed on each family:
`/tmp/tsk-issue40-motion-v4-phone.xcresult` and
`/tmp/tsk-issue40-motion-v4-pad.xcresult`. Both owned simulators were shut down;
no simulator remained booted and Simulator was quit.

## Checked completion and collapse

Canonical task mutation, reload and sync continue immediately. A presentation
controller retains each completed row's original snapshot, placement and view
context through those reloads. After a successful save it displays a checked
circle and struck-through title for one second. If the canonical result no
longer includes the task, a 280 ms animation scales the content and row height
together toward the vertical center before releasing the snapshot. Upcoming
retains and collapses both appearances together. Reduce Motion keeps the
one-second feedback and skips the collapse animation. Tasks still matching a
view remain visible, while failed completion releases the hold immediately.
Circle, context-menu and workspace keyboard completion share this behavior.

Four controller tests use real TaskChampion mutations and an injected clock:
reload retention across both Upcoming roles; independent consecutive
completions with stable neighbor placement; genuine occurrence failure; and a
completed task that still matches its view. The first ordering implementation
failed when an earlier held row disappeared, then passed after placement used
neighbor identities. Core 161 passed; Native 175-test run passed with external integrations and two fixture probes skipped;
controllers 51 Swift Testing plus 6 XCTest passed; UI routing 14 passed.
Standards and Spec reviews reported zero findings.

Genuine simulator recordings confirmed the one-second checked feedback and
centered collapse on both device families. An earlier recording exposed
unscaled text during native List height animation; one AnimatableModifier now
interpolates scale and height together. The corrected signed arm64 simulator
build succeeded. The report embeds trimmed normal-speed WebM recordings,
rotating the iPad recording to match its actual landscape orientation.

Local visual report: `/Users/julesseguin/.local/share/ui-reports/tsk/label-implement-issue-40/20261022T135909Z.html`
(4,998,379 bytes; 106 captures and two recordings). All 14 sections and 106
images loaded at 390 × 844 in Chrome. Enlargement and both recordings were
verified. Production source is `2d09853`; WebP quality is 65 to preserve every
capture within the 5 MB delivery limit.

## Title-only row alignment

Rows with neither a project nor a deadline use centered vertical HStack
alignment, placing the title beside the center of the completion circle.
Rows with either metadata field retain their existing top alignment. The
shared row applies this consistently in Today, Upcoming, project and custom
views, including wrapped titles and Dynamic Type. Completion feedback and
collapse remain unchanged.

The signed arm64 simulator build and canonical populated-row matrix passed on
both iPhone and iPad, covering light/dark and default/accessibility XXXL text.
Results: `/tmp/tsk-issue40-center-phone.xcresult` and
`/tmp/tsk-issue40-center-pad.xcresult`. The matched captures show single-line
and wrapped title-only rows aligned with their completion circles. Both
Standards and Spec reviews reported zero findings. No business logic changed;
host suites were not repeated for this layout-only refinement. Both simulators
were shut down by the test runner; none remained booted.

Alignment report on this Mac:
`/Users/julesseguin/.local/share/ui-reports/tsk/label-implement-issue-40/20261022T141934Z.html`
(3,584,282 bytes; 80 captures). All ten sections were expanded and enlargement
opened and closed at 390 × 844. Production source is `9503280`. The previous
report retains the unchanged completion-animation and notification evidence.

## Animated checkmark and local saving feedback

Source `98f4ac3` removes the shared saving flag from completion-circle disabled
styling. Only the task's own feedback phase supplies that styling. Shared
saving still blocks pointer hits, and TaskStore's admission guard continues
to serialize mutations. Other tasks keep their normal titles and circles.

The circle-to-checkmark change uses native SF Symbols Replace at speed 3.
Animated completion allows 400 ms for that transition to settle, then retains
the existing one-second checked hold. Reduce Motion skips the symbol animation
and settling delay. Controller tests verify both durations and retention
through reload; all 51 Swift Testing and 6 XCTest controller tests passed.
The canonical checked-state UI assertion now samples immediately before its
fallback wait, avoiding a one-second first poll that missed the brief state.

A temporary native rendering probe used the real TaskListRow and TaskStore,
with a two-second hold in TaskStore.perform before a genuine scratch
TaskChampion completion. It failed on the unrelated circle's disabled state
before the fix, then passed on both iPhone and iPad. Captures show grey sibling
circles before and normal blue sibling circles after. Probe scaffolding was
removed from the production source. The matched iPad saving baseline was not
captured; that comparison is explicitly unverified in the report.

The final signed simulator build and canonical completion/persistence journey
passed on both families: `/tmp/tsk-issue40-tick-final-phone.xcresult` and
`/tmp/tsk-issue40-tick-final-pad.xcresult`. Genuine recordings confirm the quick
native tick followed by a visible checked hold. Both owned simulators were
shut down; no simulator remained booted and Simulator was quit. Standards and
Spec reviews found no material issues.

The user rejected scaled-content removal and requested stationary content
covered from top and bottom. Three throwaway browser motion variants were
provided: hard cover before reflow, hard cover with early reflow, and soft
cover before reflow. The user subsequently selected C, soft cover before
reflow; the implementation and verification are recorded below. Prototype source is
isolated in `/tmp/tsk-completion-motion-prototype` on
`prototype/task-completion-motion-40`, outside the production PR.

Interactive prototype and native evidence on this Mac:
`/Users/julesseguin/.local/share/ui-reports/tsk/label-implement-issue-40/20261022T150505Z-completion-prototypes.html`
(286,687 bytes; three replayable variants, ten native captures and two native
clips). The browser check is labeled illustrative. Native recordings use
normal playback speed and stop before the old collapse; the iPad clip crops
to the sidebar. The report was checked at 390 × 844, including variant
switching, Replay, slow motion, all four native sections, enlargement and both
recordings. Physical touch and VoiceOver remain unverified.


## Selected C: stationary soft cover, then close gap

Production source `ba6c5df` replaces content scaling with a centered soft mask.
After the native SF Symbols tick settles for 400 ms and the one-second checked
hold finishes, the visible region closes from top and bottom over 420 ms. Its
edges feather by up to six points. Text and icons remain stationary and
unscaled; the underlying list background is revealed. Only after the content
is hidden does the empty row gap close over 240 ms. Both Upcoming appearances
share the phases. Reduce Motion keeps checked feedback and removes the row
without the animated cover or gap closure.

The real-TaskChampion controller test first failed against the previous
280 ms collapse, then passed with explicit covering and collapsing phases.
The full controller suite passed: 51 Swift Testing and 6 XCTest. The signed
arm64 simulator build passed. Standards and Spec reviews found no material
issues.

Canonical iPhone and iPad each passed two focused methods covering ordinary
completion, both Upcoming appearances, durable Done read-back, recurrence
scope, genuine failure feedback and sibling preservation. Results:
`/tmp/tsk-issue40-soft-cover-phone.xcresult` and
`/tmp/tsk-issue40-soft-cover-pad.xcresult`. Genuine native recordings show
stationary content throughout the soft cover, followed by gap closure. Both
owned simulators were shut down; none remained booted and Simulator was quit.

All three prototypes and the C verdict are archived on
[`prototype/task-completion-motion-40`](https://github.com/Julesseg/tsk/tree/prototype/task-completion-motion-40/App/Prototypes/TaskCompletion)
at `7342e74`, linked from issue #40. Prototype code is outside this PR.

Final focused report on this Mac:
`/Users/julesseguin/.local/share/ui-reports/tsk/label-implement-issue-40/20261022T161721Z-soft-cover.html`
(673,057 bytes; 16 native captures and four normal-speed before/after
clips). The before source is `98f4ac3`. Sampled removal frames illustrate the
motion phases rather than equal elapsed times. iPad clips crop to the sidebar.
All eight sections and 16 images loaded at 390 × 844. Enlargement opened
and closed; all four clips played, advanced past one second, and were paused.
The previous reports retain the unchanged light/dark, Dynamic Type and
notification-settings evidence. Selected C was recorded in light/default
text; physical input, VoiceOver and system delivery were not reverified.

## Soft-cover pacing diagnosis

The user rejected the simplified native removal alternatives and asked to
retain the stationary soft cover. Those alternatives and the rejection are
archived outside this PR on `prototype/native-completion-options-40` at
`70a8d3c`, linked from issue #40. They are not the implementation below.

The original custom AnimatableModifier recalculated gradient geometry and
explicit row height during animation. A temporary simulator probe used the
real TaskListView, TaskListRow, TaskStore and scratch TaskChampion storage:
five sequential completions with 40 tasks. Main-thread CADisplayLink callbacks
requested at 60 Hz were generally 16.7 ms during cover, so callback timing alone did not catch
the reported stepping. Actual modifier updates and recorded-pixel movement
advanced about every 33 ms. Repeating with eight tasks reproduced this
pattern; large-list storage or remote sync was not necessary to expose it.

The fix animates a fixed soft mask with SwiftUI's scale transform. Only the
mask scales; text and icons stay stationary. It removes custom per-frame
geometry, height measurement and row-height interpolation. Retained snapshots
leave the visible collection only after the 420 ms cover is complete; native
List removal closes the hidden gap over 240 ms. Animation is keyed to the
completion IDs entering the removal phase, scoped to the active view. The
native SF Symbols tick, 400 ms settling delay, one-second checked hold,
failure handling and Reduce Motion path remain.

The calibrated pixel check uses actual recording frame timestamps and the
changing grayscale mass of the second row's mid-cover region. Phase samples
only bound the search window; MP4 creation time has coarse precision and is
not used to claim exact phase alignment. At a median movement-step threshold
of 24 ms, all five baseline completions fail and all five optimized
completions pass:

| Completion | Baseline median step (ms) | Optimized median step (ms) |
| --- | --- | --- |
| 1 | 33.333 | 16.667 |
| 2 | 33.333 | 16.667 |
| 3 | 33.333 | 16.666 |
| 4 | 31.667 | 16.666 |
| 5 | 31.667 | 16.667 |

The largest sampled optimized mid-cover step was 20.0 ms, versus 36.667 ms
before. This is simulator visible-cover cadence, not app-wide FPS or physical
phone performance. In the clean recorded candidate, covering callbacks had
p95 16.72 ms and max 32.15 ms; gap closure had p95 30.92 ms and max 35.22 ms.
Neither had callback gaps above 50 ms. Cold work around the first checked
feedback still reached 69.17 ms; the change does not establish a fix for all
possible hitches. No build, video decoding or host tests ran during this
final quantitative capture. An earlier overlapping timing trial was discarded.
Instruments Hitches was unavailable on this simulator and supplied no hitch
proof. Remote-sync traffic and physical-device pacing remain unverified.

The real-TaskChampion controller test was changed before the fix to require
removal from both Upcoming appearances at the collapsing phase. It failed
against the old retained-row implementation, then passed with native List
removal. The full controller suite passed: 51 Swift Testing and 6 XCTest.
The clean signed simulator build passed. Standards and Spec reviews found
no material issues. All temporary probe gates and sampling code were removed
from production before canonical UI verification.

Local diagnostic source, scripts and JSON are retained on this Mac at
`/Users/julesseguin/.local/share/ui-reports/tsk/label-implement-issue-40/completion-pacing-diagnostics-20261022`.
The pixel checker is calibrated to this fixture and recording ROI; it is not
a portable CI performance test. Its original commands are
`python3 /tmp/check_tsk_cover_pacing.py baseline-2` (red) and
`python3 /tmp/check_tsk_cover_pacing.py fixed-warm-recorded` (green).

Source `8b428e5` passed three canonical XCUITest methods on each family:
`testVisibleCompletionRemovesEveryUpcomingAppearanceAndPersists`,
`testOccurrenceCircleCompletionAndGenuineFailureKeepSeriesScope`, and
`testMatchedPopulatedTaskListsAcrossAppearanceAndAccessibilityText`.
These cover durable completion, both Upcoming appearances, genuine failure
and sibling scope, and Today/Upcoming/project/custom/detail in light/dark
and default/accessibility XXXL text. Results:
`/tmp/tsk-completion-smooth-phone-retry.xcresult` and
`/tmp/tsk-completion-smooth-pad-retry.xcresult`.

The initial local UI runs were interrupted when the Mac exhausted disk space;
those results were discarded. Task-owned generated build caches were cleared
and the checks rerun successfully one simulator at a time. Both owned
simulators were shut down; none remained booted and Simulator was quit.
The old SHA `0ee84d2` separately exhausted three iPad CI retries on HID relay
and settings accessibility-query failures, with seven other checks passing.
That stop and the need for runner/accessibility investigation were recorded
on PR #59; no unrelated tests or CI configuration were changed.

Final local report on this Mac:
`/Users/julesseguin/.local/share/ui-reports/tsk/label-implement-issue-40/20261022T183745Z-smooth-soft-cover.html`
(4,314,405 bytes; 100 matched native captures and two normal-speed clips).
All 50 sections were opened at 390 × 844, including the final sidebar crops
for readable default-text iPad rows. Image enlargement opened and closed.
Both recordings played, advanced past one second, and were paused. The clips
are encoded at 60 fps without motion interpolation to preserve the captured
before/after cadence. The pixel measurements use the original recording PTS,
not the re-encoded report clips. Static baselines are `9503280`; completion
baselines are `ba6c5df`. Diagnostic fixture UUID ordering differs between
motion recordings. Quantitative iPad pacing, a new native Reduce Motion
recording, physical input and full remote sync remain outside this evidence.
