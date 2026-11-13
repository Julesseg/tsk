# Planner evaluation

Interview updated 2026-11-13. These are accepted workflow preferences and open decisions for evaluating a new direction. A backend replacement or rebuild has not been selected.

## Accepted preferences

- Prioritize a satisfying daily planning workflow. Adopting an existing app and ending this project is an acceptable outcome.
- Revisit Sorted³ as a candidate. The reason for leaving it is no longer remembered; a trial should establish whether it still fits.
- Center the experience on navigable day pages, manual task ordering, calendar visibility, optional task times, and easy rescheduling. Durations, time blocks, and automatic scheduling are not core requirements.
- Keep unfinished work from earlier days visible on Today. Automatically changing its Scheduled date is acceptable but unnecessary.
- Treat Scheduled as the primary date: when the user intends to work on a task. Managing a separate Deadline is not a core requirement; whether to retain an optional Deadline remains open.
- Optimize everyday use for iPhone and Mac. The essential Mac keyboard workflow is quick capture through Tuna. Keyboard-driven scheduling, project assignment, and notes editing are useful extras and may be handled in the desktop app. A full task-management CLI is not required.
- Preserve interoperability for custom quick capture on both platforms.
- Few Taskwarrior-specific features are used. Preserving Taskwarrior for its own sake is not a requirement.
- The current dependency on an always-on computer for Taskwarrior recurrence generation is acceptable. This does not establish how recurrence would transfer to another app.
- Migrate the complete working set for the trial, including undated and waiting tasks and recurring series with their unfinished occurrences. Retain completed and deleted history in a preserved Taskwarrior archive. Avoid duplicating generated occurrences when transferring recurring series.
- Map an existing task's date to the earlier of Scheduled and Deadline when both exist. Use the sole value when only one exists; leave undated tasks undated. Preserve both original values in the migration archive.
- Evaluate capture on both devices, synchronization and recurrence reliability, day ordering and rescheduling, and visibility of unfinished work. Allow up to two weeks, ending earlier when normal use provides enough evidence. Record concrete friction and reasons to reach for Taskwarrior.
- Use Sorted as the sole everyday editor during the trial. Preserve Taskwarrior for recovery and reconcile changes made during the trial if returning; restoring the initial export alone is insufficient.

## Open decisions

- Migration route, supported fields, recurrence fidelity, verification, and recovery of changes if the trial ends.
- Placement of undated work, completed-task history on day pages, and presentation of carried work, if tsk is redesigned.
- Whether to adopt Sorted³, evolve tsk over Taskwarrior, or choose a different backend after the trial.

## Relation to existing decisions

The [product direction](product-direction.md) and accepted ADRs describe the existing Taskwarrior client. This evaluation reopens its Taskwarrior-first purpose and the requirement to expose separate Scheduled and Deadline dates. A Reminders backend would also reopen [ADR 0001](adr/0001-import-only-apple-reminders.md); [ADR 0003](adr/0003-share-taskwarrior-planning-and-deadline-fields.md) and [ADR 0006](adr/0006-scheduled-includes-time.md) record the existing date choices. Supporting an everyday Mac workflow does not yet select a native tsk Mac app or supersede [ADR 0007](adr/0007-iphone-only.md).

Record a replacement architectural decision when the trade-off is settled. The trial itself is reversible and does not require an ADR.

## Sorted³ documentation check

Checked 2026-11-13. The official [URL scheme guide](https://www.sortedapp.com/blog/url-scheme) documents opening views and adding tasks with a title, date, list, and tags. It does not document task retrieval, editing or completion by identifier, recurrence input, notes input, or a bulk migration format. Scripted capture is therefore a candidate; a full task-management CLI is unverified and is not required for this trial.

The [App Store listing](https://apps.apple.com/us/app/sorted-calendar-notes-tasks/id1306893526) advertises recurrence, iCloud sync, backups, and Shortcut Actions. These feature claims do not establish import/export fidelity. The official support center returned HTTP 410 during this check; a documented route preserving all tasks and a usable migration-out route were not established. Inspect the installed app and validate representative transfers before committing the active task set.

[Tuna custom scripts](https://tunaformac.com/docs/custom-scripts-and-script-directories) can receive user text as arguments or standard input through Run with Input or Send to Script. A script can encode the title and open Sorted's documented Add URL. [Smart Links](https://tunaformac.com/docs/smart-links) provide encoded input templates, but custom-scheme handling is not explicitly guaranteed by that documentation. Both approaches require checking the installed Mac apps, including whether capture saves immediately and how it affects focus.

## Migration investigation

Preserve a complete source backup and inventory before any transfer. The user requested a single import command without a mandatory sample/check sequence. Validation and retry tracking run automatically, while destination saving and recovery remain explicit verification limits. No tasks have been migrated during this interview.

The [migration tool](sorted-migration.md) prepares a private source archive and one-command direct URL importer. Projects map to lists and tags pass through. Notes, repeat rules and unsupported fields are preserved in an actionable sidecar report. Reminders are not required. This route does not provide a durable-save acknowledgement or an automatic reverse migration.
