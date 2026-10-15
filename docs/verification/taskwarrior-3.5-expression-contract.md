# Taskwarrior 3.5 expression contract, version 1

Profile identifier: `tsk-taskwarrior-3.5-expression-v1`. The reference is
Taskwarrior 3.5.0, commit `3419d5ba1e6a780fbbb0a8d68d8fd31e675c1bf8`, its pinned libshared commit
`86935551e0faa56ed14c52802a23280a593df338`, `regex=1`,
`search.case.sensitive=1`, default urgency coefficients, no urgency inheritance,
Y-M-D date format, Sunday numbered weeks, and the device timezone. This extends
the complete required custom-view expression path; it does not import desktop
reports, contexts, configuration, custom urgency coefficients, or working-set IDs.

The public boundary remains `TaskManager.tasks(filter:schema:)`,
`viewSnapshot(filter:schema:)`, `validateFilter`, and saved-view operations.
The raw native editor checks, opens, saves, edits and reopens these expressions;
result edits/completion use the same durable task actions. There is no implicit
pending or project constraint. Snapshots always retain the complete replica for
dependency evaluation.

## Expression values and operators

In addition to all modifiers, searches, boolean expressions, dates, virtual tags,
dependency and typed UDA predicates documented in [the filter guide](../taskwarrior-filters.md),
expressions accept registered fields and computed `urgency`, direct partial `=`,
exact `==`, partial inequality `!=`, exact inequality `!==`, `<`, `<=`, `>`, `>=`,
and ECMAScript `~`/`!~`. `and`, `or`, `xor`, implicit conjunction, parentheses,
and unary `!` compose ordinary predicates with computed expressions.

Arithmetic supports `+`, `-`, `*`, `/`, `%`, right-associative `^`, and unary
signs. Precedence follows pinned Eval.cpp: exponent, unary, multiplication/division/
remainder, addition/subtraction, ordering, equality, regex, conjunction, disjunction,
exclusive disjunction. Exponents must be integers. Integer division truncates;
a real operand preserves real division. Numbers retain the client’s Float-to-Double
UDA read and Double expression arithmetic. The constants `true`, `false`, and
`pi` retain the pinned value `3.14159165` when used as expression operands.
An unregistered bare word remains a search, including `true` and `not`.
A registered bare field resolves through DOM. The pinned evaluator keeps a
separate Boolean result slot: bare numeric arithmetic selects no rows; a
Boolean-origin arithmetic result retains that slot (`true + 2` selects rows,
`false + 2` does not). Comparisons and boolean operators produce their actual
Boolean result. tsk preserves this behavior rather than inventing truthy-number
filter semantics.

String addition concatenates. String subtraction inserts a hyphen and retains the
right literal’s quotes, as pinned Variant.cpp does; comparisons remove surrounding
quotes. Integer string repetition is supported within a bounded allocation.
Dates and durations follow the pinned conversion matrix: date plus duration
is a date; date minus date is a duration; duration divided by duration is real.
The source’s truncation and unsigned32 conversions for real temporal arithmetic
are retained. ISO duration component sums read with signed32 wrapping, distinct
from an arithmetic duration result. No date or duration string is rewritten.

Direct DOM projections include `tags.<tag>`, `annotations.count`, one-based
`annotations.<N>.description`/`.entry`, and date `.year`, `.month`, `.day`,
`.week`, `.weekday`, `.julian`, `.hour`, `.minute`, `.second`, including annotation
entry components. Annotation order follows byte-sorted raw keys. Date week
numbers use the default Sunday `%U` convention; weekdays are Sunday zero and
Julian day is one based. Missing date components use epoch zero, as the client does.
All field identities and string operations preserve UTF-8 spelling.

Typed modifier operands may contain arithmetic, such as `urgency.above:3+1`.
Lexer precedence matters: `3-1` is a set-shaped string operand, so
`urgency.above:3-1` performs a lexical comparison rather than subtraction.
Use spaced direct arithmetic when this distinction matters.

## Default urgency

Default urgency sums Float contributions in the pinned order: project presence1,
start presence4, scheduled strictly before now5, waiting−3, blocked−5,
annotation/tag count factors0/0.8/0.9/1, due scale times12, blocking8,
signed whole-day age divided by365 times2, priority H6/M3.9/L1.8, next tag15.
The due factor ranges from0.2 at least14 days ahead to1 at least7 days overdue,
with the pinned linear interpolation between. Future entry ages remain negative;
only ages above365 are capped. Missing entry contributes2. Raw key presence,
including an empty project/start, follows the source. Dependency contributions
use every stored task, including prerequisites outside the view.

Float accumulation is observable: M alone exports rounded `3.9`, but
`urgency == 3.9` is false and `urgency > 3.9` is true. `urgency + 1 > 4.9`
also selects it. There is no equality tolerance, display rounding, persistent
urgency cache, inheritance, or imported custom coefficient substitution.
Computed views publish a foreground reevaluation boundary; changing time,
priority, tags, annotations, planning or prerequisites updates membership.

## CLI sugar, errors and genuine exclusions

Unquoted UUID tokens become one union of UUID-prefix selectors at the first
UUID position, even inside direct comparisons. Thus `reference == abcdef12`
compares the field with a Boolean selector; `reference == 'abcdef12'` or
`reference.is:abcdef12` compares the typed field value. UUID selectors also
preserve the client’s all-record working-set behavior with `+ACTIVE`.

Taskwarrior rewrites a number at the start of an expression or immediately after
an opening parenthesis into a desktop working-set ID, including decimal numbers.
These forms fail explicitly in tsk because those IDs have no portable identity.
Start a parenthesized numeric fragment with a field or unary sign, for example
`urgency > (urgency - urgency + 3.0 + 1.0)` or `urgency > (+3.0 + 1.0)`.
A bare numeric ID, ID set/range, `id` field and `+LATEST` remain unsupported;
use UUIDs for task identity. A supported numeric modifier operand is not ID sugar.

Use word `and`/`or`: the pinned client emits symbolic `&&`/`||` directly into
its postfix stream without normal infix precedence. tsk reports this ambiguity
explicitly. Regex flags and platform-dependent `.word`/`.noword` remain excluded;
explicit supported ECMAScript patterns are available.

Unknown schema fields, malformed input, invalid regexes, invalid referenced
stored values, division/remainder by zero, invalid operand types and noninteger
exponents produce actionable errors. Boolean sides are evaluated eagerly, so a
false predicate does not conceal an invalid referenced operand. Numeric overflow,
nonfinite results and unsafe/unbounded repetition fail explicitly rather than
trapping, allocating indefinitely, or copying upstream undefined behavior.

## Verification

`TaskComputedFilterTests` exercises the public manager with literal expected
results, including Float boundaries, full graph transitions, precedence,
truncation, eager errors, selector unions, and retained raw attributes.
`ComputedFilterConformanceTests` compares actual TaskChampion storage with a
separate pinned Taskwarrior process for computed urgency and the integrated typed
operator matrix, preserves foreign UTF-8 fields, reopens a saved definition,
changes a prerequisite durably, and verifies genuine CLI errors. Setting
`TSK_FILTER_EVIDENCE_DIRECTORY` records the input records, version/profile,
clock bounds, CLI selections and Core selections as JSON. Live moving-urgency
comparisons enforce a measured300-second clock budget and place interpolation
fixtures six hours away from a decimal threshold. The exact seven-day boundary
and its one-second crossing remain literal public Core checks with a controlled
clock; a frozen Core clock must not be compared to an advancing CLI clock at that
boundary. No tolerance, rounded value, query or assertion is removed.
argv crosses Python
JSON stdin to avoid Darwin Foundation’s Unicode normalization.

`TypedFilterUITests.testComputedArithmeticViewErrorsEditsReopenAndCompletion`
uses the real shared factory on iPhone/iPad: invalid expression draft, computed
Medium-priority result, priority change removing membership, persistent reopen,
expression edit restoring membership, and completion. Local generic compilation
and canonical UI execution are separate gates; no local simulator capture or
physical keyboard acceptance is claimed by these source tests.
