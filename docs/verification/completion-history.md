# Retained planner completion history

`TaskManager.complete(id:)`, `complete(ids:)` and coordinated selection completion
save the occupied planner page with status, end and removal of start. Occurrence
completion still saves its parent mask in the same atomic transaction. URL,
App Intent, widget and detail actions use these same operations; no originating
UI view is required. A combined date-and-completion selection uses the resulting
date intent. Undated tasks have no planner page.

## Taskwarrior representation

`tsk_completion_page` is a string UDA containing
`v1:<calendar era>:<year>:<month>:<day>`. Components use the manager's local
calendar. The page is the later of the original planner day (Scheduled, otherwise
Deadline) and Today at completion. A carried Monday task completed Wednesday
therefore keeps Wednesday; a Friday task completed Wednesday keeps Friday.
Matching calendar-date components retains that page across midnight, relaunch,
sync, and a timezone change within the same calendar. Changing calendar systems
is not a migration of this metadata.

Completion leaves Scheduled, Deadline, precision, entry and existing
`tsk_planner_order` unchanged. The existing planner ordering remains the order
representation: original day, untimed before timed, time, manual rank, then the
stable entry/UUID fallback. Thus a checked carried row stays among its original
neighbors rather than moving into a new completion-date group. Subsequent
explicit ordering can move unfinished neighbors around history; history itself
cannot be dragged or selected for completion. There is no UI-only history store
or invented Scheduled time.

TaskChampion stores/transports the UDA through its existing opaque-attribute
support. Configure `uda.tsk_completion_page.type=string` in Taskwarrior tooling.
Other clients need not render the retained page. Ordinary per-attribute sync
conflict resolution applies, as for status/end and existing manual ranks.
Repeated completion preserves the saved record. A pending task ignores any old
completion page and a later completion replaces it. Unknown/malformed page
metadata is preserved and ignored when reading. Legacy/external completed tasks
without valid page state use the later of original planner day and recorded
`end` day; without both a planner date and valid `end`, they have no inferred
planner history. No backfill writes occur on reads. Explicit later date edits
retain the saved page, but their current intent participates in planner ordering.

## Views and feedback

Day pages (including Today) admit completed history on the retained page only.
Inbox and unfinished project membership still require pending status. A retained row renders a permanent check
and dimmed title/content. Transient checked/cover/collapse feedback still serves
views that actually lose the completed task; planner history never collapses.

## Evidence boundaries

Two Core public-management scenarios distinguish carried completion and early
future completion, including order and unchanged dates. Existing occurrence and
bulk cases retain mask/atomic failure assertions. Existing Native persistence
and real encrypted Taskwarrior sync conformance cover retained page/order on
reopen and an independent peer after a desktop round trip. A focused iPhone
Scheduled journey covers the checked/dimmed rows and fixture-free relaunch.
Canonical iPhone CI at the final integration SHA remains required; host tests
and adapter round trips do not establish external system invocation.
