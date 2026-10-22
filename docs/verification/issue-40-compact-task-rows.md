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
