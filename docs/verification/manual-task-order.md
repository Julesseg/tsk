# Durable task order and native dragging

Core owns `TaskDragSession`, `TaskManager.drop(_:)`, and
`TaskManager.schedule(ids:change:)`. UIKit collection-view drag and drop delegates supply the actual lift, movement
and drop through the list's native interaction. The list renders
an in-memory reordered preview so neighboring rows move during the gesture.
Crossing a live row center in scrolling content coordinates in either direction records that row's original
complete planner intent, independently of final adjacency. Only drop invokes
storage; cancellation discards the preview. A successful operation has no Undo.

On day pages the preview and saved order obey original planner day, untimed
before timed, then time. Carryover retains its original date. Manual order is
free within an untimed day or equal-time group. A target with only Deadline
supplies fallback intent without changing Deadline. Project dragging changes
order only. Title dragging and checkbox long-press selection have separate
admission regions; ordinary task-list selection remains available as before.

## Taskwarrior representation

Two string user-defined attributes carry independent orders:

- `tsk_planner_order`: rank within effective planner intent (original local
  calendar-day boundary plus `untimed`, or that boundary plus the exact timed
  timestamp).
- `tsk_project_order`: rank within the exact project name.

Both encode `v1:<base64 UTF-8 group>:<nonnegative integer rank>`. Ranks are
independent of Scheduled, Deadline, entry and modified timestamps. Scheduled
precision continues to use `tsk_scheduled_precision`. Rank comparison only
applies when its encoded group matches the task's current effective intent or
project. Malformed, unknown-version and stale-group ranks are ignored. A
missing rank follows ranked tasks, then uses the established descending-entry
and UUID order; older data is not rewritten merely by reading it. Untimed
nonmidnight timestamps remain untimed and share their local-day order group.
Changing timezone can invalidate a day-boundary group; legacy order then
applies until the next explicit ordering operation.

An ordering save assigns consecutive ranks within each affected group. Drop
saves the preview with one coordinated, snapshot-checked atomic transaction,
including Scheduled/precision changes for the dragged task. Recurrence
bookkeeping uses the existing coordinated occurrence validation and mask
update. A stale preview or failed transaction leaves the stored originals
intact. Normal mutation publication requests the existing synchronization and
post-commit effects. No secondary order database or timestamp migration exists.

Incoming scheduling uses `schedule(ids:change:)`. `day` preserves each task's
effective timed/untimed intent (including a Deadline fallback); `intent` assigns
a complete value. The operation removes incoming IDs from their old positions,
retains existing destination order, and appends the supplied relative order
within each applicable destination group in one transaction. Callers supply
IDs in their visible order. These operations do not implement calendar
selection, selected-block UI, event targets or completion history.

TaskChampion persists the attributes on the task and transports them as opaque
UDAs through existing encrypted Taskwarrior synchronization. Configure
`uda.tsk_planner_order.type=string` and `uda.tsk_project_order.type=string` when
using Taskwarrior tooling to inspect them. Other clients need not render tsk
order. External edits that change the group invalidate the old rank; edits
that preserve or later restore the exact group can retain/reactivate it.
Concurrent order changes use TaskChampion's ordinary per-attribute conflict
resolution; equal ranks have the stable legacy tie break. There is no separate
cross-client ordering conflict protocol.

## Evidence boundaries

The compact Core sequence exercises preview-only crossings, reversal, complete
intent inheritance, constrained ordering, project independence, destination
append, stale previews and injected atomic failures. The existing Native
planning test reopens the persistent replica after day and project moves. The
existing real encrypted Taskwarrior sync test passes both order attributes
through a desktop edit and verifies observable order on an independent peer.
These tests establish storage and transport, not another client's presentation.

The focused standard-text iPhone Scheduled journey performs actual native
drags in both directions, checks displaced live neighbors and unchanged
persistent data during crossing, then checks saved intent/order, relaunch and
project date preservation. Its DEBUG receipt observes native callbacks and
reads the real manager while the touch is down; it does not simulate a drop.
Canonical CI at the final integration SHA remains the acceptance gate.
