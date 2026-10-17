# Waiting verification

Waiting is a virtual state: a raw pending task with a valid `wait` timestamp strictly later than the current instant. The stored status remains pending. Exactly at the wait timestamp, the waiting reason expires without mutating the persisted record. Matching Today tasks remain visible based on planned dates/deadlines, including when waiting; wait alone does not change planning, deadline, or start state.

`TaskManager.availability(id:)` reads the task through the common interface and projects `TaskAvailability`. The reusable pure `TaskRecord.availability(at:)` supports local clock updates. Availability carries an array of reasons for later waiting-plus-blocked integration. `isAvailable` expresses ordinary pending state without these reasons, not Taskwarrior's full `+READY` predicate; scheduled/blocked filter semantics belong to their own slices. UI displays reasons, without a Ready badge.

The editor independently adds, changes, or clears the raw `wait` date with a native date/time picker. Deadline and waiting editing share one optional date editor; planned-day editing remains distinct. Existing malformed/raw dates remain preserved unless explicitly replaced or removed. New waiting dates default to tomorrow at the current clock time for review before saving. Saves patch only changed fields. Detail retains the waiting date even when expired; its active reason disappears. Today and Upcoming rows render the same Core waiting reason. An explicit SwiftUI timeline schedules the reason at its expiry boundary without any database query on the timer.

## Verified locally

- 18 Core tests at ticket base, including three waiting tests: strict before/exact/after boundary; Today inclusion and unchanged pending status; edit-to-future/edit-to-past/removal; preserved identity, scheduled/due/start/opaque values; malformed raw value retention; nonpending states do not become waiting or available.
- Actual TaskChampion SQLite plus installed Taskwarrior 3.5.0: native save/reopen of future wait, matching Today membership, Taskwarrior `status:waiting` exports one task with stored status pending while `status:pending` excludes it; moving wait into the past or removing it restores virtual pending selection; waiting edits do not change planning/deadline/start/opaque fields or UUID. The conformance fixture uses a freshly captured system reference time and a one-hour future wait to keep the independent CLI clock valid.
- Generic arm64 iOS Simulator build-for-testing compiles the native UI and XCUITest target without booting a simulator.

## Canonical UI gate

`TskWaitingUITests.testWaitingTaskStaysInTodayAndWaitExpiresOrClearsWithoutChangingPlanning` creates planned/due/wait through native editors, verifies the matching Today row and reason, relaunches to verify persistence and pending detail, advances the isolated clock exactly to expiry, verifies the reason disappears while the carried-forward task remains, edits wait back into the future, then clears it and verifies durable Today visibility without a waiting reason. Screenshot checkpoints are attached when the suite runs.

Canonical XCUITest execution, physical picker ergonomics, foreground expiry timeline delivery, iPad appearance, and matching before/after captures remain unverified locally. No new simulator or browser was started. The local UI report explicitly lists missing captures at `/tmp/tsk-issue-3/issue-12-ui-report.html`; it contains no screenshots and has not been visually inspected because the previous ticket's computer-use viewer attempt timed out.
