# Typed custom-field filtering (#18)

The existing public TaskManager raw-filter/saved-view seam resolves device-local
attribute definitions and evaluates all five types. Numeric predicates use the
pinned client's Float storage precision, duration predicates compare seconds,
date predicates retain relative-calendar semantics, and string/UUID identity
uses exact UTF-8 spelling. String definitions can declare allowed value order;
priority uses its H/M/L/empty default. Metadata remains device local and shared
with participants; task UUIDs and unfamiliar attributes remain unchanged.

Public tests cover missing and present-empty numeric/duration values, zero and
negative comparisons, quoted operands, default priority and local value order,
canonically equivalent Unicode values, actionable invalid imported values, and
saved membership after durable edits. Actual TaskChampion storage tests reopen
local schema/views, edit typed values, observe changed membership, repair an
invalid imported score, and preserve unfamiliar NFC/NFD raw keys. Removing a
schema produces a clear filter error while keeping its raw task value.

Live isolated Taskwarrior 3.5.0 comparisons cover all five types, relevant
modifiers, regex value formatting, priority, local ordering and missing values.
The fixture passes argv through Python to preserve Unicode spelling. Raw numeric
regex values undergo the client's numeric conversion; quoted patterns retain
literal ECMAScript syntax. Typed `.left`/`.right` mirror the pinned expression
reconstruction behavior, which differs from ordinary string anchoring. Source
references are DOM.cpp, Variant.cpp, CLI2.cpp and Context.cpp in the pinned
checkout. Invalid imported values intentionally report errors instead of silently
using the client's lossy fallback conversion or deleting fields.

The native UI includes allowed-value definition controls, byte-exact picker
choices, updated raw-filter guidance, and automatic saved-view refresh after
value/schema edits. TypedFilterUITests exercises real capture, local definitions,
configured ordering, raw expression save, invalid value correction, membership
change and relaunch. The iPad CI selection includes this class alongside all
existing workspace, annotations, automation, recurrence, attributes and Reminders
classes. Screenshot attachments are produced when canonical UI tests run.

Local simulator execution/screenshots were not captured because of disk
constraints and the no-boot instruction. Generic signed arm64 simulator
build-for-testing compiles the App and UI tests; actual UI execution, iPhone/iPad
rendering, hardware keyboard interaction and account/device background behavior
remain separate CI/device evidence. No personal infrastructure is configured.
