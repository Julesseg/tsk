# Upcoming verification

Upcoming presents future planned work (`scheduled`) and deadlines (`due`) in ascending local-calendar-day groups. Only raw pending tasks with dates on a later day qualify, including pending waiting/blocked tasks and occurrences. Recurring templates, completed tasks, malformed dates, and today's dates are excluded. DST boundaries use calendar intervals rather than fixed 24-hour increments; the default calendar autoupdates with the device timezone.

`TaskManager.tasks(query: .upcoming)` returns unique persistent task records. `TaskManager.upcomingDays()` and `UpcomingDay.groups(tasks:at:calendar:)` project those records into date-role appearances. Presentation identity contains task UUID, role, and exact timestamp; each entry retains the original TaskRecord. Two dates create two entries, even on the same day, with no additional backend task. Days sort ascending, then entries by timestamp, planned-before-deadline role for equal timestamps, description, and UUID. Shared detail/editor/completion actions target the original UUID.

The native list groups entries under date headings and explicitly labels each appearance as Planned work or Deadline. Deadlines show their time. Save/completion update the underlying task collection first, then rebuild groups immediately through Core; genuine storage failures remain visible through the existing error and retry flow. Foreground/significant-time-change reloads refresh membership.

## Verified locally

- 15 Core tests at ticket base, including three Upcoming tests: two roles/different days/same day for one UUID; current/future day membership; Paris DST and injected UTC day boundaries; deterministic entry ordering; pending occurrence visibility; rescheduling/removal/completion through TaskManager; preserved start/opaque fields.
- Actual TaskChampion SQLite plus Taskwarrior 3.5.0: save/reopen one task as two ordered role entries, reschedule one date without altering the other, export exactly one UUID with the expected scheduled/due ISO dates and opaque attributes, complete one appearance, and reopen with no Upcoming entries while the one completed record remains persisted.
- Generic arm64 iOS Simulator build-for-testing compiles app and UI tests without booting a simulator.

## Canonical UI gate

`TskUpcomingUITests.testFutureDateRolesShareTaskIdentityAndActionsAcrossDayGroups` captures empty Upcoming, creates both dates through native editors using an isolated test clock, relaunches with a prior reference day to make the stored dates future, verifies two roles with the same UUID on one day, reschedules planning to another future day through the shared editor, verifies two day groups and retained identity, relaunches to check durable groups, and completes one row to remove both appearances. A final relaunch verifies exactly one completed task. Screenshot checkpoints are attached.

The parent prohibited simulator boots on this disk-constrained host. Canonical XCUITest execution, physical native-picker ergonomics, iPad appearance, and matching before/after screenshots remain unverified locally. The local UI report lists missing captures explicitly at `/tmp/tsk-issue-3/issue-11-ui-report.html`. It contains no screenshots and has not been visually inspected; the prior ticket's computer-use viewer attempt timed out, so no new browser was started for this ticket.
