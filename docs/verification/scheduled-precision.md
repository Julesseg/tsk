# Scheduled date precision

Issue #103 implements the date-intent portion of ADR 0008 in the existing
capture and editing interfaces. Planner placement and navigation are separate
slices of spec #102.

Scheduled remains Taskwarrior's `scheduled` timestamp in epoch seconds;
Deadline remains `due`. The additional string attribute
`tsk_scheduled_precision` carries `v1:<scheduled epoch seconds>:timed` or
`v1:<scheduled epoch seconds>:untimed`. For example,
`v1:1792195200:timed` distinguishes explicit midnight UTC on 17 October 2026
from the same timestamp without a chosen time. TaskChampion stores the string
alongside ordinary task attributes, and encrypted synchronization carries it
without a backend migration. A Taskwarrior client that wants to display or edit
the hint can declare `uda.tsk_scheduled_precision.type=string`; clients can
continue using the ordinary Scheduled and Deadline fields independently.

Core exposes `TaskRecord.scheduled(calendar:)` and the corresponding draft read,
returning a `TaskScheduledDate` containing the original date and `hasTime`.
`TaskDraft.setScheduled(_:)` writes the timestamp and its precision together,
or removes both. Capture and editor time controls use this operation. Day
shortcuts retain the chosen time precision as they move the date. The existing
`plannedDate` accessor remains available for timestamp-only callers; assigning
it clears a previous precision hint. Opening a task or editing unrelated fields
does not backfill metadata, normalize its timestamp, or discard unknown fields.

A hint is authoritative only when its version, timestamp and precision match
the currently stored Scheduled value. Missing, malformed, unknown-version or
stale hints fall back to the existing timestamp interpreted in the supplied
calendar (the current device calendar in the app): exact local midnight means
untimed, any other clock time means timed. Reading this fallback never rewrites
the timestamp or deletes the hint. An external timestamp change therefore
invalidates old precision, including hints inherited by externally generated
recurrences. Editing precision in tsk establishes a new bound hint. During row
rebasing, unsaved Scheduled and precision edits stay paired while unrelated
fresh attributes are retained.

This timestamp binding detects external date changes, not the identity of the
writer. A client that edits the timestamp and later restores the exact bound
value can reactivate the old hint. A client that intentionally changes precision
at the same timestamp must update or remove the hint. This is a compatibility
tradeoff: no external client hooks, generation engine or migration are required.

Untimed Scheduled values produce no individual Scheduled notification. Explicit
times, including midnight, use their actual timestamp and ignore the midnight
replacement preference. Deadline retains its independent existing preference;
coincident effective Scheduled and Deadline alerts combine into one request.
Completion/deletion cancellation, permission and accepted-event deduplication
continue through the existing notification reconciliation boundary.

The existing persistent-replica/Taskwarrior export test exercises explicit
midnight and untimed reopening. The existing real encrypted-sync test exercises
phone-to-Taskwarrior timestamps, a returned explicit-midnight hint, a stale hint
after an external date edit, and a returned untimed edit while preserving
Deadline, annotations and unfamiliar attributes. The existing iPhone Scheduled
journey covers timed editing, midnight selection, untimed capture and relaunch.
Adapter and policy tests do not establish OS notification delivery or external
Shortcuts invocation; canonical iPhone CI remains required.
