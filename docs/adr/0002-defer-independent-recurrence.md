# Defer independent recurrence generation

For the initial release, one designated external Taskwarrior client owns recurring occurrence generation; tsk does not generate occurrences. The user requested independent iOS recurrence only if it was straightforward; [upstream research](../research/recurrence-feasibility.md) found that TaskChampion does not implement it, and compatible generation requires template and occurrence bookkeeping, date semantics, and a policy to prevent duplicate generation across clients. We therefore defer an in-process Taskwarrior adaptation or a separate iOS generator while preserving recurrence data.

Recurrence authoring from iOS is a separate capability, supported by [source-based feasibility research](../research/recurrence-control-from-ios.md). Creating and editing recurring templates is included in the initial tsk scope; it does not require tsk to generate occurrences. The sync server only mediates task synchronization. If the designated generator stops, tsk cannot obtain new occurrences beyond the already-generated horizon; simply running synchronization on that client does not generate them either.

Series edits affect future unfinished occurrences while preserving completed history; editing one occurrence is a separate action. Frequency or schedule changes have an explicit effective date and show the affected unfinished occurrences. This requires compatible series bookkeeping, not only synchronized property changes.

After reconsidering optional iOS generation, the user reaffirmed external generation for now. An optional on-device generator remains a later, lower-priority capability.
