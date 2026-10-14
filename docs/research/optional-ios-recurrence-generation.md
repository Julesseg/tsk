# Optional iOS recurrence generation

Research date: 2026-10-14. Taskwarrior source findings are pinned to `v3.5.0`.
The user chose to consider this capability later, without prioritizing it. It is
excluded from the initial release, which keeps generation external while including
recurring-template creation and editing. This note describes generic product
behavior and assumes no particular user infrastructure.

## Recommendation

An explicit, initially disabled "Generate recurring occurrences on this device"
option is a plausible future capability. It would make this iOS client the
designated generator, while other clients have generation disabled. Automatic
takeover when another client appears unavailable should remain a separate,
unresolved feature.

This recommendation is an inference from Taskwarrior's existing per-client
recurrence configuration and its documented single-generator workaround. It does
not claim that an iOS implementation has been built or tested.
[Recurrence configuration](https://taskwarrior.org/docs/man/taskrc.5/)

## The option needs an engine

The inspected Taskwarrior generator implements schedule calculation, catch-up,
future occurrence limits, template masks, occurrence creation, relative date
offsets, expiration, and invalid-date handling. Enabling a Boolean in `tsk`
would need to invoke equivalent implemented behavior; it does not activate
generation in the TaskChampion sync server.
[Taskwarrior generator](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp),
[opaque server synchronization](https://gothenburgbitfactory.org/taskchampion/sync-model.html)

There are two implementation routes worth evaluating:

- **Adapt Taskwarrior's C++ implementation in process.** Taskwarrior builds an
  internal static `task` library containing recurrence code, but the generator
  depends on global `Context`, configuration, the task model, database adapter,
  and date helpers. This is reusable source, not a supported standalone generator
  interface. An iOS build and a suitable wrapper remain unverified.
  [Static library target](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/CMakeLists.txt),
  [generator dependencies](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp),
  [recurrence declarations](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.h)
- **Extract or port a standalone generator.** A Swift implementation or a Rust
  engine behind a bridge could offer a narrower interface, but compatibility
  would still require reproducing template/occurrence bookkeeping and Taskwarrior
  date semantics. Choosing this route would create an explicit compatibility and
  maintenance obligation, not remove the recurrence work.
  [Inspected behavior to reproduce](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp),
  [completion bookkeeping](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdDone.cpp),
  [modification propagation](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/commands/CmdModify.cpp)

Calling a bundled Taskwarrior executable as a child process is unsuitable for a
normal iOS app: Apple Developer Technical Support states that iOS apps cannot
spawn child processes. In-process C++ integration is a different possibility.
[Apple DTS explanation](https://developer.apple.com/forums/thread/747499)

## Foreground catch-up and future occurrences

The inspected generator considers due dates from a template and appends
occurrences for indexes beyond its existing mask. It includes missed dates and
a configured number of future occurrences; Taskwarrior's default
`recurrence.limit` is one future occurrence. The horizon is based on due dates,
not on whether earlier occurrences have been completed.
[Generation and horizon calculation](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp),
[recurrence limit](https://taskwarrior.org/docs/man/taskrc.5/),
[documented recurrence behavior](https://taskwarrior.org/docs/recurrence/)

An iOS implementation could run catch-up while the app is active and generate
future occurrences ahead of time. That is an implementation proposal based on
the generator's structure, not an existing `tsk` capability. Choosing a larger
horizon trades more already-created tasks for fewer occasions when reopening
the app is needed to create upcoming ones. The horizon size and its user-facing
meaning remain open.

Background execution cannot guarantee exact generation times or continuous
availability. Apple's `earliestBeginDate` only prevents an earlier start; it
does not guarantee execution at that date. Scheduled background work may wait
many hours. Foreground catch-up therefore needs to remain sufficient for
correctness even if opportunistic background generation is added.
[Earliest begin date](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate),
[background task guide](https://developer.apple.com/documentation/backgroundtasks/starting-and-terminating-tasks-during-development)

Already-created occurrences can have local notifications registered for their
scheduled/deadline times. The system can deliver registered local notifications
while the app is not running; firing such a notification does not require a
generation operation at that moment. This supports pre-generation plus local
notification scheduling, but it does not guarantee notification coverage beyond
the generated and registered horizon. Pending notification capacity and missed
notification policy remain separate questions.
[Local notification scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app),
[existing bounded notification research](notifications-and-sync-feasibility.md)

## Explicit ownership rather than automatic failover

Taskwarrior exposes `recurrence=1` or `recurrence=0` and recommends enabling
generation on one primary client while disabling it on all other clients to
avoid a duplication bug. This configuration belongs to each client's local
configuration; TaskChampion's documented task-operation synchronization does
not automatically distribute a recurrence configuration setting.
[Client configuration and duplication workaround](https://taskwarrior.org/docs/man/taskrc.5/),
[TaskChampion synchronized operations](https://gothenburgbitfactory.org/taskchampion/sync-model.html)

A comparable `tsk` option would therefore be device-local unless a new ownership
protocol were deliberately introduced. Enabling it on one device cannot silently
disable generation in other clients. An explicit handover needs a policy for
disabling the previous generator, synchronizing current templates/occurrences,
and enabling the chosen client. These are design implications, not a protocol
already supplied by TaskChampion.

Lack of recent synchronization does not prove another generator has stopped: it
may be generating while disconnected. Automatic takeover could therefore allow
two clients to generate the same logical occurrence with different UUIDs. The
inspected generator uses new UUIDs and mask length to decide what to create;
ordinary task synchronization does not make that algorithm a single-owner
election system.
[Replica disconnection model](https://gothenburgbitfactory.org/taskchampion/sync-model.html),
[UUID and mask-based generation](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp#L90),
[documented duplicate-generation risk](https://taskwarrior.org/docs/man/taskrc.5/)

## Verification and scope

No iOS generator, adapted Taskwarrior library, notification horizon, or ownership
handover was built or exercised for this note. Source inspection supports the
feasibility of an explicit single-generator option and explains its constraints;
it does not establish implementation readiness.

Before choosing a route, verify pinned compatibility for catch-up, future
horizons, month ends, leap dates, daylight saving changes, offsets, masks,
completion/deletion, series edits, and offline synchronization. The product still
has deferred generation to a later, lower-priority capability. Ownership and
supported recurrence coverage would need decisions before implementing it. This
note does not add generation to the accepted initial release scope.
