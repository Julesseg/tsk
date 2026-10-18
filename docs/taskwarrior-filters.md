# Raw filters and local custom views

A custom view evaluates its raw Taskwarrior expression over all locally stored
tasks. There is no added pending-status or project predicate. View names and
expressions are saved only on this device as metadata in the shared App Group
replica directory, with an atomic write before acknowledgement. They are shared
with local app participants but do not enter TaskChampion synchronization. Task edits and completion
use the existing Core actions and refresh membership after durable commit.

The reference client is Taskwarrior **3.5.0**, with `regex=1` and
`search.case.sensitive=1`. The current filter implementation supports:

- String attributes, ordinary `+tag`/`-tag`, full UUIDs, and status predicates.
- Date predicates with named dates, durations and offsets; computed availability,
  dependency, date, presence, status, local-UDA and orphan virtual tags.
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

Typed local fields support string, numeric, date, duration and UUID predicates.
Numbers compare the stored Float value promoted to Double, matching the pinned
client rather than a rounded display. Durations compare fixed seconds; dates
reuse the relative/local-calendar rules below; UUID values retain exact case
and prefix spelling. Missing values retain Taskwarrior’s empty-string Variant
semantics, which differ by type and operator: a missing numeric field is below
zero, while a present numeric zero is not missing. Duration ordering against a
zero operand intentionally differs from duration equality.

Local string definitions may declare allowed values, highest first, using one
value per line in the native definition editor. An empty line explicitly places
unset values in that order. Definitions and value identity preserve UTF-8
bytes. The default priority order is H, M, L, empty. Filtering existing values
outside a declared list follows the pinned client’s end-iterator ordering;
changing a constrained value requires an allowed value or explicit removal.
Changing a definition keeps task data intact and refreshes the current view.

A referenced invalid stored typed value reports the task UUID, field and type.
Unrelated fields remain readable/editable and the invalid raw string is retained
until explicitly repaired or cleared. Removing a definition makes dependent
filters report the missing schema without deleting its raw task attributes.

Typed regex operands use the evaluated value’s representation (six significant
digits for numeric values and ISO text for durations). Quote regex patterns
containing expression operators. In pinned Taskwarrior, typed `.left`/`.right`
reuse the original evaluated operand without the string-only anchors; ordinary
string `.left`/`.right` retain their prefix/suffix behavior.

Computed default urgency and typed arithmetic use the versioned
[Taskwarrior 3.5 expression contract](verification/taskwarrior-3.5-expression-contract.md).
Direct comparisons, arithmetic, temporal and DOM values compose with the same
modifiers and boolean predicates. For example `urgency + 1 > 4.9 and +PENDING`
selects the default Medium-priority Float boundary explicitly. No pending predicate
is added by the app. Genuine desktop-ID, platform-dependent and unsafe-expression
exclusions report actionable errors rather than a narrower builder query.

Date fields retain separate meanings: `due:today` filters deadlines and does
not substitute `scheduled`. A partial date predicate compares the local
calendar day; `.is`/`.equals` compare instants, `.before` and `.after` are strict,
and `.by` includes equality. `.none` and `.any` retain empty-date behavior.
Relative operands include `now`, `today`, `yesterday`, `tomorrow`, weekday/month
names, ordinals, start/end of previous/current/next day, week, workweek, month,
quarter and year, and the pinned client's holiday aliases. Informal times,
extended ISO calendar/ordinal/week dates, UTC offsets, duration aliases and
signed offsets such as `now-1week` and `today+P1D` use the same public query.
Invalid dates fail before saving. Raw stored date strings are never rewritten.

The query uses the injected clock and a Gregorian calendar with the injected
timezone. Day boundaries follow local daylight-saving transitions; duration
arithmetic uses Taskwarrior's fixed seconds. Defaults match Taskwarrior 3.5.0
(`due=7`, relative times, Sunday week numbering). Its named week boundaries
are Monday based, and its midsummer calculation follows the actual pinned
source, including the weekday subtraction, rather than a locale assumption.

Virtual tags include `READY`, `BLOCKED`, `BLOCKING`, `UNBLOCKED`, date tags
(`DUE`, `TODAY`, `YESTERDAY`, `TOMORROW`, `OVERDUE`, `WEEK`, `MONTH`, `QUARTER`,
`YEAR`), status and attribute-presence tags, `UDA` and `ORPHAN`. They evaluate
against the entire replica, including prerequisites outside the view. READY
requires pending status, no future wait, no incomplete prerequisite and a
scheduled instant strictly before now when present. Completed/deleted tasks
remain available to explicit queries; date virtual tags exclude terminal tasks.
Plain `+ACTIVE` mirrors Taskwarrior's working-set optimization; an expression
with `or`/`xor` uses all records. UDA/ORPHAN use the effective byte-exact local
schema, including the default priority UDA and recognized native raw prefixes.

A custom snapshot publishes `nextEvaluation`. The app rearms a cancellable
foreground refresh after each snapshot and reloads on significant clock changes
and foreground activation. Midnight, wait expiry, scheduled/overdue boundaries
and moving `now` operands therefore update membership without resaving a view.
Task mutations and prerequisite completion reload the same expression.

Core owns the lexer, boolean AST, schema, predicate evaluation and saved-view
validation. `TaskManager.tasks(filter:schema:)` and `validateFilter` are the
public query boundary; `savedViews`, `saveView`, and `deleteView` handle local
view definitions through an injected external store. The native implementation
stores protected JSON beside the shared SQLite database. The native app and
participant factories inject the same store. Saved-view read-modify-save
operations hold the common semantic mutation lease across the entire operation,
including awaited storage calls, preventing actor reentrancy and cross-process
lost updates. View-only changes do not trigger task synchronization. An absent
optional view store produces an explicit read/write error.

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
temporal evaluation and the later computed predicate extensions.
