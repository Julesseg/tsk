# Relative dates and virtual tags (#17)

TaskManager evaluates relative date predicates and virtual tags through the
existing raw-expression/saved-view seam. It preserves raw attribute bytes and
UUIDs, and supplies the complete replica for dependency and schema context.
Snapshots publish the next relevant clock boundary. The native app rearms a
foreground timer and reloads on significant-time changes and foreground entry.
The raw editor has a safe-area keyboard dismissal action and visible errors.

Verified locally:

- Core test-first failures demonstrated missing date evaluation, missing clock
  boundaries and status/wait refresh metadata before implementation.
- Core tests cover deadline/planned separation, local DST midnight, invalid
  operands, wait/schedule boundaries, prerequisite completion and unsigned raw
  date overflow saturation without rewriting stored values.
- Actual TaskChampion 3.1.0 storage reopens the same saved temporal definition,
  recomputes results after prerequisite completion and next-day reopening,
  and retains unfamiliar and canonically equivalent UTF-8 raw keys.
- The pinned Taskwarrior 3.5.0 fixture compares UUID selections for named dates,
  period boundaries, informal times, ISO ordinal/week dates, relative duration
  expressions, date modifiers and virtual tags including UDA/ORPHAN.
  An argv array passes through Python to retain exact Unicode bytes on Darwin.
- The full real-adapter suite includes real encrypted synchronization and
  independently reopened participants; no persistence substitute is used.

Pinned-source details checked by the fixture include Monday-based named week
boundaries despite Sunday week numbering, source-exact midsummer weekday
subtraction and plain +ACTIVE working-set selection. Invalid 24:00 date-filter
operands are rejected explicitly: the CLI does not select the equivalent next
midnight, even though its UDA setter accepts that separate spelling.

TemporalFilterUITests covers native task capture with a deadline, saving
`due:today and +READY`, visible keyboard dismissal, reopening the saved
expression under an advanced injected clock, returning to the original day,
and completing its result. It attaches populated/empty/completed screenshots
when run by the canonical iPhone XCUITest lane. Existing iPad custom-view tests
exercise the same editor and shared query in the adaptive workspace.

Local simulator execution and before/after screenshots were not captured:
disk-constrained shared Mac, with no simulator boot authorized for this slice.
The signed generic arm64 simulator build compiles App and XCUITest; UI execution,
iPhone/iPad rendering, hardware keyboard behavior and real wall-clock wakeup
remain canonical CI/device checks. No personal account infrastructure is used.
