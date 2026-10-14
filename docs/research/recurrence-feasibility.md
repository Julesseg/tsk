# Recurrence feasibility for the initial release

Research date: 2026-10-13. Taskwarrior implementation findings are pinned to
`v3.5.0`; its `libshared` dependency is pinned to
`86935551e0faa56ed14c52802a23280a593df338`. This is source-based research, not an
implementation or interoperability test. Generation deferral is recorded in
[ADR-0002](../adr/0002-defer-independent-recurrence.md); the more detailed policies
recommended below still need to be settled.

The product constraint from the interview is to include independent recurrence
only if it is straightforward; otherwise defer it initially.

## Recommendation

Defer independent recurrence generation initially. Support synchronized existing
occurrences and preserve recurrence data. The user subsequently accepted recurring
template creation and editing as initial capabilities; those require their own
semantics and verification, covered in [the control research](recurrence-control-from-ios.md).

This difficulty assessment is an inference from the mechanisms below. TaskChampion
does not supply a recurrence engine, and Taskwarrior's implementation combines
date calculation, template and occurrence bookkeeping, configuration, and database
operations. This is a separate compatibility feature rather than a storage API
setting. [Task model](https://taskwarrior.org/docs/task/),
[Taskwarrior recurrence implementation](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp)

Confidence is high that recurrence is not automatically provided by TaskChampion
and requires substantial additional behavior. Confidence is lower about which
implementation route would be simplest without a build and interoperability
spike.

## Current project baseline

The repository currently has a greeting app and a dependency-free `TskCore`
package. No task model, TaskChampion bridge, persistence, synchronization, or
recurrence implementation exists. The proposed recurrence feature would therefore
sit on an integration that still needs to be built. [README](../../README.md),
[Core package](../../Core/Package.swift),
[current Core behavior](../../Core/Sources/TskCore/Greeter.swift),
[current application screen](../../App/Tsk/ContentView.swift)

## Storage compatibility does not provide recurrence behavior

TaskChampion maintains local replicas and synchronization. Its task model
recognizes recurring status, but recurrence execution belongs to Taskwarrior.
Embedding TaskChampion can provide the underlying records without generating new
occurrences. [TaskChampion API](https://docs.rs/taskchampion/latest/taskchampion/index.html),
[Task model](https://taskwarrior.org/docs/task/)

## When occurrences are generated

Taskwarrior recurrence follows a due-date schedule. The default
`recurrence.limit=1` controls how many future occurrences are generated; historical
missing dates are also considered. Completing an occurrence early does not mean a
new one immediately appears. [Recurrence explanation](https://taskwarrior.org/docs/recurrence/),
[configuration manual](https://taskwarrior.org/docs/man/taskrc.5/),
[generateDueDates](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp)

In `v3.5.0`, `Context::dispatch` calls `handleUntil` and `handleRecurrence` before
commands marked `needs_recur_update`, gated by `gc`. `handleRecurrence` additionally
checks the `recurrence` configuration. Custom reports set the update flag; `done`
and `synchronize` explicitly disable it. Thus **running `task sync` alone does not
generate occurrences** in the inspected version. [Context.cpp](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/Context.cpp#L839),
[report command](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdCustom.cpp#L58),
[completion command](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdDone.cpp#L53),
[sync command](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdSync.cpp#L50),
[generation configuration check](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp)

For a desktop-owned policy, the desktop must execute a generation-triggering
command, such as `task list`, and then synchronize the resulting changes. Merely
being powered on or periodically synchronizing is insufficient. This is a
consequence of the inspected command flags, not a requirement to introduce new
desktop automation into this project.

## Compatibility mechanisms required

The inspected generator and completion/deletion commands implement these linked
behaviors:

- A hidden template with recurring status, `due`, `recur`, optional `until`, and
  a `mask` tracking generated occurrences.
- Occurrences cloned from the template with new UUIDs, `parent` pointing to its
  UUID, and zero-based `imask` identifying their position in the mask.
- Mask entries for pending (`-`), completed (`+`), deleted (`X`), and waiting
  (`W`) occurrences; occurrence status changes update the template.
- Relative `wait` and `scheduled` offsets copied to each occurrence.
- Missing-occurrence catch-up, a future horizon, expiration, invalid period
  handling, and timestamp overflow handling.
- Explicit propagation behavior for edits or deletion of a series versus one
  occurrence.

[Generator and mask bookkeeping](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp),
[completion bookkeeping](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdDone.cpp),
[deletion behavior](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdDelete.cpp),
[modification behavior](https://taskwarrior.org/docs/commands/modify/)

Displaying and completing existing occurrences is a smaller scope than generating
them, but compatible completion still needs recurrence bookkeeping and
interoperability verification. It should not be assumed that setting only the
occurrence status reproduces Taskwarrior's full completion behavior.

## Period syntax and date handling

Taskwarrior accepts named periods, abbreviated duration units, weekdays, and
ISO-8601 durations. Its recurrence implementation has special cases for monthly,
quarterly, annual, and related periods; other values fall through to duration
parsing and second arithmetic. [Frequency manual](https://taskwarrior.org/docs/man/task.1/),
[duration documentation](https://taskwarrior.org/docs/durations/),
[getNextRecurrence](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp)

In the inspected code, monthly calculation clips a day that does not exist in the
next month; annual calculation handles February 29. Calendar branches reconstruct
local timestamps, while `daily` resolves to 86,400 seconds. The pinned date library
uses `mktime` with daylight saving inference. A Swift `Calendar` implementation
would therefore need compatibility tests rather than being assumed equivalent,
especially for month ends, daylight saving transitions, and time zone changes.
[Recurrence date branches](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp),
[pinned Duration.cpp](https://github.com/GothenburgBitFactory/libshared/blob/86935551e0faa56ed14c52802a23280a593df338/src/Duration.cpp),
[pinned Datetime.cpp](https://github.com/GothenburgBitFactory/libshared/blob/86935551e0faa56ed14c52802a23280a593df338/src/Datetime.cpp)

Taskwarrior's recurrence redesign document is explicitly a draft proposal. It must
not be mistaken for the behavior implemented in the inspected release.
[Draft recurrence RFC](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/doc/devel/rfcs/recurrence.md)

## Reuse versus a new implementation

Launching a bundled Taskwarrior executable is unsuitable for a normal iOS app:
Apple Developer Technical Support states that iOS apps cannot spawn child
processes. In-process library integration is a different possibility.
[Apple DTS explanation](https://developer.apple.com/forums/thread/747499)

Taskwarrior builds an internal C++ static `task` library, but recurrence uses the
global `Context`, its task model, database adapter, configuration, and date parser.
The inspected sources do not expose a standalone Swift or Rust recurrence API.
Adapting this internal library is plausible, but it requires a build and interface
spike; porting behavior into Core or a Rust bridge still requires the compatibility
mechanisms above. [Static library target](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/CMakeLists.txt),
[recurrence declarations](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.h),
[implementation dependencies](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp)

## Multiple clients and an initial ownership policy

Official Taskwarrior guidance recommends enabling recurrence on one primary client
and disabling it on every other client to avoid a duplication bug. Independent
offline generators cannot safely be treated as automatic failover merely because
they synchronize afterward. [Configuration manual](https://taskwarrior.org/docs/man/taskrc.5/),
[sync manual](https://taskwarrior.org/docs/man/task-sync.5/)

A conservative initial policy is:

- Desktop Taskwarrior owns generation; `tsk` does not generate occurrences.
- `tsk` displays and completes already-generated occurrences while preserving
  template and occurrence metadata, with tested mask/status interoperability.
- Series creation and editing were originally proposed for deferral, but the user
  subsequently included recurring-template creation and editing in initial scope.
- Setup explains that when the generating desktop is unavailable, existing
  occurrences remain usable, but new ones cannot arrive beyond the already
  generated horizon.

The last limitation follows from leaving generation with the desktop. A running
sync server does not remove it because TaskChampion does not execute recurrence.
Generation ownership and deferral are recorded in ADR-0002. Recurring-template
creation and editing are accepted initial capabilities. Series edits affect future
unfinished occurrences while preserving completed history, with an effective date
for frequency or schedule changes. Exact bookkeeping remains implementation work.

## Remaining uncertainty and verification

No iOS build of Taskwarrior's internal library or recurrence interoperability test
was attempted for this research. Whether extraction or a port is easier remains
unverified. The user's actual recurrence syntax and required series editing
behavior have not been inspected.

Before committing to independent generation, verify a pinned implementation against
Taskwarrior for catch-up, future horizon, month ends, leap dates, daylight saving
changes, offsets, completion/reopening/deletion bookkeeping, series changes, and
offline multi-client synchronization. Resolve generator ownership before enabling
generation on both desktop and phone.
