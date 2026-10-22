# Compact task rows — issue 40

Today, Upcoming, project and custom lists use `TaskListRow`. A separate
completion button has a 44-point minimum target and calls the existing
`TaskStore.complete` operation.
The target grows to fit Dynamic Type symbols. The task label remains a navigation link. Context menus consistently offer
Start/Stop, Edit and Complete where valid; trailing swipes offer Edit only.
There is no completion Undo.

The description wraps without a fixed row height. Project and up to two tags
share compact context; additional tags are counted. Active, waiting and blocker
count summaries adapt from horizontal to vertical layout when space is tight.
Full availability reasons, diagnostics, dates and tags remain in task detail.
Collapsed rows show the deadline rather than the planned day. Upcoming retains
its date-role identifiers, day groups and shared task UUID, with Planned work
identified separately from Deadline. Filtering, ordering, recurrence generation
and the completion operation are unchanged.

## Runtime journeys

`TaskPresentationUITests` runs on both device families. The populated fixture
has a long description, a project, an active start marker, a future waiting
date, two prerequisites, separate planned/deadline dates and an opaque field.
The fixture uses native `dep_<uuid>` attributes as well as exported `depends`.

- Matched Today, Upcoming, project, custom and full-blocker-detail captures in
  light/dark appearance with default and accessibility XXXL text.
- Completion circle removes both Upcoming appearances; relaunch verifies the
  task remains completed. A trailing swipe exposes Edit without Complete.
- A recorded Taskwarrior occurrence completes independently of its sibling.
  An incompatible parent mask produces a genuine failure, visible feedback
  and a retained occurrence. Core/Native tests cover atomic mask updates and
  preservation of unrelated attributes.
- Existing planning, project and Upcoming completion journeys now tap circles.
  The new class is included in the iPad full selection; iPhone full discovers
  all test classes automatically.

The baseline application is `83ff10c4b252101d2510f0e019f9e7a4876525f6`.
Its completion-circle journey fails at the missing control, before the shared
row implementation. Baseline captures add only the new UI test file in an
isolated worktree. Before/after devices, appearance, text size, fixture and
navigation match. The fixed clock changes between Today and Upcoming captures
so the same task can demonstrate each view without modifying its dates.

## Evidence

Local test results and the visual report are recorded in the PR. Simulator
results establish the exercised application paths, not physical touch,
VoiceOver, account behavior or distribution provisioning. Injected Calendar
is empty so these captures isolate task presentation. Installed TaskChampion
storage and the actual completion operation are used; mutation failures are
not mocked.

Local host verification: Core passed 160 tests; Native passed 131 and skipped
44 requiring external service/Taskwarrior/Spotlight configuration; controller
packages passed 47 Swift Testing tests and 6 XCTest tests. Native execution
included the built independent probe and its multi-process occurrence checks.
The UI selection script passed all 14 routing regressions. The shared app and
UI test products built successfully with signed arm64 simulator products.

The capture journey creates the custom view at default text size and reopens
it across appearance/text-size launches. This isolates row presentation from
native keyboard focus in the unrelated custom-view editor at accessibility
XXXL; task fixtures and the custom filter remain unchanged across modes.

Final canonical runs passed all three `TaskPresentationUITests` methods on
each device after the minimum-target sizing and swipe-reset corrections:
`/tmp/tsk-issue40-after-phone-v2-final.xcresult` and
`/tmp/tsk-issue40-after-pad-v2-final.xcresult`. The earlier seven-method iPhone
run also passed activity, planning, project and Upcoming regression journeys.

Local visual report: `/Users/julesseguin/.local/share/ui-reports/tsk/label-implement-issue-40/20261022T092100Z.html` (4,752,575 bytes; 88 captures).
All captures rendered in a 390 × 844 Chrome viewport, and image enlargement
opened and dismissed correctly. The existing Review task alerts control can
overlay lower content at accessibility XXXL in both revisions; long rows
require scrolling. Matched completed-history captures are omitted explicitly
in the report, while Done read-back and circle absence passed at runtime.

The after captures identify production-code commit `ae8f7eb` in their captions.
