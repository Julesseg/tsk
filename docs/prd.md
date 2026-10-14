# tsk product requirements document

## Problem Statement

Taskwarrior users need a capable, modern iPhone and iPad app that lets them capture work, decide what to do next, and act quickly while continuing to use their existing Taskwarrior clients. A mobile client must preserve task information and Taskwarrior behavior, work without a connection, synchronize promptly through TaskChampion, and participate in native iOS workflows.

The repository currently provides a greeting app, a pure SwiftPM Core module, and Core/XCUITest scaffolding. Task storage, TaskChampion integration, task views, recurrence controls, and system integrations described here are not implemented yet. This PRD turns the agreed product direction into an initial product contract without recording any personal infrastructure setup.

## Solution

Build a first-class native iOS/iPadOS Taskwarrior client with Liquid Glass and a thin SwiftUI app over a deep Core module. The primary workflow is capture, choose, and act. Provide Things 3-inspired Today, Upcoming, and project views; device-local custom views defined using Taskwarrior filters; a complete task editor; offline local persistence; and automatic synchronization with a configured TaskChampion server as soon as connectivity and iOS execution permit.

The initial product includes Shortcuts/Siri, widgets, Spotlight, text/URL sharing, calendar events displayed only in Today, notifications derived from task dates, and selected-list Apple Reminders import. Recurring templates can be created and edited in tsk, while one designated external Taskwarrior client generates occurrences. Optional on-device generation remains a later, lower-priority capability.

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
8. As a task owner, I want to set a planned day independently of a deadline, so that planning work does not change when it must be finished.
9. As a task owner, I want to set and change a waiting date, so that I can distinguish work that is not yet available.
10. As a task owner, I want to manage dependencies between tasks, so that I can see what blocks work and what becomes available after completion.
11. As a task owner, I want to start and stop work on a task, so that active work is represented consistently with Taskwarrior.
12. As a task owner, I want to complete tasks from the task list, so that routine actions do not require opening every task.
13. As a Taskwarrior user, I want to edit user-defined attributes through an advanced editor, so that my additional task fields remain usable on mobile.
14. As a Taskwarrior user, I want to define user-defined attribute types locally in tsk, so that editing and filtering can interpret those values correctly.
15. As a Taskwarrior user, I want to retain unfamiliar attributes when editing other fields, so that mobile edits do not discard information used by other clients.

### Task views and choosing work

16. As a task owner, I want to see tasks planned for today in Today, so that I can act on the work I intended for the day.
17. As a task owner, I want to keep unfinished tasks planned for earlier days in Today until completion or rescheduling, so that unfinished commitments do not disappear overnight.
18. As a task owner, I want to see tasks due today and overdue in Today, so that I can recognize approaching or missed deadlines.
19. As a task owner, I want to see matching waiting or blocked tasks with their reason in Today, so that I can understand why a planned or due task is not actionable.
20. As a task owner, I want to see future planned work grouped by day in Upcoming, so that I can review the days ahead.
21. As a task owner, I want to see future deadlines distinguished from planned dates in Upcoming, so that I can plan work without confusing it with its deadline.
22. As a task owner, I want to see a task at both its future planned date and its different deadline, so that both commitments are visible.
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

### Shortcuts, Siri, widgets, Spotlight, and sharing

52. As an iOS user, I want to create tasks through Shortcuts and Siri, so that capture can participate in native automation.
53. As an iOS user, I want to find tasks through Shortcuts and Siri, so that automations can work with existing tasks.
54. As an iOS user, I want to complete tasks through Shortcuts and Siri, so that I can act without navigating through the main app.
55. As an iOS user, I want to reschedule tasks through Shortcuts and Siri, so that native automation can update my task plan.
56. As an iOS user, I want to show Today in a widget, so that the day’s tasks are visible outside the app.
57. As an iOS user, I want to show a chosen task view in a widget, so that the widget can reflect the work I want to monitor.
58. As an iOS user, I want to complete tasks from a widget, so that a small task action takes minimal interaction.
59. As an iOS user, I want to open a matching task from Spotlight, so that system search leads directly to the relevant task.
60. As an iOS user, I want to share text into an editable task draft, so that information from another app can become actionable work.
61. As an iOS user, I want to share a URL into a task draft while retaining the link and shared text, so that the original content remains useful when I act on the task.
62. As an iOS user, I want to set project, tags, and dates while reviewing a shared draft, so that the task is organized before saving.

### Calendar and Reminders import

63. As a task owner, I want to see calendar events in Today alongside my tasks, so that I can account for existing commitments when choosing work.
64. As an iOS user, I want to display calendar events without creating or modifying them, so that calendar integration remains limited to the agreed purpose.
65. As an iOS user, I want to choose which Reminders lists to import, so that only selected sources enter tsk.
66. As a task owner, I want to use each selected Reminders list as the project for imported tasks, so that the existing list organization carries into Taskwarrior.
67. As an iOS user, I want to import incomplete reminders without an extra priority criterion, so that all eligible unfinished work is included.
68. As an iOS user switching apps, I want to run a one-time import that leaves original reminders in place, so that migration does not remove the source records.
69. As an iOS user, I want to enable continuous import that moves eligible reminders into tsk and removes successfully imported sources, so that Reminders can remain a capture entry point without retaining normal imported copies.
70. As an iOS user, I want to save each imported task durably before its source reminder is deleted, so that a failed destination save cannot remove my only copy.
71. As an iOS user, I want to keep the source reminder and see a failure when source deletion fails, so that an incomplete move is visible and does not lose the source.
72. As an iOS user, I want to retain no import provenance, processed IDs, or source-derived task identity, so that import does not leave an additional tracking model behind.
73. As an iOS user, I want to operate continuous import on one designated device, so that multiple devices do not normally race to import the same source.
74. As an iOS user, I want to understand that an interrupted move or later retry can produce a duplicate without bookkeeping, so that the importer does not promise an impossible exactly-once guarantee.
75. As a task owner, I want to manage imported tasks independently after import, so that later edits do not require two-way synchronization with Reminders.
76. As a task owner, I want to convert recurring reminders only when their complete rule has a verified supported mapping, so that the resulting Taskwarrior template preserves the supported recurrence semantics.
77. As an iOS user, I want to leave unsupported or unverified recurring reminders untouched and receive a reason, so that import does not silently flatten or destroy their recurrence.

### Notifications

78. As a task owner, I want to receive a notification at a task’s scheduled time, so that planned work becomes visible at the intended moment.
79. As a task owner, I want to receive a distinct notification at a different deadline time, so that I can distinguish planned work from a due task.
80. As a task owner, I want to receive one combined notification when scheduled and deadline alert times coincide, so that the same moment does not produce duplicate alerts.
81. As a task owner, I want to use an enabled-by-default 09:00 notification fallback for midnight-valued dates in the current device time zone, so that dates without a chosen time can alert during the day.
82. As a task owner, I want to change or disable the midnight notification fallback, so that notification timing matches my preferences.
83. As a Taskwarrior user, I want to keep stored scheduled and deadline dates unchanged when changing notification preferences, so that alert presentation does not rewrite task semantics.
84. As a task owner, I want to retain the specified time for dates that do not match the midnight convention, so that timed tasks are not silently shifted.
85. As a task owner, I want to receive registered local notifications while the app is closed, so that delivery of an already scheduled alert does not depend on foreground use.
86. As a task owner, I want to receive newly discovered missed alerts immediately after sync, so that a late-received task alert is not silently discarded.
87. As a task owner, I want to suppress missed alerts when the same sync reveals the task’s completed or deleted final state, so that reconciliation does not notify me about work that is already finished or removed.
88. As a task owner, I want to avoid receiving the same already delivered missed event again after every sync, so that newly discovered alerts remain distinct from repeated synchronization.
89. As a task owner, I want to cancel pending alerts when completion or deletion is known locally, so that tasks I have finished or removed do not retain pending reminders.
90. As a task owner, I want to reconcile pending alerts when dates change locally or arrive through sync, so that registered alerts reflect the latest known task state.
91. As an iOS user, I want to keep notification preferences specific to each device, so that one device’s alert preferences do not unexpectedly alter another’s.

### Native experience and permissions

92. As an iPhone user, I want to use a compact native capture-and-action workflow, so that daily task management fits the phone.
93. As an iPad user, I want to use an adaptive layout with keyboard support at launch, so that the larger screen and keyboard improve task management.
94. As an iOS user, I want to use native navigation, typography, gestures, accessibility, appearance, and Liquid Glass, so that tsk behaves as a first-class iOS app.
95. As a task owner, I want to scan compact lists and reveal additional detail when needed, so that the interface balances density with clarity.
96. As an iOS user, I want to retain ordinary task management when Calendar, Reminders, or notification permissions are denied or revoked, so that optional system access does not prevent use of my tasks.
97. As an iOS user, I want to receive clear permission and integration failure states, so that I can understand which requested capability is unavailable.

## Implementation Decisions

### Modules and interfaces

- Core is the platform-independent module for task behavior. The SwiftUI app stays thin. iOS extensions and actions use the same Core behavior rather than implement competing task rules.
- Introduce one primary public task-management interface in Core through which callers and behavior tests create, edit, complete, query, plan, and synchronize tasks. Keep field validation, view membership, filter evaluation, recurrence bookkeeping, import orchestration, and notification planning behind that interface.
- Reuse the existing Core and XCUITest testing seams. Where platform execution actually varies, supply concrete adapters for persistent TaskChampion data, synchronization, EventKit, notification registration, clock/time zone, and system entry points. Keep adapter details internal where possible; do not create a public interface for each individual field or UI action.
- Keep platform-independent decisions testable without EventKit or UserNotifications. Actual OS reads, writes, permission requests, scheduling, and extension execution belong in platform adapters; their results flow back through the Core interface.
- Preserve task identity and unfamiliar attributes. User-defined attribute definitions are configured locally. Do not round-trip tasks through a reduced schema that discards fields another client understands.
- Pin the supported Taskwarrior and TaskChampion versions before claiming compatibility. Select and verify the Swift integration route separately; this PRD does not assert that an existing bridge or Taskwarrior library has already been proven to work on iOS.

### Dates, task views, and filters

- The planned day uses Taskwarrior’s scheduled attribute; the deadline uses its due attribute. Starting work is a separate state and must not be used as the planned day.
- Today contains unfinished tasks planned for today or an earlier day, and tasks due today or overdue. An unfinished planned task remains until completed or rescheduled. Matching waiting or blocked tasks remain visible with their reason. Calendar events appear in Today only.
- Upcoming groups future planned work and future deadlines by day, labeling their roles. A task can appear on two dates when its planned date and deadline differ.
- Provide project views and actions directly from lists. Templates and ordinary occurrences remain distinct domain concepts.
- Custom views accept Taskwarrior filter expressions entered in tsk. Use documented Taskwarrior defaults and local attribute definitions. Do not import desktop reports, contexts, or configuration.
- TaskChampion’s storage interface is not a Taskwarrior filter evaluator. Implement or reuse compatible evaluation and verify its behavior against the pinned Taskwarrior version, including boolean expressions, modifiers, relative dates, virtual tags, dependencies, and typed custom fields. Explicit errors must not become an excuse to silently replace the requested language with a smaller tag/project filter builder.
- Saved custom views remain device-local. Notification preferences also remain device-specific.

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

### Apple Reminders import

- Let users select source lists. Each selected list maps to the project for its imported tasks. Import incomplete reminders only, without an additional priority or importance filter.
- One-time import copies eligible reminders and leaves the originals in Reminders. Continuous import moves eligible reminders and removes successfully imported sources.
- Commit a valid destination task or recurring template durably locally before deleting its source. Never delete the source following a failed destination save. If source deletion fails, preserve the reminder, show the failure, and avoid repeatedly copying it within that running attempt.
- Retain no provenance fields, processed reminder IDs, source-derived task identities, import history, or durable import bookkeeping. Source-list selection and its project mapping are operating configuration, not a retained per-item tracking model.
- Run continuous import on one designated device, with it disabled on other devices. An interrupted save/delete sequence or a later retry can still duplicate a task; this trade-off was explicitly accepted. Do not claim cross-store atomicity or exactly-once import.
- Imported tasks are managed independently. There is no subsequent source-edit propagation, export, or two-way synchronization.
- Convert a recurring reminder only when its full rule has a verified supported mapping into a Taskwarrior template. Skip unsupported or unverified rules, leave the source untouched, and explain the reason. Never silently flatten recurrence or delete the source after an approximate or partial conversion.
- Establish supported EventKit field and recurrence conversions with real interoperability checks. Similar frequency labels do not establish equivalence around selectors, completion-gated recurrence, time zones, daylight saving, month ends, or end conditions.
- Continuous import can react to source changes and available execution opportunities. Do not promise instant background ingestion when iOS does not run the app.

### Notifications and other iOS capabilities

- Derive notifications from scheduled and deadline times. Do not require a separate opt-in reminder time on each task. Different times produce distinct planned/due alerts; coincident effective alert times produce one combined alert.
- Start the midnight-time replacement enabled at 09:00 in the device’s current time zone. Allow choosing another time or disabling replacement. It affects notification timing only; stored task dates remain unchanged. Other timestamps retain their specified times.
- Treat midnight as a convention, not recovered input precision: Taskwarrior does not retain whether midnight was explicit. Do not advertise reliable detection of a date entered without a time.
- Reconcile the final local/synchronized task state before producing alerts. Cancel pending events for completed/deleted tasks. On sync, fire newly discovered missed events immediately unless the final state is completed or deleted. Do not fire an already delivered event again on every sync.
- Reconcile registrations when task dates change. Register local notifications so existing schedules can fire while the app is closed. Remote completion cannot cancel a stale local alert until the relevant change reaches the device; do not imply automatic server-side cancellation.
- Shortcuts/Siri support create, find, complete, and reschedule. Widgets support Today or a chosen view and task completion. Spotlight opens matching tasks.
- Sharing text or a URL opens an editable draft retaining the shared content, with project, tags, and dates available before save. File attachment storage is not initial scope.
- Calendar integration reads events for Today and creates no calendar events or time blocks. Permission denial or revocation leaves ordinary task management usable.
- iPhone leads everyday capture and action. iPad gets adaptive layout and keyboard interaction at launch. Use native iOS navigation, typography, gestures, accessibility, appearance, and Liquid Glass.

## Testing Decisions

The user confirmed Core’s public task-management interface, the existing XCUITest suite, and real adapter checks as the testing seams.

- Good tests exercise observable behavior through the same interface used by callers. Check persisted results, task identity, returned views, synchronization state, and platform effects. Avoid tests that merely repeat field assignments, inspect private implementation structure, or pass only because a mock reproduces the implementation.
- Core’s current Swift Testing greeting tests provide the fast, platform-independent testing lane, not task behavior prior art. Extend that lane with scenario-based tests through the proposed task-management interface. The current XCUITest launch/greeting smoke test establishes the UI lane; it is not evidence that any task feature exists.
- Use deterministic time, time zones, and controlled adapter results for meaningful Core scenarios. Prefer a small number of whole workflows over separate seams for each field or view.
- Verify create/edit/complete/query workflows survive reopening local storage, retain UUIDs and unknown fields, and keep local edits during sync failures. Exercise multiple clients against a real TaskChampion setup before claiming convergence; mocked sync success is insufficient.
- Compare Taskwarrior filter results against the pinned Taskwarrior client using shared task fixtures. Cover expression operators, parentheses, attribute modifiers, relative dates, virtual tags, dependencies, typed user-defined fields, missing values, and explicit invalid/unsupported-expression errors.
- Exercise Today and Upcoming at day boundaries: overdue, prior planned days, future planned/deadline dates, tasks present at both dates, completion, rescheduling, waiting/blocked inclusion, and planned-versus-deadline separation. Verify calendar events appear only in Today.
- Round-trip recurring templates through a real external Taskwarrior generator. Verify creation, occurrence return sync, occurrence completion bookkeeping, single-occurrence edits, effective-date series edits, preserved completed history, masks/relationships, and continued generation without duplicated or missing instances. Include date boundaries, relative dates, month ends, leap days, and daylight saving in the supported contract.
- Test one-time import leaves sources unchanged and continuous import deletes only after durable destination save. Inject destination-save failure, deletion failure, and interruption between stores; verify source preservation and honest duplicate limitations rather than an exactly-once assertion. Verify completed and unselected source items are excluded, lists map to projects, and no per-item provenance or bookkeeping is retained.
- Verify each supported recurring-reminder conversion against both actual EventKit data and the pinned external generator. Unsupported/unverified rules must remain untouched and be explained; verify source deletion scope for a supported recurring set before claiming safe continuous migration.
- Verify notification planning through Core, including the 09:00 default, custom/disabled replacement, unchanged task dates, distinct/combined events, final-state completion/deletion suppression, immediate newly missed events, repeat prevention, and pending cancellation/rescheduling. Test actual delivery and registration reconciliation on iOS; do not assume the deprecated notification API’s capacity is the current limit.
- Grow the existing XCUITest suite with capture/edit/list actions, Today/Upcoming/projects/custom views, offline use and visible retry states, occurrence-versus-series editing, settings, import results, and graceful denied-permission states. The macOS CI XCUITest job is the canonical UI gate; local simulator execution is optional.
- Exercise Shortcuts/App Intents, share extension, widgets, Spotlight, Calendar/Reminders access, and local notification delivery using real platform adapters in simulator or device environments as appropriate. Where CI cannot prove account or background behavior, record the missing evidence and require the relevant integration/device verification before claiming support.
- Verify adaptive iPad behavior, physical keyboard interaction, system appearance, and accessibility. Simulator/CI success alone does not prove physical keyboard, background timing, or external-account behavior.
- A documentation review or green scaffold CI does not fulfill these feature-level checks. Every delivered capability needs evidence at its stated seam, with unsupported cases and remaining verification limits reported explicitly.

## Out of Scope

- On-device occurrence generation in the initial release, including an enabled recurrence generator or automatic takeover from another generating client. Optional iOS generation is later and lower priority.
- Guaranteed immediate background sync/import or exact background generation timing.
- Desktop report, context, or configuration import.
- Synchronization of saved custom views between devices or of device-specific notification preferences.
- Creating or modifying calendar events, time blocking, or displaying calendar events as an Upcoming integration.
- Export or two-way synchronization with Apple Reminders, updating source reminders after one-time import, and propagating later source changes into independently managed tasks.
- Persistent per-item import provenance, processed IDs, source-derived task identity, or exactly-once import guarantees across separate stores and retries.
- Importing completed reminders, additional priority-based source selection, silently flattening unsupported recurrence, or deleting unsupported recurring sources.
- File attachment storage and a dedicated Mac experience.
- Provisioning or configuring any personal external generator or server. The PRD describes generic client capabilities only.
- Implementing the application as part of publishing this PRD. It specifies the product; the current repository remains a scaffold.

## Further Notes

- The agreed source brief, glossary, ADRs, and primary-source research are in documentation PR #2: https://github.com/Julesseg/tsk/pull/2. Its Core and XCUITest checks passed for documentation/scaffold changes, not the capabilities specified here.
- This is an umbrella product spec. Preserve the complete initial scope when it is decomposed into implementation milestones. Do not drop UI or system integrations because one execution environment cannot run them locally.
- Repository policy places business behavior in Core and keeps the UI thin. Core tests are the fast loop; CI is the canonical app UI gate. Future implementation work must include its UI and be delivered through working-branch pull requests.
- The exact Swift/TaskChampion binding, supported version pins, verified EventKit field mappings, safe series-edit bookkeeping, notification capacity/registration strategy, and device/account verification are implementation work. Do not present them as solved by this document. Avoid publishing an unverified list of supported recurrence conversions.
- Native task attributes do not preserve input precision or original time-zone metadata. The midnight fallback is an explicitly accepted notification convention, not a change to Taskwarrior storage semantics.
- Neither TaskChampion property writes nor its sync server execute Taskwarrior’s recurrence validation, series propagation, mask updates, filter evaluation, or occurrence generation automatically.
- No personal infrastructure setup is part of this PRD, and no implementation time or cost estimate is asserted.
