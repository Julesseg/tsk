# Product direction

This brief records the product choices accepted during the design interview. It describes intended behavior; the repository currently contains the app scaffold, not these features.

## Purpose and audience

tsk is a first-class iOS Taskwarrior client with TaskChampion as its intended backend. Its distinguishing characteristic is its Taskwarrior foundation, combined with a modern interface and integration with the rest of iOS.

The initial reference user is an existing Taskwarrior user whose terminal workflow continues alongside tsk. Everyday actions should remain understandable without Taskwarrior knowledge.

## Primary workflow

Optimize for capture, choosing what to do next, and completing or rescheduling tasks. Task views should support decisions and allow actions directly from the list.

Provide predefined views inspired by Things 3, including Today, Upcoming, and views by project. Allow custom views defined using Taskwarrior filters.

Keep planned work dates separate from deadlines. The planned day uses Taskwarrior's `scheduled` attribute; the deadline uses `due`.

Today includes tasks planned for today, unfinished tasks planned for earlier days, and tasks due today or overdue. Unfinished planned tasks remain until completed or rescheduled. Waiting or blocked tasks that meet these criteria remain visible with their reason.

Upcoming groups future planned work and future deadlines by day, clearly labeling planned dates versus deadlines. A task with different planned and deadline dates may appear on both dates.

Custom views accept Taskwarrior filter expressions entered in tsk. Use documented Taskwarrior defaults, with user-defined attribute types configurable locally in tsk. Report invalid or unsupported expressions clearly; Taskwarrior filter compatibility remains the requirement. Saved view definitions stay device-local; they do not synchronize between iPhone and iPad. Importing desktop reports, contexts, or `.taskrc` configuration is not planned.

## Task editing

Support editing description, project, tags, priority, annotations, planned date, deadline, waiting date, and dependencies, plus starting and stopping work. Include an advanced editor for user-defined attributes and preserve unfamiliar fields.

## Offline use and synchronization

Creating, editing, completing, and viewing tasks work locally without a connection. Synchronize with the configured TaskChampion server as soon as possible; prompt server synchronization is a priority, not a manual-only workflow.

Attempt synchronization after changes, when the app opens, and when connectivity returns. Provide visible sync status and retry. Sync promptly while active and use available background opportunities; receiving remote changes while the app is closed is best effort because iOS controls background execution.

## iOS integration

Shortcuts and Siri, capture from the share sheet, widgets, Spotlight search, notifications, Calendar, and Apple Reminders import are all important parts of the initial product scope.

Apple Reminders integration is import-only: a one-time or continuous import of incomplete reminders from selected lists. Users choose which lists to import. Each selected Reminders list becomes the Taskwarrior project for its imported tasks. Completed reminders are excluded. There is no additional priority or importance criterion.

One-time import is for switching apps: copy eligible reminders into tsk and leave the originals in Apple Reminders. Continuous import moves eligible reminders into tsk and removes the imported reminders from Apple Reminders. The two modes deliberately differ in source deletion.

After import, manage the task independently in tsk. Export and two-way synchronization are outside the agreed scope. Do not retain provenance, processed reminder IDs, source-derived task identifiers, or import bookkeeping. Selected list configuration and its project mapping remain necessary for operating import.

Save the task durably in local storage before deleting its source reminder. If source deletion fails, preserve the reminder; an interrupted move or later retry can create a duplicate. The user accepts this occasional duplication in exchange for retaining no bookkeeping. Continuous import runs on one designated device and stays disabled on others; task synchronization still reaches every client. See [the integration boundary decision](adr/0001-import-only-apple-reminders.md).

Convert recurring Apple reminders into Taskwarrior templates only for verified supported recurrence rules. Skip unsupported or unverified rules, leave the source reminder untouched, and explain why. Do not silently flatten a recurring reminder or approximate its rule. In continuous mode, remove the source only after durably saving a valid replacement. Supported conversions require interoperability tests against the external generator; matching frequency labels alone does not establish compatibility. See [the mapping research](research/reminders-recurrence-mapping.md).

Calendar integration only displays calendar events in Today. tsk does not create calendar events or time blocks.

Shortcuts and Siri support creating, finding, completing, and rescheduling tasks. Widgets show Today or a chosen task view and provide completion actions. Spotlight opens matching tasks in tsk.

Sharing text or a URL into tsk opens an editable task draft before saving, preserving shared text and links with quick access to project, tags, and dates. File attachment storage is deferred initially.

Notifications are based on scheduled or deadline times. A separate opt-in reminder time per task is not the agreed behavior. Different scheduled and deadline times each produce a notification, distinguished as planned versus due; coincident times produce one combined notification. Completion or deletion cancels pending notifications once known locally.

Provide a settings option to use a configurable default notification time when a date has the default midnight time. Start enabled at 09:00 in the device's current time zone, with options to change the time or disable the replacement. Other timestamps retain their specified times. This changes notification timing, not the stored task date. Taskwarrior does not retain whether midnight was explicit, so the setting is a convention rather than reliable detection of time-free input. Notification preferences remain device-specific.

After synchronization, immediately fire newly discovered missed alerts for unfinished tasks. Evaluate the final synchronized task state first: if the same sync reveals completion, do not fire its missed alert. Completion or deletion suppresses task alerts. An already delivered event is not newly discovered on every subsequent sync.

## Devices

iPhone leads the everyday capture-and-action workflow. iPad receives an adaptive layout and keyboard support at launch. A dedicated Mac experience is a later decision.

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

Optional iOS recurrence generation and file attachment storage are deferred. A dedicated Mac experience is a later decision. Desktop configuration import, saved-view synchronization, calendar event creation, and export or two-way synchronization with Apple Reminders are outside the agreed scope.

Before implementation can claim interoperability, select and pin supported Taskwarrior and TaskChampion versions, verify the Swift integration route, and test filter behavior, template editing, occurrence completion bookkeeping, and supported Reminders conversions. Verify notification delivery, midnight-time replacement, sync reconciliation, and background behavior on iOS. Source-based feasibility research is not evidence that those capabilities already work.
