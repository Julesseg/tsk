# Planned days, deadlines, and Today verification

`TaskManager.tasks(query: .today)` uses the injected clock and calendar to include raw pending tasks whose `scheduled` or `due` timestamp is before the end of the current local day. This includes carried-forward planned tasks and prior-day deadlines, and retains matching waiting/blocked tasks. Recurring templates and completed tasks are excluded. Start state alone does not add membership. Local date boundaries use calendar intervals, including the 23-hour Paris DST day.

The native editor independently adds, changes, and removes `scheduled` and `due`. Existing raw values remain untouched until explicitly edited. Unrecognized dates are displayed rather than silently replaced. Deadline editing includes a time picker; planning writes the selected local day's midnight. Save patches preserve identity, start state, and unfamiliar fields. Today updates immediately after save or completion, on returning to the foreground, and on iOS significant-time-change notifications.

## Verified locally

- Core suite: 11 tests at the ticket base, including ordinary capture/edit/completion tests and three planning tests covering local day boundaries, DST, carry-forward, rescheduling/completion membership, and independent date writes/removal.
- Actual host TaskChampion SQLite plus Taskwarrior 3.5.0: native save/reopen, separate ISO export of scheduled/due, unchanged start/opaque attributes/UUID, future rescheduling removal, due-date reinclusion, and completion removal.
- Generic arm64 iOS Simulator build-for-testing compiles native UI and XCUITest without booting a simulator.

## Added canonical UI gate

`TskPlanningUITests.testIndependentDatesCarryForwardRescheduleAndCompleteInToday` creates through native editors, relaunches with the following day's test clock, verifies carry-forward, reschedules while an old deadline keeps membership, clears that deadline to remove membership, replans, completes through the list, and checks durable removal after relaunch. UI screenshots are attached at the key states.

No new simulator was booted on this disk-constrained host. The initial generic all-architecture build reached native/UI compilation but failed because the locally reused Rust library contains arm64 only; the targeted arm64 build-for-testing is the valid local gate. Canonical CI executes the suite. Physical picker ergonomics, foreground midnight notification delivery, iPad appearance, and matching before/after screenshot comparisons remain unverified locally. The local UI report explicitly lists missing captures at `/tmp/tsk-issue-3/issue-10-ui-report.html`.
