# Mapping recurring Apple Reminders to Taskwarrior

Research date: 2026-10-14. Scope: bounded primary-source documentation and Taskwarrior 3.5.0 source review. No importer, recurrence generator, or device behavior was tested. No claim is made about a personal Reminders account or external generator configuration.

## Product direction

tsk can create and edit Taskwarrior recurrence templates; occurrence generation remains external initially. Selected Reminders lists map to Taskwarrior projects. One-time import copies incomplete reminders and leaves sources; continuous import deletes successfully imported sources. No import provenance or identity bookkeeping is authorized.

## Verified facts

EventKit recurrence supports daily, weekly, monthly, and yearly frequencies with positive integer intervals. It also supports selectors for weekdays, month days, months, year weeks/days, and positions within selected occurrences. End conditions can be a date, an occurrence count, or no end. EventKit exposes only the first incomplete reminder in a recurring set; the next becomes available when that reminder is completed. [Apple recurrence documentation](https://developer.apple.com/documentation/eventkit/creating-a-recurring-event?changes=_7&language=objc)

Taskwarrior documents duration-like recurrence frequencies, including daily, weekly, monthly, yearly, and weekdays. Its FAQ says a single recurrence on several selected weekdays is unsupported; multiple templates can simulate it. This is different from an EventKit rule with multiple weekday selectors. [Taskwarrior frequencies](https://taskwarrior.org/docs/man/task.1/#frequencies), [Taskwarrior recurrence FAQ](https://taskwarrior.org/support/faq/)

Taskwarrior recurrence uses a hidden template with a due date, a `recur` value, and an optional `until` date; generated instances are separate tasks. Instance generation need not wait for completion of the current instance. [Taskwarrior recurrence model](https://taskwarrior.org/docs/recurrence/)

In Taskwarrior 3.5.0, ordinary daily/weekly periods fall through to duration arithmetic. Its pinned duration library defines a day as 86,400 seconds. The recurrence code handles some monthly/yearly spellings separately using calendar components: monthly recurrence clamps invalid month days, and yearly recurrence changes February 29 to February 28. Consequently different spellings and date boundaries must be checked against the target generator, not inferred from display labels. [Taskwarrior 3.5.0 recurrence source](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp), [Pinned duration source](https://github.com/GothenburgBitFactory/libshared/blob/86935551e0faa56ed14c52802a23280a593df338/src/Duration.cpp)

The reviewed Taskwarrior recurrence model exposes a date end through `until`, rather than an occurrence-count end. `until` is also documented as task expiration. In the tagged recurrence source it affects generation boundaries and can be inherited by instances. It must not be treated as an interchangeable occurrence counter. [Taskwarrior recurrence model](https://taskwarrior.org/docs/recurrence/), [Taskwarrior until attribute](https://taskwarrior.org/docs/man/task.1/), [Tagged recurrence source](https://github.com/GothenburgBitFactory/taskwarrior/blob/v3.5.0/src/recur.cpp)

## Mapping assessment

These implications are engineering assessments from the facts above, not established conversion support:

- Matching “daily”, “monthly”, or “yearly” labels is insufficient to prove identical recurrence. Timed rules need daylight-saving/time-zone checks; month-end and leap-day rules need date-sequence checks.
- Arbitrary combinations of calendar selectors cannot be assumed to fit a single Taskwarrior `recur` frequency. Splitting one reminder into multiple templates changes task structure and is a separate product decision.
- A count-limited rule cannot simply become an `until` date without establishing the intended remaining occurrences, starting anchor, and external generator behavior. No such mapping was verified here.
- The fetched incomplete reminder is not a complete occurrence history. Mapping it to a template requires a deliberate current-occurrence anchor and handling of already-completed occurrences.
- Reminders' completion-gated availability differs from Taskwarrior's generated task instances. Importing recurrence means accepting Taskwarrior behavior once a verified mapping is available; it does not recreate every Reminders interaction.
- Source deletion for a recurring reminder needs a real EventKit test establishing what is removed and ensuring the replacement template is valid before deletion. This review does not establish deletion scope for recurring sets.

## Accepted product policy

Convert a recurring reminder to a Taskwarrior template only when its complete recurrence semantics have a verified supported mapping. For unsupported or unverified rules, leave the reminder untouched, skip importing it, and explain the specific reason in the current import result. Do not silently remove recurrence, approximate its dates, or delete a source after a partial conversion.

The user accepted this policy; it is not a verified supported-rule list. Neither even the simplest rule nor every Apple rule has been proven compatible by this review. The implementation should establish supported cases with tests against the actual external Taskwarrior generator, covering selectors, date boundaries, time zones, end conditions, and the first incomplete occurrence. No local generation is introduced by this decision.
