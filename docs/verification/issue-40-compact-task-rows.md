# Minimal task rows — issue 40

Today, Upcoming, project and custom lists share `TaskListRow`. The user's
refinement replaces the original compact summaries with only the description,
project and a flag followed by a deadline relative to today. Rows use plain
list styling, no separators or colored backgrounds, and horizontal insets of
8 points leading and 12 trailing. Descriptions wrap without a fixed height.

The deadline uses local calendar-day boundaries: Yesterday, Today, Tomorrow,
N days ago or In N days. Core tests cover midnight and daylight-saving changes;
the display refreshes every minute. A planned day is never used as a deadline.
Upcoming keeps its existing order, day groups and task identities, with
Planned work and Deadlines labels outside the task rows. Full dates, tags,
activity, availability reasons and diagnostics remain in task detail.

A separate completion button has a 44-point minimum target and grows with
Dynamic Type. It calls the existing `TaskStore.complete` operation. The label
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

Baseline captures use `83ff10c4b252101d2510f0e019f9e7a4876525f6` plus the new
test file only. Devices, fixtures, appearance, text size and navigation match.
The fixed clock changes between Today and Upcoming to exercise both views.
The original completion journey failed at its missing circle before the fix.
The custom view is created at normal text size and reopened across modes,
keeping unrelated large-text editor keyboard focus out of the row matrix.

## Verification limits

Simulator evidence covers the exercised app paths. Physical touch, VoiceOver,
account behavior and distribution provisioning were not verified. The existing
Review task alerts control can overlay lower content at accessibility XXXL
in both revisions; long rows require scrolling. Matched completed-history
captures are omitted explicitly, while persistence and circle absence are
asserted at runtime. External Native tests remain skipped where Taskwarrior,
sync or Spotlight configuration is absent.

The PR records final test results, source revision and the local HTML report.

Host verification after rebasing onto `a632410`: Core 161 passed; Native 131
passed and 44 skipped; controller packages 47 Swift Testing and 6 XCTest
passed; UI selection routing 14 passed. Native included the independent probe.
Both Standards and Spec reviews reported zero findings.

Final canonical runs passed five iPhone tests (presentation matrix, ordinary
and occurrence completion, activity, waiting) and three iPad presentation /
completion tests. Results: `/tmp/tsk-issue40-refined-phone-final.xcresult` and
`/tmp/tsk-issue40-refined-pad-final.xcresult`. Owned simulators were shut down.

Local visual report: `/Users/julesseguin/.local/share/ui-reports/tsk/label-implement-issue-40/20261022T101929Z.html` (4,670,378 bytes; 88 captures).
All captures loaded at 390 × 844 in Chrome; image enlargement opened and
dismissed correctly. After captures use production source `98c6909`.
