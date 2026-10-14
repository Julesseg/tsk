# Taskwarrior filters and Apple Reminders import feasibility

Research date: 2026-10-13. Scope: primary-source documentation review for the product interview. No implementation, build, device import, or compatibility test was performed. TaskChampion observations concern its current published Rust API; the repository dependency version was not checked in this review.

## Approved direction

- Predefined Today, Upcoming, and project views, taking inspiration from Things 3.
- Custom views defined using Taskwarrior filter expressions.
- Apple Reminders import: incomplete reminders once or continuously from selected lists, which map to Taskwarrior projects. Completed reminders, export, and two-way synchronization are outside this direction. No priority or importance criterion applies.
- One-time import copies eligible reminders and leaves sources untouched. Continuous import moves reminders into tsk and removes imported source reminders, without retaining import bookkeeping or provenance. The user accepts occasional duplicates after interrupted moves and continuous import on only one designated device.
- The planned day maps to `scheduled`; the deadline maps to `due`.
- Custom filter expressions are entered in tsk, and saved views stay device-local. Desktop report/context/configuration import is not planned.

The questions below refine these requirements; they do not replace them with narrower capabilities.

## Taskwarrior filters

### Verified facts

TaskChampion's documented `Replica` API supplies all/pending task retrieval, UUID lookup, working sets, and dependency maps. It does not expose a Taskwarrior filter-expression evaluator. The documented `Task` API supplies task properties and relationships, but no urgency calculation API. [Replica API](https://docs.rs/taskchampion/latest/taskchampion/struct.Replica.html), [Task API](https://docs.rs/taskchampion/latest/taskchampion/struct.Task.html)

Taskwarrior expressions include attribute modifiers, tags, boolean operators, parentheses, and searches. Search behavior depends on regex and case-sensitivity configuration; report predicates can add implicit constraints. [Filters](https://taskwarrior.org/docs/filter/)

Virtual tags are computed at runtime. Some require task relationships or time; `+DUE` also depends on `rc.due`. [Virtual tags](https://taskwarrior.org/docs/tags/)

UDA types and allowed values are configuration. Taskwarrior preserves attributes received without their UDA definitions, but does not expose those orphaned attributes as ordinary report/filter fields. [UDAs](https://taskwarrior.org/docs/udas/)

Reports combine filters with sorting and presentation configuration. Contexts and urgency coefficients are also configuration, so matching a desktop installation's results requires more than receiving its tasks. [Reports](https://taskwarrior.org/docs/report/), [Configuration](https://taskwarrior.org/docs/man/taskrc.5/)

### Assessment and recommendation

Supporting the approved filter requirement requires evaluator reuse or a compatible parser and evaluator, plus explicit handling of configuration-dependent semantics. This is an inference from the API boundary above, not a tested implementation conclusion.

Keep Taskwarrior filter expressions as the product requirement. The user accepted documented Taskwarrior defaults, local UDA type definitions, and explicit errors for invalid or unsupported expressions. Record the supported Taskwarrior version, configuration inputs, and comparison tests against that version when designing the implementation; this is not approval to silently narrow filter compatibility.

Filter expressions, shell commands, and report names are different inputs. Desktop report/context/configuration import is not planned. Use documented defaults and locally configured UDA definitions; exact conformance remains implementation work.

## Things-inspired views and Taskwarrior dates

### Verified facts

Things distinguishes when work should begin from its deadline. Future start dates place tasks in Upcoming; they enter Today when their start date arrives. Today is intended for the tasks the person plans to work on and supports ordering them for the day. Upcoming presents the next seven days individually before later dates. [Things scheduling](https://culturedcode.com/things/support/articles/2803579/), [Things default lists](https://culturedcode.com/things/support/articles/4001304/)

Taskwarrior distinguishes `scheduled` (earliest opportunity to work), `due` (deadline), `wait` (hide until), and `start` (work actually started). An unscheduled task is considered ready, so selecting all ready tasks does not define a curated Today list. [Using dates effectively](https://taskwarrior.org/docs/using_dates/), [Terminology](https://taskwarrior.org/docs/terminology/)

### Settled view behavior

The user accepted distinct planned work dates and deadlines, mapped to `scheduled` and `due`.

Today includes unfinished tasks planned for today or earlier, and tasks due today or overdue. Unfinished planned tasks remain until completed or rescheduled; matching waiting or blocked tasks stay visible with their reason. Today also displays calendar events, without creating events or time blocks.

Upcoming groups future planned work and deadlines by day, distinguishing their roles. A task may appear at both its future planned date and its future deadline.

## Apple Reminders import

### Verified facts

EventKit supports fetching all reminders across calendars/lists or a selected set, as well as separate complete/incomplete queries. This supplies the access needed for both requested import modes. [Retrieving reminders](https://developer.apple.com/documentation/eventkit/retrieving-events-and-reminders?changes=_9), [Reminder predicates](https://developer.apple.com/documentation/eventkit/ekeventstore/predicateforincompletereminders%28withduedatestarting%3Aending%3Acalendars%3A%29?language=_5)

Reminders require the full-access permission, which grants read/write access even when tsk chooses to use it only for import. Denial must be handled. [Reminders permission](https://developer.apple.com/documentation/eventkit/ekeventstore/requestfullaccesstoreminders%28completion%3A%29)

EventKit change notifications require refetching affected data; they are not a per-reminder change log. Apple's description concerns changes observed while the app is running. [Change notifications](https://developer.apple.com/documentation/EventKit/updating-with-notifications?language=objc)

iOS does not guarantee that a background task launches at its requested earliest date. Continuous import therefore cannot promise immediate ingestion while tsk is closed. [Background scheduling](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate)

An EventKit local item identifier can be invalidated by a full calendar sync. External identifiers have duplication cases and Exchange reminder identifiers can differ between devices. Import deduplication must account for these limitations. [Local identifiers](https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemidentifier?changes=_3%2C_3), [External identifiers](https://developer.apple.com/documentation/eventkit/ekcalendaritem/calendaritemexternalidentifier?language=objc)

Public documented fields include titles, notes, URLs, dates, priority, completion, alarms, and recurrence rules. This review did not establish complete fidelity for Reminders tags, subtasks, attachments, flags, list groups, or every recurrence feature. “Everything” must distinguish selecting all reminder items from preserving every Reminders feature; field mapping needs a focused SDK/API audit and real import tests. [Calendar item API](https://developer.apple.com/documentation/eventkit/ekcalendaritem?changes=__3&language=objc), [Reminder API](https://developer.apple.com/documentation/eventkit/ekreminder)

### Recommendation and open decisions

Continuous import can rescan on foreground entry, observed changes, and available background opportunities, with a visible last-import result. This is a proposed behavior, not an implemented guarantee.

The user chose one-time copying with originals left untouched and continuous moving with imported source reminders removed. No import identity bookkeeping is retained. Tasks are independently managed after import; there is no export or two-way synchronization.

Completed reminders are excluded, without any additional importance criterion. Selected source lists map to Taskwarrior projects. No provenance or import bookkeeping is retained. The user accepts occasional duplicates after interrupted moves; save durably locally before deleting the source, and enable continuous import on only one designated device. Convert recurring reminders only for verified supported rules; leave unsupported or unverified sources untouched with an explanation. See [the recurrence-mapping research](reminders-recurrence-mapping.md).
