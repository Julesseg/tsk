# tsk

Shared language for managing Taskwarrior tasks through tsk.

## Language

**Task**:
A piece of work tracked in Taskwarrior and managed through tsk.
_Avoid_: Reminder as a synonym for a Taskwarrior task

**Task view**:
A presentation of a selected set of tasks for a particular task-management purpose.

**Predefined view**:
A task view supplied by tsk, such as Today, Upcoming, or a view by project.

**Custom view**:
A task view defined by the user's Taskwarrior filter.

**Favorite view**:
A task view chosen by the user for quick access. Other task views remain available without becoming favorites.

**Taskwarrior filter**:
An expression that selects tasks according to Taskwarrior's filtering language.

**Imported task**:
A task created in tsk from an Apple reminder.

**Scheduled**:
An organizational date expressing the day on which the user intends to work on a task, distinct from its deadline.
_Avoid_: Deadline or planned day as the interface label for Scheduled

**Deadline**:
The date or time by which a task must be finished.
_Avoid_: Scheduled as a synonym for deadline

**Continuous import**:
Repeatedly moving eligible reminders from selected Apple Reminders lists into tsk and removing the imported source reminders. Imported tasks are subsequently managed independently.
_Avoid_: Two-way synchronization

**One-time import**:
Copying eligible reminders from selected Apple Reminders lists into tsk once, leaving the originals in Apple Reminders.

**Today**:
The predefined view of unfinished tasks planned for today or an earlier day, or due today or overdue, alongside today's calendar events. Matching waiting or blocked tasks remain visible with their reason.

**Upcoming**:
The predefined view of future planned work and deadlines grouped by day, with planned dates and deadlines distinguished.

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
