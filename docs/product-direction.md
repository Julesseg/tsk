# Product direction

This brief records the product choices accepted during the design interviews. It describes intended behavior; implementation and runtime verification are tracked separately.

The accepted [daily planner redesign](planner-redesign.md) retains Taskwarrior and supersedes conflicting navigation, date placement, ordering, calendar, and completion-history details below. It records intended behavior, not implementation.

The [PRD](prd.md) expands this direction into user stories, implementation decisions, testing decisions, and explicit exclusions.

## Purpose and audience

tsk is a first-class iOS Taskwarrior client with TaskChampion as its intended backend. Its distinguishing characteristic is its Taskwarrior foundation, combined with a modern interface and integration with the rest of iOS.

The initial reference user is an existing Taskwarrior user whose terminal workflow continues alongside tsk. Everyday actions should remain understandable without Taskwarrior knowledge.

## Primary workflow

Optimize for capture, choosing what to do next, and completing or rescheduling tasks. Task views should support decisions and allow actions directly from the list.

Provide predefined views inspired by Things 3, including Today, Upcoming, and views by project. Allow custom views defined using Taskwarrior filters.

Keep Scheduled separate from Deadline. Scheduled is the intended work date and time and uses Taskwarrior's `scheduled` attribute; Deadline uses `due`. Preserve existing Scheduled timestamps, including midnight, and support time selection and display throughout the app. See [the Scheduled decision](adr/0006-scheduled-includes-time.md), with implementation tracked in [#64](https://github.com/Julesseg/tsk/issues/64).

Today includes unfinished tasks scheduled for any time today, unfinished tasks scheduled for earlier days, and tasks due today or overdue. A task scheduled for later today is already visible; unfinished scheduled tasks remain until completed or rescheduled.

Upcoming groups future scheduled work and future deadlines by local calendar day, orders entries by their actual timestamps, and clearly distinguishes Scheduled from Deadline. A task with different Scheduled and Deadline dates may appear on both dates.

Custom views accept Taskwarrior filter expressions entered in tsk. Use documented Taskwarrior defaults for built-in task fields. Local custom-attribute editors and definition management are out of scope. Report invalid or unsupported expressions clearly; Taskwarrior filter compatibility remains the requirement. Saved view definitions stay device-local; they do not synchronize between devices. Importing desktop reports, contexts, or `.taskrc` configuration is not planned.

## Task editing

Support editing description, project, tags, priority, annotations, Scheduled and Deadline in the expanded row. Tap outside the row to save valid edits. Preserve Taskwarrior attributes such as `wait` and `start` when editing other fields.

## Offline use and synchronization

Creating, editing, completing, and viewing tasks work locally without a connection. Synchronize with the configured TaskChampion server as soon as possible; prompt server synchronization is a priority, not a manual-only workflow.

Attempt synchronization after changes, when the app opens, and when connectivity returns. Provide visible sync status and retry. Sync promptly while active and use available background opportunities; receiving remote changes while the app is closed is best effort because iOS controls background execution.

## iOS integration

Shortcuts, Siri and Calendar remain in scope. Apple Reminders import was removed by explicit user decision on 2026-11-18; existing saved tasks are retained. [ADR 0001](adr/0001-import-only-apple-reminders.md) records the retired design.

Calendar integration only displays calendar events in Today. tsk does not create calendar events or time blocks.

Shortcuts and the URL scheme will expose Add Task, Modify Task, Delete Task, Find Tasks, Complete Task, Open Task, and Open View using individual named inputs rather than Taskwarrior syntax. Simple URLs have no version component; task-targeted actions use full UUIDs, and mutations save immediately and acknowledge durable local storage. Existing saved shortcuts may break when the actions are rebuilt; Modify covers rescheduling without a legacy Reschedule action. See [the shared-action decision](adr/0005-structured-actions-for-urls-and-shortcuts.md) and its implementation tickets.


Incoming system sharing was removed from product scope on 2026-11-17. A future sharing design will be specified separately.




## Devices

tsk supports iPhone only. Native iPad layouts and distribution targets are retired under [ADR 0007](adr/0007-iphone-only.md). External keyboard commands and widgets were removed from product scope on 2026-11-17. Native iPad and Mac experiences are future product decisions.

## Visual direction

Follow native iOS interaction conventions and use the Liquid Glass design language. Maintain a distinctive, restrained identity and task lists that are compact enough to scan, with detail available when needed.

## Recurrence

Initial scope includes creating and editing Taskwarrior-compatible recurring templates in tsk. Occurrence generation remains on one designated external Taskwarrior client. TaskChampion synchronizes task data and does not execute recurrence rules.

Source inspection supports creating compatible templates without an iOS generator. tsk must perform appropriate validation and recurrence bookkeeping rather than assume that generic TaskChampion property writes execute Taskwarrior command behavior. See [the recurrence-control research](research/recurrence-control-from-ios.md).

Distinguish editing one occurrence from editing its series. Template changes affect future unfinished occurrences while preserving completed history. Frequency or schedule changes have an effective date, and the UI clearly shows which unfinished occurrences will change. Implement compatible series bookkeeping rather than just overwriting template properties.

The external generator must regularly receive changes, run a generation-triggering command, and synchronize generated occurrences back. tsk must preserve recurrence information when managing existing tasks. If the generator stops, no new occurrences arrive beyond those already generated. Exact completion interoperability still requires implementation and verification. See [the recurrence decision](adr/0002-defer-independent-recurrence.md) and [the feasibility research](research/recurrence-feasibility.md).

Optional iOS generation is a later, lower-priority capability. [Source-based research](research/optional-ios-recurrence-generation.md) supports an explicit single-generator option in principle, with foreground catch-up and pre-generation, while iOS background execution remains opportunistic. No generator implementation route has been built or tested; this capability is excluded from the initial scope.

Everyday task management works offline as described above; generation of new recurring occurrences depends on the designated external generator.

## Deferred scope and verification

Optional iOS recurrence generation and file attachment storage are deferred. A dedicated Mac experience is a later decision. Desktop configuration import, saved-view synchronization, calendar event creation, and Apple Reminders integration are outside the agreed scope.

Before implementation can claim interoperability, select and pin supported Taskwarrior and TaskChampion versions, verify the Swift integration route, and test filter behavior, template editing, occurrence completion bookkeeping. Verify sync reconciliation and background behavior on iOS. Source-based feasibility research is not evidence that those capabilities already work.

The iPhone schedules title-only, Time Sensitive notifications for future timed Scheduled dates and deadlines. Spotlight indexing remains outside product scope.
