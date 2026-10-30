# Share Taskwarrior planning and deadline fields

tsk stores the user's Scheduled date and time in Taskwarrior's `scheduled` attribute and the deadline in `due`. We chose these existing fields over separate tsk-only planning metadata so that planning through tsk remains meaningful to the terminal workflow, while keeping intended work distinct from a deadline. Taskwarrior interprets `scheduled` as the earliest opportunity to work; tsk originally presented it as the planned day. Today and Upcoming rules are recorded in [the product brief](../product-direction.md). See [the date-semantics research](../research/filters-and-reminders-feasibility.md).

[ADR 0006](0006-scheduled-includes-time.md) supersedes the day-only presentation with Scheduled date and time. The `scheduled` and `due` field mappings remain unchanged.
