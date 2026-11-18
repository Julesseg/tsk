# Retired: Import-only Apple Reminders integration

Retired by explicit user decision on 2026-11-18. Apple Reminders import is removed in full, including one-time copy, continuous move and recurring-reminder conversion. Existing tasks are retained; Calendar display remains supported. The text below records the historical decision.

tsk integrates with Apple Reminders through a one-time or continuous import of incomplete reminders from selected lists, mapping each list to a Taskwarrior project. One-time import copies reminders and leaves the originals untouched; continuous import moves them into tsk and removes the imported source reminders. The user chose removal during continuous import instead of retaining provenance or processed IDs, so no import bookkeeping or source-derived task identity is retained. Tasks are subsequently managed independently, with no export or two-way synchronization. Completed reminders are excluded; no priority or importance criterion is applied.

Because source and destination are separate stores, commit the task durably locally before deleting the reminder. Preserve the source on deletion failure. The user accepts possible duplicates after interrupted moves or retries in exchange for no retained bookkeeping. Run continuous import on one designated device, disabled on others, to reduce concurrent imports.
