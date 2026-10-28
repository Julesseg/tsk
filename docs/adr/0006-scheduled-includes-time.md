# Scheduled includes time throughout tsk

Scheduled will express an intended work date and time throughout tsk, including task editors, date displays, Shortcuts, and URL actions. This supersedes [ADR 0003](0003-share-taskwarrior-planning-and-deadline-fields.md)'s day-only presentation while retaining Taskwarrior's `scheduled` attribute and the distinction from Deadline and Waiting until. Consistent time support lets users express when they intend to work without silently discarding time when editing; the label-only rename in [PR #61](https://github.com/Julesseg/tsk/pull/61) does not deliver this semantic change.

Preserve existing timestamps and display their time, including midnight, without inferring replacement times or changing the storage format. Today still includes all unfinished work scheduled for today or earlier, including times later today; Upcoming remains grouped by local calendar day and ordered by actual timestamps. Waiting until remains a separate constraint.

Existing notification preferences remain effective, including the configurable default-time substitution for midnight alerts; other Scheduled times retain their specified alert time. Implementation and the required iPhone/iPad evidence are tracked in [#64](https://github.com/Julesseg/tsk/issues/64).
