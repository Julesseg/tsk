# tsk

Shared language for managing Taskwarrior tasks through tsk.

## Language

**Task**:
A piece of work tracked in Taskwarrior and managed through tsk.
_Avoid_: Reminder as a synonym for a Taskwarrior task

**Task view**:
A presentation of a selected set of tasks for a particular task-management purpose.

**Day page**:
A task view centered on one calendar day, showing its work, retained completion history, and calendar events. Tasks can be untimed or timed, with manual order within the day's date and time constraints.

**Planner date**:
The date supplied by Scheduled when present, otherwise by Deadline, that places a task in the planner before carryover is considered.

**Carryover**:
Unfinished work with an earlier planner date that appears on Today until completed or explicitly rescheduled. Its original date and time remain unchanged.

**Inbox**:
The task view of unfinished tasks with neither a Scheduled date nor a project. A Deadline alone does not exclude a task from Inbox.

**Taskwarrior filter**:
An expression that selects tasks according to Taskwarrior's filtering language.

**Scheduled**:
The date, with an optional time, on which the user intends to work on a task, distinct from its deadline and any waiting constraint. An explicit midnight time is distinct from a date without a time.
_Avoid_: Planned day; Deadline as a synonym for Scheduled

**Deadline**:
The date or time by which a task must be finished.
_Avoid_: Scheduled as a synonym for deadline

**Today**:
The day page for the current day, including carryover, the day's work and retained completion history, and calendar events.

**Annotation**:
A timestamped note attached to a task.
_Avoid_: Description as a synonym for annotation

**User-defined attribute**:
An additional task field beyond Taskwarrior's standard attributes.
_Avoid_: Tag as a synonym for user-defined attribute

**Task draft**:
A task being prepared for the user to review and edit before saving.

**Recurring template**:
The task that defines a recurring series and tracks its generated occurrences. It is distinct from the individual tasks the user completes.
_Avoid_: Occurrence as a synonym for recurring template

**Occurrence**:
An individual task generated from a recurring template for a particular due date.
_Avoid_: Recurring template as a synonym for occurrence
