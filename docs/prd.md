# tsk product requirements document

The accepted [daily planner redesign](planner-redesign.md) supersedes conflicting navigation, date placement, ordering, calendar display, and completion-history requirements in this original PRD. Other capabilities remain the baseline. The redesign is not yet implemented.

## Problem Statement

Taskwarrior users need a capable, modern iPhone app that lets them capture work, decide what to do next, and act quickly while continuing to use their existing Taskwarrior clients. A mobile client must preserve task information and Taskwarrior behavior, work without a connection, synchronize promptly through TaskChampion, and participate in native iOS workflows.

This PRD records the agreed product contract without recording personal infrastructure setup. Implementation and runtime verification are tracked separately; a requirement here does not establish that the behavior has been delivered or verified.

## Solution

Build a first-class native iPhone Taskwarrior client with Liquid Glass and a thin SwiftUI app over a deep Core module. The primary workflow is capture, choose, and act. Provide Things 3-inspired Today, Upcoming, and project views; device-local custom views defined using Taskwarrior filters; a complete task editor; offline local persistence; and automatic synchronization with a configured TaskChampion server as soon as connectivity and iOS execution permit.

The initial product includes Shortcuts/Siri and calendar events displayed only in Today. Apple Reminders integration is out of scope. Recurring templates can be created and edited in tsk, while one designated external Taskwarrior client generates occurrences. Optional on-device generation remains a later, lower-priority capability.

The behavior below is the initial scope. It is not an assertion that interoperability or device behavior has already been verified, and it does not prescribe a delivery estimate.

## User Stories

### Capture and task editing

1. As a Taskwarrior user, I want to capture a task quickly on my phone, so that I can record work wherever it arises.
2. As a task owner, I want to review and edit a task draft before saving it, so that I can correct captured information without creating an unwanted task.
3. As a task owner, I want to edit a task description, so that the work remains clearly described.
4. As a task owner, I want to assign and change a task project, so that I can organize work using the same projects as my other clients.
5. As a task owner, I want to add and remove task tags, so that I can categorize tasks and use those tags in filters.
6. As a task owner, I want to set and change task priority, so that I can express its relative importance.
7. As a task owner, I want to add and edit annotations, so that supporting notes remain attached to the task.
8. As a task owner, I want to set a Scheduled date and time independently of a Deadline, so that planning work does not change when it must be finished.
9. As a task owner, I want to set and change a waiting date, so that I can distinguish work that is not yet available.
10. Dependency management was removed from scope on 2026-11-17. Imported fields remain preserved and readable by Taskwarrior filters.
11. As a task owner, I want to start and stop work on a task, so that active work is represented consistently with Taskwarrior.
12. As a task owner, I want to complete tasks from the task list, so that routine actions do not require opening every task.
13. As a Taskwarrior user, I want unfamiliar task attributes preserved during ordinary edits without a custom-field editor.
14. As a task owner, I want unsupported filter fields reported explicitly instead of silently changing saved-view membership.
15. As a Taskwarrior user, I want to retain unfamiliar attributes when editing other fields, so that mobile edits do not discard information used by other clients.

### Task views and choosing work

16. As a task owner, I want to see all tasks scheduled for today in Today, including times later today, so that I can review the whole day's intended work.
17. As a task owner, I want to keep unfinished tasks scheduled for earlier days in Today until completion or rescheduling, so that unfinished commitments do not disappear overnight.
18. As a task owner, I want to see tasks due today and overdue in Today, so that I can recognize approaching or missed deadlines.
19. As a task owner, I want to see matching waiting tasks with their reason in Today, so that I can understand why a scheduled or due task is not actionable.
20. As a task owner, I want to see future scheduled work grouped by day and ordered by time in Upcoming, so that I can review the days ahead.
21. As a task owner, I want to see future deadlines distinguished from Scheduled dates and times in Upcoming, so that I can plan work without confusing it with its deadline.
22. As a task owner, I want to see a task at both its future Scheduled date and its different Deadline, so that both commitments are visible.
23. As a task owner, I want to browse tasks by project, so that I can review related work together.
24. As a Taskwarrior user, I want to enter Taskwarrior filter expressions to define custom views, so that I can use familiar task selection rules.
25. As a Taskwarrior user, I want to evaluate filters using documented Taskwarrior defaults and locally defined attribute types, so that results have a clear compatibility contract.
26. As a Taskwarrior user, I want to receive a clear error for invalid or unsupported expressions, so that I do not mistake an incorrectly interpreted filter for an accurate result.
27. As a task owner, I want to save and edit custom-view definitions on the current device, so that I can return to useful views without re-entering filters.
28. As a task owner, I want to keep saved views device-local, so that view definitions are not unexpectedly synchronized to another device.
29. As a task owner, I want to perform task actions directly in useful lists, so that choosing work and acting on it form one efficient workflow.

### Local data and synchronization

30. As a task owner, I want to create, edit, complete, and view tasks without a connection, so that ordinary task management remains available offline.
31. As a task owner, I want to retain saved changes after the app restarts, so that a successful local save represents durable work.
32. As a Taskwarrior user, I want to configure synchronization with a TaskChampion server, so that tsk participates in the same task dataset as my other clients.
33. As a task owner, I want to attempt synchronization promptly after task changes, so that other clients can receive my work as soon as execution and connectivity permit.
34. As a task owner, I want to attempt synchronization when I open the app, so that I receive remote changes promptly when returning to tsk.
35. As a task owner, I want to retry synchronization when connectivity returns, so that offline changes do not depend on remembering to sync manually.
36. As a task owner, I want to see synchronization status and invoke retry, so that I can distinguish local persistence from successful server synchronization.
37. As a task owner, I want to retain local changes during connection or server failures, so that a failed sync does not lose already saved work.
38. As a Taskwarrior user, I want to receive remote changes without duplicate task identities, so that the same task remains the same task across clients.
39. As a task owner, I want to have all supported iOS entry points use the same task behavior and synchronization policy, so that actions outside the main app do not produce inconsistent data.
40. As a task owner, I want to benefit from background synchronization opportunities without depending on exact background timing, so that the app remains correct under iOS scheduling constraints.

### Recurring templates and occurrences

41. As a task owner, I want to create a recurring template with a valid first due date and recurrence rule, so that another recurrence-enabled Taskwarrior client can generate its occurrences.
42. As a task owner, I want to view and edit recurring templates in tsk, so that recurrence management does not require switching to a terminal.
43. As a task owner, I want to distinguish a recurring template from its individual occurrences, so that I know whether I am changing a series or a task to complete.
44. As a task owner, I want to edit one occurrence separately from its series, so that an exceptional task does not unintentionally change the recurring plan.
45. As a task owner, I want to apply template changes to future unfinished occurrences while preserving completed history, so that the recurring plan can change without rewriting completed work.
46. As a task owner, I want to choose an effective date for recurrence frequency or schedule changes, so that the change starts when I intend.
47. As a task owner, I want to see which unfinished occurrences a series edit will affect, so that the scope of the edit is understandable before saving.
48. As a Taskwarrior user, I want to complete occurrences with compatible series bookkeeping, so that other clients retain a consistent view of the recurring series.
49. As a Taskwarrior user, I want to preserve recurrence links and bookkeeping during other task edits, so that mobile edits do not cause missing or duplicated occurrences.
50. As a task owner, I want to receive generated occurrences through TaskChampion synchronization, so that I can manage them using the same views and actions as other tasks.
51. As a task owner, I want to understand that new occurrences depend on a designated external generator, so that I do not expect the sync server or the initial iOS app to generate them.

### Shortcuts and Siri

52. As an iOS user, I want to create tasks through Shortcuts and Siri, so that capture can participate in native automation.
53. As an iOS user, I want to find tasks through Shortcuts and Siri, so that automations can work with existing tasks.
54. As an iOS user, I want to complete tasks through Shortcuts and Siri, so that I can act without navigating through the main app.
55. As an iOS user, I want to modify named task fields, including rescheduling, through Shortcuts, so that native automation can update my tasks without command syntax.
56. Removed from product scope on 2026-11-17: widgets.
57. Removed from product scope on 2026-11-17: widgets.
58. Removed from product scope on 2026-11-17: widgets.
60. Removed from product scope on 2026-11-17: incoming system sharing.
61. Removed from product scope on 2026-11-17: incoming system sharing.
62. Removed from product scope on 2026-11-17: incoming system sharing.

### Calendar

63. As a task owner, I want to see calendar events in Today alongside my tasks, so that I can account for existing commitments when choosing work.
64. As an iOS user, I want to display calendar events without creating or modifying them, so that calendar integration remains limited to the agreed purpose.
65. Apple Reminders import, including one-time copy, continuous move and recurring conversion, was removed from scope on 2026-11-18. Existing task data remains.

### Retired notifications and Spotlight

Notifications and Spotlight indexing were removed from product scope on 2026-11-17. Historical notification and indexing verification records do not define current acceptance.

### Native experience and permissions

92. As an iPhone user, I want to use a compact native capture-and-action workflow, so that daily task management fits the phone.
93. Superseded by [ADR 0007](adr/0007-iphone-only.md): native iPad adaptive layout is out of scope. External keyboard commands and widgets were subsequently removed from product scope on 2026-11-17.
94. As an iOS user, I want to use native navigation, typography, gestures, accessibility, appearance, and Liquid Glass, so that tsk behaves as a first-class iOS app.
95. As a task owner, I want to scan compact lists and reveal additional detail when needed, so that the interface balances density with clarity.
96. As an iOS user, I want to retain ordinary task management when Calendar permissions are denied or revoked, so that optional system access does not prevent use of my tasks.
97. As an iOS user, I want to receive clear permission and integration failure states, so that I can understand which requested capability is unavailable.

## Implementation Decisions

### Modules and interfaces

- Core is the platform-independent module for task behavior. The SwiftUI app stays thin. iOS extensions and actions use the same Core behavior rather than implement competing task rules.
- Introduce one primary public task-management interface in Core through which callers and behavior tests create, edit, complete, query, plan, and synchronize tasks. Keep field validation, view membership, filter evaluation, recurrence bookkeeping behind that interface.
- Reuse the existing Core and XCUITest testing seams. Where platform execution actually varies, supply concrete adapters for persistent TaskChampion data, synchronization, EventKit, clock/time zone, and system entry points. Keep adapter details internal where possible; do not create a public interface for each individual field or UI action.
- Keep platform-independent decisions testable without EventKit. Actual OS reads, writes, permission requests, scheduling, and extension execution belong in platform adapters; their results flow back through the Core interface.
- Preserve task identity and unfamiliar attributes. Local custom-attribute editing and definition management are not supported. Do not round-trip tasks through a reduced schema that discards fields another client understands.
- Pin the supported Taskwarrior and TaskChampion versions before claiming compatibility. Select and verify the Swift integration route separately; this PRD does not assert that an existing bridge or Taskwarrior library has already been proven to work on iOS.

### Dates, task views, and filters

- Scheduled uses Taskwarrior's `scheduled` attribute and supports date and time throughout editors and displays; Deadline uses `due`. Preserve existing timestamps, including midnight, without inferring replacement times. Starting work and Waiting until remain separate. See [ADR 0006](adr/0006-scheduled-includes-time.md) and [implementation ticket #64](https://github.com/Julesseg/tsk/issues/64).
- Today contains unfinished tasks scheduled for today or an earlier day, including times later today, and tasks due today or overdue. An unfinished scheduled task remains until completed or rescheduled. Matching waiting tasks remain visible with their reason. Calendar events appear in Today only.
- Upcoming groups future scheduled work and future deadlines by local calendar day, orders entries by actual timestamps, and labels their roles. A task can appear on two dates when its Scheduled and Deadline dates differ.
- Provide project views and actions directly from lists. Templates and ordinary occurrences remain distinct domain concepts.
- Custom views accept Taskwarrior filter expressions entered in tsk. Use documented Taskwarrior defaults for built-in fields. Do not import desktop reports, contexts, or configuration.
- TaskChampion’s storage interface is not a Taskwarrior filter evaluator. Implement or reuse compatible evaluation and verify its behavior against the pinned Taskwarrior version, including boolean expressions, modifiers, relative dates, virtual tags, dependencies, and built-in typed fields. Explicit errors must not become an excuse to silently replace the requested language with a smaller tag/project filter builder.
- Saved custom views remain device-local.

### Persistence and synchronization

- Local task operations are durable and usable offline. An acknowledged local save is distinct from a successful server sync.
- Attempt sync after task changes, when the app opens, and when connectivity returns. Show current sync state and support retry. Retain local work when synchronization fails.
- Use background opportunities, while keeping correctness independent of a guaranteed background launch. Do not promise immediate receipt of remote changes while iOS suspends the app.
- Converge through TaskChampion task identity and synchronization semantics. This PRD does not replace upstream conflict handling with a separate task-merging protocol.
- System actions and extensions must use consistent persistence, task identity, validation, and synchronization behavior. Integration-specific failure states must not corrupt ordinary local task use.

### Recurring templates

- Initial tsk supports creating and editing valid recurring templates. TaskChampion stores and synchronizes these records; it does not execute Taskwarrior command validation or generate occurrences.
- One designated external Taskwarrior client owns generation. It must receive templates, run a generation-triggering command, and synchronize generated occurrences back. A sync-only client does not satisfy the generation requirement in the inspected Taskwarrior version.
- Template initialization and edits must preserve the required task status, recurrence rule, due anchor, and compatible template/occurrence relationships. Occurrence completion must maintain the series bookkeeping expected by Taskwarrior, rather than only change an individual status.
- Distinguish editing one occurrence from editing the series. Series edits affect future unfinished occurrences and preserve completed history. Frequency and schedule changes use an effective date, and the UI shows the unfinished occurrences that will change.
- Changing template properties alone does not update already-generated occurrences. Implement and verify the affected-occurrence updates and bookkeeping before exposing series editing as compatible. Do not reset template state as a shortcut that regenerates duplicates.
- If the external generator stops, existing occurrences remain usable, but new ones cannot arrive beyond the already-generated horizon. Do not embed a generator in the initial app or automatically take over generation from another client.

### iOS capabilities

- Shortcuts and simple, unversioned URLs expose Add, Modify, Delete, Find, Complete, Open Task, and Open View with named inputs and shared behavior. Task-targeted actions use one entity or full UUID. Mutations execute immediately and acknowledge durable local storage; optional URL callbacks return structured results and never undo or retry a committed change on delivery failure. Existing saved shortcuts may break; Modify replaces standalone Reschedule. See [ADR 0005](adr/0005-structured-actions-for-urls-and-shortcuts.md) for the decision and implementation tickets.
- Incoming system sharing is retired; a future implementation requires a new product contract.
- Calendar integration reads events for Today and creates no calendar events or time blocks. Permission denial or revocation leaves ordinary task management usable.
- Support iPhone capture and action, Native iPad support is out of scope under [ADR 0007](adr/0007-iphone-only.md). Use native iOS navigation, typography, gestures, accessibility, appearance, and Liquid Glass.

## Testing Decisions

The user confirmed Core’s public task-management interface, the existing XCUITest suite, and real adapter checks as the testing seams.

- Good tests exercise observable behavior through the same interface used by callers. Check persisted results, task identity, returned views, synchronization state, and platform effects. Avoid tests that merely repeat field assignments, inspect private implementation structure, or pass only because a mock reproduces the implementation.
- Core’s current Swift Testing greeting tests provide the fast, platform-independent testing lane, not task behavior prior art. Extend that lane with scenario-based tests through the proposed task-management interface. The current XCUITest launch/greeting smoke test establishes the UI lane; it is not evidence that any task feature exists.
- Use deterministic time, time zones, and controlled adapter results for meaningful Core scenarios. Prefer a small number of whole workflows over separate seams for each field or view.
- Verify create/edit/complete/query workflows survive reopening local storage, retain UUIDs and unknown fields, and keep local edits during sync failures. Exercise multiple clients against a real TaskChampion setup before claiming convergence; mocked sync success is insufficient.
- Compare Taskwarrior filter results against the pinned Taskwarrior client using shared task fixtures. Cover expression operators, parentheses, attribute modifiers, relative dates, virtual tags, dependencies, built-in typed fields, missing values, and explicit invalid/unsupported-expression errors.
- Exercise Scheduled time selection and preservation, including non-midnight and existing midnight values. Exercise Today and Upcoming at day/DST boundaries: overdue, earlier Scheduled dates, times later today, future Scheduled/Deadline timestamps, tasks present at both dates, completion, rescheduling, waiting/blocked inclusion, and Scheduled-versus-Deadline separation. Verify calendar events appear only in Today.
- Round-trip recurring templates through a real external Taskwarrior generator. Verify creation, occurrence return sync, occurrence completion bookkeeping, single-occurrence edits, effective-date series edits, preserved completed history, masks/relationships, and continued generation without duplicated or missing instances. Include date boundaries, relative dates, month ends, leap days, and daylight saving in the supported contract.
- Grow the existing XCUITest suite with capture/edit/list actions, Today/Upcoming/projects/custom views, offline use and visible retry states, occurrence-versus-series editing, settings and graceful denied-permission states. The macOS CI XCUITest job is the canonical UI gate; local simulator execution is optional.
- Exercise Shortcuts/App Intents and Calendar access using real platform adapters in simulator or device environments as appropriate. Where CI cannot prove account or background behavior, record the missing evidence and require the relevant integration/device verification before claiming support.
- Verify iPhone navigation, system appearance, and accessibility. Simulator/CI success alone does not prove background timing, or external-account behavior.
- A documentation review or green scaffold CI does not fulfill these feature-level checks. Every delivered capability needs evidence at its stated seam, with unsupported cases and remaining verification limits reported explicitly.

## Out of Scope

- On-device occurrence generation in the initial release, including an enabled recurrence generator or automatic takeover from another generating client. Optional iOS generation is later and lower priority.
- Guaranteed immediate background sync or exact background generation timing.
- Desktop report, context, or configuration import.
- Synchronization of saved custom views between devices.
- Creating or modifying calendar events, time blocking, or displaying calendar events as an Upcoming integration.
- File attachment storage and a dedicated Mac experience.
- Provisioning or configuring any personal external generator or server. The PRD describes generic client capabilities only.
- Implementing the application as part of publishing this PRD. It specifies the product; the current repository remains a scaffold.

## Further Notes

- The agreed source brief, glossary, ADRs, and primary-source research are in documentation PR #2: https://github.com/Julesseg/tsk/pull/2. Its Core and XCUITest checks passed for documentation/scaffold changes, not the capabilities specified here.
- This is an umbrella product spec. Preserve the complete initial scope when it is decomposed into implementation milestones. Do not drop UI or system integrations because one execution environment cannot run them locally.
- Repository policy places business behavior in Core and keeps the UI thin. Core tests are the fast loop; CI is the canonical app UI gate. Future implementation work must include its UI and be delivered through working-branch pull requests.
- The exact Swift/TaskChampion binding, supported version pins, verified EventKit field mappings, safe series-edit bookkeeping and device/account verification are implementation work. Do not present them as solved by this document. Avoid publishing an unverified list of supported recurrence conversions.
- Neither TaskChampion property writes nor its sync server execute Taskwarrior’s recurrence validation, series propagation, mask updates, filter evaluation, or occurrence generation automatically.
- No personal infrastructure setup is part of this PRD, and no implementation time or cost estimate is asserted.
