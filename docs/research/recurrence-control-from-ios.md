# Controlling recurrence from iOS without generating occurrences

Research date: 2026-10-14. Source inspection is pinned to Taskwarrior `v3.5.0`
and TaskChampion `v3.1.0`, which that Taskwarrior release declares as its
dependency. The user has since accepted creating and editing recurring templates
in the initial scope, while keeping generation external. Series edits affect future
unfinished occurrences, preserve completed history, and use an effective date for
frequency or schedule changes; occurrence-only editing remains separate. This is
source-based feasibility research rather than verified implementation.
[Taskwarrior's TaskChampion dependency](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/taskchampion-cpp/Cargo.toml)

## Answer

An iOS client can plausibly create a recurring template and synchronize it for a
desktop Taskwarrior client to generate occurrences. This does not require the
iOS client to calculate the recurrence schedule. It does require the iOS client
to create the correct records and the desktop to receive them, run generation,
and synchronize the resulting occurrences back. This is a feasibility conclusion
from source inspection, not a verified end-to-end integration.
[TaskChampion creation and operation APIs](https://github.com/GothenburgBitFactory/taskchampion/blob/v3.1.0/src/replica.rs),
[desktop generator](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp)

The sync server does not parse `recur:daily` and generate tasks. That spelling is
Taskwarrior command input; the task contains a `recur` property whose value is
`daily`. TaskChampion's server sees opaque encrypted task-history data, while
recurrence processing occurs in the Taskwarrior client.
[Server synchronization model](https://gothenburgbitfactory.org/taskchampion/sync-model.html),
[frequency input](https://taskwarrior.org/docs/man/task.1/),
[Taskwarrior generator](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp)

## Creating a template

For a new ordinary Taskwarrior-compatible template, an iOS integration would use
the TaskChampion task-creation and property APIs to initialize the following data:

| Data | Meaning |
| --- | --- |
| New UUID | Task identity, supplied to `create_task`; not a stored task property. |
| `status = recurring` | Use `Status::Recurring`; this is the raw spelling in TaskChampion `v3.1.0`. |
| Nonempty `description` | Taskwarrior requires a description for a newly added task. |
| `due` | First due instant, stored as decimal UNIX epoch seconds. |
| `recur` | Valid supported frequency string, for example `daily`. |
| `entry`, `modified` | Creation and modification timestamps, matching normal Taskwarrior initialization. |
| `rtype = periodic` | Matches Taskwarrior's default for a recurring task; the inspected legacy generator does not branch on this field. |
| Optional `until`, `wait`, `scheduled`, project, tags, priority | Additional compatible task attributes where supported. |

[TaskChampion identity and creation](https://github.com/GothenburgBitFactory/taskchampion/blob/v3.1.0/src/replica.rs),
[status serialization](https://github.com/GothenburgBitFactory/taskchampion/blob/v3.1.0/src/task/status.rs),
[Taskwarrior validation and defaults](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/Task.cpp#L1420),
[storage adapter](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/TDB2.cpp#L73),
[timestamp representation](https://gothenburgbitfactory.org/taskchampion/tasks.html)

The generator's essential selection and calculation inputs are recurring status,
`due`, and `recur`. The other ordinary initialization fields above reproduce
Taskwarrior-compatible task creation rather than being claimed as mechanically
necessary inputs to its date calculation. `due` must be a meaningful valid instant
and `recur` must be validated; storing arbitrary properties in TaskChampion does
not run Taskwarrior's command validation.
[Generation inputs](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp),
[Taskwarrior add validation](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/Task.cpp#L1420)

Initially, `mask` can be absent or empty. There should be no `parent` or `imask`
on this new template. The desktop generator reads the mask and, for each date
whose index has no mask position yet, clones the template into an occurrence,
assigns a new UUID, sets `parent` to the template UUID, writes its zero-based
`imask`, and removes `mask` from the occurrence. It appends the occurrence's
state to the template mask.
[Template and occurrence construction](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp#L90)

Taskwarrior's `add` command validates description and the presence of `due` when
`recur` exists. Its storage adapter then calls `Task::validate`, which turns a
pending task with `due` and `recur`, and without an occurrence parent/template
reference, into recurring status. Direct TaskChampion calls do not perform that
Taskwarrior conversion: the iOS integration should explicitly set recurring
status rather than assume that adding `recur` to a pending task invokes it.
[Add command](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdAdd.cpp#L54),
[storage validation](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/TDB2.cpp#L73),
[status derivation](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/Task.cpp#L1461),
[TaskChampion status setter](https://github.com/GothenburgBitFactory/taskchampion/blob/v3.1.0/src/task/task.rs#L303)

## Desktop generation and the return trip

Recurring tasks are included in TaskChampion's working set, and Taskwarrior's
generator scans its pending-task collection for tasks whose status is recurring.
The desktop must receive the template through sync before that scan can see it.
[TaskChampion working-set handling](https://github.com/GothenburgBitFactory/taskchampion/blob/v3.1.0/src/replica.rs#L360),
[Taskwarrior task retrieval](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/TDB2.cpp#L319),
[generator selection](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp#L70)

In the inspected Taskwarrior release, `sync`, `add`, `modify`, and `done` do not
request recurrence generation. A report such as `list` does. With generation
enabled, the conceptual flow is therefore: phone creates and syncs template;
desktop syncs, runs a generation-triggering report, then syncs; phone syncs to
receive occurrences. A powered-off desktop, or a desktop that only runs sync,
does not produce new occurrences through this flow.
[Command dispatch](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/Context.cpp#L839),
[report flag](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdCustom.cpp#L58),
[sync flag](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdSync.cpp#L50),
[add flag](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdAdd.cpp#L43),
[modify flag](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdModify.cpp#L52),
[done flag](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdDone.cpp#L53)

## Editing a template is not a complete series-edit operation

Directly editing template properties through TaskChampion can change the data the
desktop will use for future generation. It does not automatically execute
Taskwarrior's `modify` command or propagate changes into already-created
occurrences. The generator only creates occurrences beyond the existing mask
length; it does not rewrite dates or descriptions of occurrences already
represented by mask positions.
[Generator's mask check](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp#L96),
[Taskwarrior explicit propagation](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdModify.cpp#L129)

This has two practical consequences, inferred from that code: changing a
template's `due` or `recur` cannot be presented as automatically rescheduling the
next existing occurrence; clearing its mask is unsafe as a shortcut, because the
generator will create new occurrences for indexes already represented by existing
tasks. A series-edit feature needs an explicit policy and consistent updates for
the template and affected pending occurrences.

Taskwarrior's own command checks forbid removing `due` from a recurring task or
removing its recurrence. Its series propagation separately modifies pending
siblings/children and the parent according to `recurrence.confirmation`. None of
those command semantics are implied by a generic TaskChampion property write.
[Consistency checks and propagation](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdModify.cpp#L110),
[documented modification behavior](https://taskwarrior.org/docs/commands/modify/)

## Completion and deletion remain bookkeeping operations

TaskChampion's `done` implementation sets completed status and the status setter
handles `end`. It does not update the Taskwarrior parent's recurrence mask.
Taskwarrior's `done` command separately calls `updateRecurrenceMask`; deletion
does too. Mask entries record pending (`-`), completed (`+`), deleted (`X`), and
waiting (`W`) state at the occurrence's `imask` position.
[TaskChampion completion](https://github.com/GothenburgBitFactory/taskchampion/blob/v3.1.0/src/task/task.rs#L303),
[Taskwarrior completion](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdDone.cpp),
[mask update](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp#L368),
[deletion command](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdDelete.cpp)

Marking a template deleted stops its selection by the generator, but existing
occurrences are separate tasks. Deleting an entire series requires choosing and
updating the affected pending occurrences as well; Taskwarrior has explicit
propagation logic for that choice.
[Generator selection](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp#L70),
[series deletion](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdDelete.cpp)

## Scope and verification

Creating a new template for a single desktop generator is a narrower and more
plausible addition than independent iOS generation. Full series editing,
rescheduling, stopping a series, and compatible occurrence completion still
require explicit behavior and tests. Recurring-template creation and editing are
accepted initial capabilities. Series edits affect future unfinished occurrences,
preserving completed history, with an effective date for frequency or schedule
changes. Deferring independent generation does not remove the implementation and
interoperability requirements.

Multiple devices may edit task data while only one generates occurrences. Official
Taskwarrior guidance recommends one recurrence-enabled primary client to avoid a
duplication bug; having iPhone and iPad create or edit templates does not require
either to become a generator.
[Recurrence ownership guidance](https://taskwarrior.org/docs/man/taskrc.5/)

No new template was created in a live TaskChampion replica and round-tripped
through desktop Taskwarrior for this note. Before claiming compatibility, verify
template creation, desktop receipt and generation, occurrence return sync,
existing-occurrence edits, masks after completion/deletion, and concurrent client
changes with pinned interoperable versions. No implementation was changed.
