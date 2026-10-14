# Raw filters and local custom views

A custom view evaluates its raw Taskwarrior expression over all locally stored
tasks. There is no added pending-status or project predicate. View names and
expressions are saved only on this device, separately from the TaskChampion
replica, with an atomic write before acknowledgement. Task edits and completion
use the existing Core actions and refresh membership after durable commit.

The reference client is Taskwarrior **3.5.0**, with `regex=1` and
`search.case.sensitive=1`. The initial filter slice supports:

- String attributes, ordinary `+tag`/`-tag`, full UUIDs, and status predicates.
- Partial `attribute:value`, exact `.is`/`.equals`, `.isnt`, partial `.not`,
  `.none`, `.any`, and string `.before`/`.under`/`.below`,
  `.after`/`.over`/`.above`, `.by` comparisons.
- `.has`/`.contains`, `.hasnt`, `.startswith`/`.left`, `.endswith`/`.right`.
- Bare searches and `/pattern/` against description and annotations; boolean
  implicit `and`, explicit `and`, `or`, `xor`, parentheses, and unary `!`.

String identity and ordering compare UTF-8 bytes. Empty partial operands match
only empty strings. Ordinary string ordering with an empty operand does not
match, except equality for `.by`. Status equality and partial equality are
case-insensitive exact comparisons; pending tasks with a future wait evaluate
as waiting. Text, project and tags remain case-sensitive. Tag keys and the
`tags` projection use authoritative independent raw keys.

Quote values containing spaces or expression punctuation, for example
`description.has:'(Alpha|Beta)'`. A blank expression selects every task.
The word `not` is searched text; unary negation uses `!(project:Work)`.
Unknown attributes report the missing local schema instead of silently
becoming text searches. Invalid modifiers, parentheses, quotes and regexes
produce errors before querying or saving. A failed saved-view edit retains
its previous definition and the editor draft.

Date and virtual-tag expressions, local UDA types/value order, and computed
or arithmetic operands are extended by the following filter slices. This
slice returns explicit unsupported errors for them, including priority
ordering, numeric working-set IDs, and regex flags. `.word`/`.noword` are
also rejected because pinned Taskwarrior implements different boundaries on
Darwin and Linux; an explicit supported ECMAScript pattern is available.
Unsupported input is never reinterpreted as a narrower builder query.

Core owns the lexer, boolean AST, schema, predicate evaluation and saved-view
validation. `TaskManager.tasks(filter:schema:)` and `validateFilter` are the
public query boundary; `savedViews`, `saveView`, and `deleteView` handle local
view definitions through an injected external store. The native implementation
stores protected JSON in Application Support outside the synchronized replica.

The small portable C++17 helper uses `std::regex` ECMAScript and
`regex_search`, matching the pinned upstream
[regex wrapper](https://github.com/GothenburgBitFactory/libshared/blob/86935551e0faa56ed14c52802a23280a593df338/src/RX.cpp).
It receives explicit UTF-8 lengths, so byte semantics and embedded NULs are
retained. It owns compiled expressions and error buffers. SwiftPM compiles it
on Linux and Apple targets; Linux CI installs standard C++ development headers
without replacing Swift's bundled Clang.

Conformance tests query the public manager against pinned CLI fixtures and
compare live actual-replica selections with Taskwarrior export. The live CLI
fixture passes an argv array via a Python subprocess: Darwin Foundation
`Process.arguments` normalizes Unicode spelling, so directly passing Unicode
filter arguments would corrupt the reference query. No filters run through a
shell. UI tests cover validation, save/edit/relaunch/open, result completion
and deletion. Compilation, UI execution, device rendering and physical
keyboard behavior remain distinct verification gates.

Custom queries also expose `TaskManager.viewSnapshot(filter:schema:)`: one
raw-record read supplies the selected rows, all records for dependency context,
and byte-exact project names. A prerequisite outside a custom view continues
to explain blocking, and completing it updates availability without deleting
link metadata. The injected Core clock and calendar remain query inputs for
the later temporal and computed predicate extensions.
