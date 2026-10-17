# Task attribute identity

TaskChampion identifies raw attribute keys by their UTF-8 bytes. Taskwarrior
3.5.0 also retains distinct composed and decomposed Unicode keys, tags and
project values. Swift `String` equality treats canonically equivalent spellings
as equal, so a `[String: String]` or `Set<String>` cannot represent this dataset
faithfully.

`TaskRecord.attributes` and `TaskDraft.attributes` use `TaskAttributes`;
`TaskManager.update(id:changes:)` and `TaskReplica.update` use
`TaskAttributePatch`. These maps accept dictionary literals, String subscripts,
`updateValue`, `removeValue`, `mapValues`, and sequence iteration over
`(key: String, value: Value)`. Their backing identity and equality compare UTF-8
bytes. Do not construct an intermediate Swift String-keyed dictionary or set
when converting existing task data. `keys` is an array; `keyIdentities` contains
`UTF8String` values suitable for sets and SwiftUI identifiers.

A patch deletion is `patch.updateValue(nil, forKey: key)`, or a contextual
literal such as `let patch: TaskAttributePatch = ["project": nil]`.
Assigning a bare nil to its subscript removes the patch entry instead.
`edited.changes(comparedTo: original)` compares both keys and values by bytes,
so changing only Unicode spelling remains a real edit.

`TaskProjectSelection` equality, hashing and membership compare project bytes.
`TaskProjectSelection.names(in:)` returns distinct names in deterministic UTF-8
order. Tags are derived from the authoritative raw `tag_` keys without
normalization. `UTF8String` also supplies byte-exact `Hashable`, `Comparable`
and `Identifiable` behavior for UI collections. A user-visible label may look
identical for two distinct spellings; display similarity does not merge them.

The private Swift/Rust request/response transport encodes attributes and
patches as arrays of `{ "key": ..., "value": ... }` entries. JSON object
maps decoded into Swift dictionaries would already lose a key before Core
could preserve it. This changes only the bridge transport; the existing
TaskChampion SQLite database and its raw keys require no migration.

Tests cover independent unknown keys and tags, unrelated edits, targeted tag
removal, exact project membership, Unicode-spelling-only edits, actual replica
reopening, and real Taskwarrior 3.5.0 export. UI collection and editor wiring
compile with the app; simulator execution and screenshot comparisons remain
separate acceptance evidence.
