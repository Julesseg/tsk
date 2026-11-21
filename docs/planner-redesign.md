# Daily planner redesign

Accepted design, 2026-11-15. This records the completed design interview, not delivered or runtime-verified behavior.

## Direction and scope

Evolve tsk into an opinionated daily planner inspired by Sorted³ while retaining Taskwarrior, TaskChampion storage and synchronization, and the existing external recurrence generator. The core value is day pages, manual ordering, optional times, calendar context, carryover, and quick rescheduling. Durations, time blocks, and automatic scheduling are outside this direction.

The app remains an iPhone app. The existing Mac CLI and Tuna capture workflow remain useful; this design does not select a native Mac app. Preserve existing task editing, integrations, and offline/sync behavior unless explicitly replaced below.

## Planner placement

Each unfinished task has at most one actionable planner placement:

- When Scheduled exists, it determines the day, even when Deadline is earlier or overdue.
- Otherwise, Deadline supplies the fallback placement and appears in the Deadline column.
- With neither date, the task has no planner placement.

Deadline remains independent and appears in the expanded row. It does not create a second planner entry when Scheduled exists. Planner scheduling always writes Scheduled and leaves Deadline untouched.

Unfinished untimed Scheduled tasks roll forward to Today when the app refreshes the planner. This writes today as their Scheduled day without a time. Untimed Scheduled dates must be today or later. Timed Scheduled and Deadline-only tasks carry forward in the list with their original timestamps.

Scheduled supports a date without a time and a date with an explicit time, including 00:00. These are distinct intentions. For legacy or external timestamps without precision metadata, interpret midnight as untimed and other clock times as timed; preserve the underlying timestamp. Supporting explicit midnight prospectively requires additional task metadata alongside the existing Taskwarrior date field. See [ADR 0008](adr/0008-preserve-planner-date-intent.md).

## Day page and ordering

The task list is continuous, without section headers or separators. Its order is:

1. Carried timed Scheduled tasks, ordered by original date and time.
2. Deadline-only tasks, ordered by Deadline.
3. Untimed Scheduled tasks for the displayed day, in manual order. Rolled-over tasks append to this group.
4. Timed Scheduled tasks for the displayed day, ordered by time. Manual order breaks ties among equal times.

The scheduled time sits at the far left of the row, before the checkmark. Carried timed tasks show their original date and time in red. Untimed Scheduled tasks have a dash in the leading slot.

Manually ordering tasks must not invent clock times. Incoming untimed tasks append to the untimed portion; incoming timed tasks enter chronological position after existing tasks at the same time. Preserve the relative order of an incoming batch and the existing destination tasks.

## Dragging

Long press followed by movement starts native iOS dragging. Other rows move visually to make room during the gesture. Touching the Scheduled slot selects a task immediately. Sweeping up or down extends selection across other rows. Dragging a selected task by its title moves the selected tasks as a block in their relative order.

Crossing another row in either direction records its effective Scheduled value. The last row crossed determines the value applied to all dragged tasks when dropped:

| Last row crossed | Scheduled assigned on drop |
| --- | --- |
| Carried-over task | Its original timed Scheduled date |
| Untimed task on the displayed day | The displayed day without a time |
| Timed task | Its date and time |
| Deadline-only task | Its displayed fallback date and time or untimed intent |
| Timed calendar event | Its start date and time |

Crossing determines inheritance, rather than merely which row is adjacent at drop. Track the prospective value during the gesture; persist date changes only once, on drop. Deadline never changes. Native visual movement is not an intermediate date save. A successful drop has no Back or Undo action; a failed save must preserve the original task data.

Dragging within a project changes manual order only and does not inherit Scheduled values.

## Navigation and calendar scheduling

The top toolbar links directly to Inbox and Projects, with a Today button outside the planner. A compact glass date pill overlays the planner list and expands into a month calendar. Saved and favorite views and the Views menu are retired. The pill always offers a reliable swipe area for moving between days, including when task rows fill the page. Day-page swipes can also move between dates while preserving row swipe actions. Disable day-to-day swiping on both the pill and page during selection mode.

Swipe across the expanded calendar to browse months. Hold the collapsed date pill to return to Today. With no tasks selected, tapping a calendar date navigates to that day. With tasks selected, tapping today or a later date immediately sets Scheduled to that day without a time. The separate bulk Scheduled and Deadline pickers can each set a date with or without a time.

After a successful calendar scheduling action, close the calendar and clear selection. Tasks disappear from the current day or Inbox when they no longer match it. Project members remain in their project because scheduling does not change project membership. There is no Apply confirmation or Undo after successful calendar scheduling. A failed save retains the tasks and selection.

## Inbox, projects, and capture

Inbox contains unfinished tasks with both no Scheduled date and no project. Deadline alone does not exclude a task: a deadline-only orphan can appear in Inbox as well as on its fallback planner day. Unscheduled project tasks stay in their project as lists; scheduled tasks without projects stay in the planner. Neither belongs in Inbox.

Project views show all unfinished members, including scheduled tasks.

| Capture context | Default Scheduled | Default project |
| --- | --- | --- |
| Today or future day page | Displayed day, untimed | None |
| Past day page | None | None |
| Project | None | Current project |
| Inbox or external quick capture | None | None |

Explicit capture inputs override these defaults. External capture must not inherit whichever page happened to be open. Preserve interoperability for custom capture methods on iPhone and Mac, especially Tuna keyboard capture.

## Calendar events

Display calendar events for the chosen day in a compact strip above the tasks in the same scrolling list. All-day events appear first, followed by timed events on a horizontal hour ruler and compact rows for events outside the configured hours. Calendar Settings controls the hour range and calendar visibility.

Dragging a task onto a timed event uses the event’s start as Scheduled. All-day events are display-only. Calendar access remains read-only.

## Completion history

Completed tasks stay checked and dimmed, preserving order on the planner page they occupied when completed. A Monday task carried into Wednesday and completed there stays on Wednesday. A Friday task completed early stays on Friday. This is history of the occupied planner page, not grouping strictly by the actual completion date. Completing a task does not rewrite Scheduled.

## Retired notifications

Notifications were removed from product scope on 2026-11-17. Planner date placement and stored task dates remain independent of alerts.

## Acceptance examples

| Situation | Expected result |
| --- | --- |
| Scheduled next Monday, Deadline last Friday | One planner entry on Monday; Deadline remains available in the expanded row |
| Only Deadline Friday at 14:00; calendar scheduling to Monday | Scheduled becomes Monday without a time. Deadline stays Friday at 14:00 |
| Drag across a timed task, then an untimed task, and drop | Save the untimed task's day without a time |
| Drag across an overdue task last | Copy its original overdue Scheduled value; the dragged task can become carried-over |
| Several selected tasks are dragged across one timed row | All receive that row's Scheduled date and time on drop, preserving their relative order |
| Deadline-only task without a project | Visible in Inbox and on its fallback planner day |
| Yesterday's untimed task is unfinished at midnight | Appears on Today with yesterday's date; no automatic date rewrite |
| Explicit midnight versus a date without time | Midnight is timed and can alert; the untimed task has no individual Scheduled alert |

## Implementation boundary

The product rules are settled; no planner implementation is included in this design work. Engineering still needs to choose the precision metadata format, persistence and synchronization of manual order, and storage for completion-page history. Those choices must preserve these rules and external Taskwarrior interoperability. They are not selected implicitly by this brief.

This brief supersedes conflicting navigation, planner placement, ordering, calendar display, completion-history rules in the [original product direction](product-direction.md) and [PRD](prd.md). [ADR 0008](adr/0008-preserve-planner-date-intent.md) records the change from the date semantics in ADR 0006. Other existing capabilities remain the baseline.
