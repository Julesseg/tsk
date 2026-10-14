# Reminders import identity and copy-once behavior

Research date: 2026-10-14. Scope: current Apple documentation and TaskChampion API review. No importer implementation, provider-specific identity test, or device import was performed.

## Current product direction

- Import selected Apple Reminders lists into mapped Taskwarrior projects.
- One-time import copies incomplete reminders and leaves the source reminders untouched.
- Continuous import copies incomplete reminders, then deletes each successfully imported reminder from Apple Reminders.
- The user rejects retaining import information anywhere.
- Import identity bookkeeping remains unauthorized. This includes local processed IDs, source-derived task UUIDs, hidden task fields, annotations, and markers in Reminders.

The user has resolved ordinary reimport by choosing source removal for continuous mode. The user accepts occasional duplication after an interrupted move, with local durable task save preceding source deletion, and continuous import enabled on one designated device only. The earlier source-preserving analysis below is retained as historical research, not as the current continuous-import policy.

## Source-removal addendum

### Verified facts

EventKit provides `remove(_:commit:)` for an `EKReminder`. With `commit: true`, removal is committed immediately; with `false`, it waits for `EKEventStore.commit()`. The removal API can throw, so deletion can fail. [Remove a reminder](https://developer.apple.com/documentation/EventKit/EKEventStore/remove%28_%3Acommit%3A%29)

TaskChampion changes reach replica storage through `Replica.commit_operations`; operations can be committed in one TaskChampion transaction. Its storage backend is transaction-protected. This is separate from EventKit's commit mechanism. [Replica operations](https://docs.rs/taskchampion/latest/taskchampion/struct.Replica.html#method.commit_operations), [TaskChampion operations](https://docs.rs/taskchampion/latest/taskchampion/index.html), [Replica storage](https://docs.rs/crate/taskchampion/latest/source/docs/src/storage.md)

The reviewed APIs document commits to their respective stores. They do not document a transaction spanning EventKit reminder deletion and TaskChampion task storage. This bounded review does not prove the absence of every possible coordination mechanism; it does not establish a shared atomic commit capability.

### Assessment and unresolved behavior

For a persistent TaskChampion backend, the accepted order is to complete the local task-storage commit first, then remove the source reminder. An in-memory task object or staged operations are not sufficient evidence of a stored task. Local storage success and remote TaskChampion synchronization are separate milestones; source deletion follows local durable save, with prompt server synchronization handled separately.

| Situation | Consequence with task-save-first ordering |
| --- | --- |
| Task storage fails | Keep the source reminder; do not delete it. |
| Task storage succeeds and source deletion succeeds | The normal transfer completes and the reminder no longer appears in subsequent source scans. |
| Task storage succeeds but deletion fails or the app stops before deleting | The task exists and the reminder remains. A later scan may create a duplicate because no durable import identity is retained. |
| Two devices read the same reminder before either source deletion is visible | Both can independently create a task. Deleting the source afterwards does not remove the duplicate destination tasks. |

These are ordering/race assessments, not measured failure rates or tested provider behavior. Deleting first would instead expose a loss window if task storage then fails, so it is not recommended. An in-memory guard can help within one running process but cannot settle a crash/relaunch gap or cross-device race.

The user accepted occasional duplicates after interruption in exchange for retaining no import bookkeeping, and continuous import on one designated device. A single importing device reduces concurrent creation but does not eliminate the interruption window. Do not promise exact-once transfer or introduce IDs to solve it.

When deletion fails during a running import, show the failure and stop that import attempt from repeatedly creating copies. A later retry may duplicate the task, which is accepted. This note authorizes no implementation or actual reminder deletion.

## Historical research: identity guarantees

EventKit's `calendarItemIdentifier` is a local identifier. Apple states that a full calendar sync can invalidate it and recommends recovery using cached item properties. [Local item identifier](https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemidentifier)

`calendarItemExternalIdentifier` supports cross-device access, but duplicate copies of an item may exist. Apple recommends additional calendar/source information in these cases. Exchange reminder identifiers differ between devices. [External item identifier](https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemexternalidentifier)

External-identifier lookup returns an array and may find multiple matching items. [External-ID lookup](https://developer.apple.com/documentation/eventkit/ekeventstore/calendaritems%28withexternalidentifier%3A%29)

TaskChampion accepts a caller-supplied task UUID and returns the existing task when that UUID already exists. This permits deterministic task identity mechanically; it does not strengthen EventKit's identity guarantees. [TaskChampion task creation](https://docs.rs/taskchampion/latest/taskchampion/struct.Replica.html#method.create_task)

Apple's pages were retrieved through their linked Markdown representations because the HTML documentation returned JavaScript shells during this review.

## Historical research: source-preserving options

The implications below are engineering assessments based on the documented guarantees, not tested algorithms or implementation decisions.

| Option | Information retained | Limits |
| --- | --- | --- |
| Local processed reminder IDs | Importer-local bookkeeping outside task fields | Can prevent reimport while IDs remain recognizable and bookkeeping survives. Identifier resets, separate devices, and loss of local state can cause reimport. |
| Deterministic task UUID derived from a source ID | Source-derived information in task identity | Avoids a dedicated provenance field but still encodes an import relationship. Identifier changes or provider/device differences can produce a new UUID for the same reminder. |
| No persistent bookkeeping, source untouched | No import identity retained | Cannot reliably distinguish an already copied reminder from a newly encountered item on subsequent scans. Repeated imports can duplicate tasks. |

Matching by title, project, or dates is heuristic: distinct legitimate reminders can share those values, and imported tasks may later be edited. It must not be presented as a reliable generic copy-once algorithm.

Deterministic UUIDs also need an existing-task guard so that revisiting a source item does not overwrite the independently edited Taskwarrior task. This remains implementation work if that option is ever approved.

List-to-project mappings identify destinations, not individual source reminders. They cannot by themselves establish whether a reminder was already imported.

## Historical research: earlier clarification

Before the source-removal decision, the proposed clarification was whether minimal processed reminder IDs in local importer storage were acceptable. The user instead chose to delete sources for continuous import; these alternatives are not the adopted policy.

If permitted, describe the resulting guarantee as deduplication within retained importer state, with documented identifier-reset and multi-device limitations. One designated importing device reduces the multi-device problem but does not solve full sync or lost local state. Handling ambiguous identity recovery would need an explicit policy and real tests.

If retaining any identity remains prohibited and sources remain untouched, continuous exact-once copying cannot be promised. The product decision is then whether to retain one-time import only or accept possible duplicates during continuous import. One-time imports also cannot promise deduplication across independently repeated runs without retained identity.

No local IDs, hashes, UUID derivation, hidden fields, source markers, or recovery heuristics are authorized by this research note.
