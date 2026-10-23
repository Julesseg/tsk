# App design audit

Status: design interview complete. The user accepted the scope and interaction
decisions on 2026-10-21. No application changes have been implemented by this
audit; delivery steps and acceptance criteria below describe future work.

## Evidence and limits

Audited commit `c27a217295d143c1b923a9c3655d52a8058cf8a1` on 2026-10-20.
Reviewed current SwiftUI source, product direction, glossary and ADRs, and
screenshots exported from [CI run 39391064038](https://github.com/Julesseg/tsk/actions/runs/39391064038)
at that exact commit. Its main result bundles report 12 passing iPhone tests
and 10 passing iPad tests; Share has a separate bundle and is not included
in those counts.

Visual evidence covers iPhone 18 Pro Max and iPad Pro 13-inch (M5), iOS 27.0:
task lists, detail, capture/edit, Upcoming, Settings, view configuration and
largest-text Settings. This audit reused CI evidence and booted no simulators.
The accompanying local HTML report embeds selected captures with their test
identifiers. It is a baseline, not a before/after comparison.

Dense real-world task collections, populated Calendar, small iPhone layouts,
VoiceOver and physical interaction were not newly exercised. Settings children,
recurrence and Share findings below are source-based. Existing smoke success
does not establish the proposed design or the delivery of every feature.

The opening scaffold descriptions in `product-direction.md` and `prd.md` are
stale. Their workflow and domain decisions remain useful; current code and
runtime evidence establish what is built.

## Assessment

The native visual language is reasonably consistent. The main issue is
information hierarchy: optional fields, empty states, operational explanations
and raw storage values compete with the task and its next action. iPad spreads
the same long form over a wide detail column without making planning easier
to reach. Broad replacement of navigation or visual styling is not yet justified.

| Finding | Evidence | User consequence |
| --- | --- | --- |
| Rescheduling requires the full editor | `App/Tsk/TaskListView.swift:92`, `App/Tsk/UpcomingTaskList.swift:37`, `App/SharedTaskForms/TaskPlanningSection.swift:15` | A declared primary action has no direct list control; Today/Tomorrow also require enabling Planned day first. |
| Task rows stack metadata independently | `App/Tsk/TaskListView.swift:67`, `App/Tsk/UpcomingTaskList.swift:16`, `App/Tsk/TaskAvailabilityView.swift:23` | Project, activity, dates, full blocker names and recurrence can consume multiple lines. Upcoming has a separate implementation and different context-menu actions. |
| Detail privileges completeness over decisions | `App/Tsk/TaskDetailView.swift:19`, `App/SharedTaskForms/TaskOrganizationSection.swift:95` | Empty priority, activity and dependency rows precede planning. Screenshots show planning below the initial viewport, even on a large iPad. |
| Raw information duplicates readable detail | `App/Tsk/TaskDetailView.swift:48`, `App/Tsk/TaskPlanningSummary.swift:25` | Every raw field and UUID is always rendered; start time is repeated. Errors have both a top banner and a bottom section. |
| Capture opens the complete metadata form | `App/Tsk/TaskEditorView.swift:27`, `App/TskShare/ShareCaptureView.swift:89` | Simple capture carries project, priority, tags, three date controls and explanatory copy. |
| Calendar consumes the start of Today | `App/Tsk/TaskListView.swift:15`, `App/Tsk/TodayCalendarSection.swift:10` | Permission/setup copy or every event precedes tasks. The largest-text capture makes that competition especially apparent. |
| Choosing views is mixed with configuring tabs | `App/Tsk/TaskSettingsView.swift:10`, `App/Tsk/CustomViewsView.swift:67`, `App/Tsk/CustomViewsView.swift:104` | Views opens in persistent edit mode; inactive predefined views cannot simply be opened, while inactive custom views open their editor. |
| Integration screens mix operation and diagnostics | `App/Tsk/SyncSettingsView.swift:25`, `App/Tsk/TaskNotificationSettingsView.swift:33`, `App/Tsk/ContinuousReminderSettingsView.swift:21` | Current state and the useful next action compete with credentials, counters and explanatory text. |

## Agreed presentation changes

The accepted interaction direction replaces the earlier detail/sheet cleanup
proposal. Deliver it through the three bounded steps below.

### 1. Scan and act from task lists

Use a shared row and action presentation in Today, Upcoming, projects and
custom views. Keep the description primary, with deadline and compact relevant
context, including recognizable waiting/blocked/active state. Planned day is
organizational information and does not appear as task metadata on a collapsed
row; retain it for scheduling and view organization. Summarize blocker counts
in the list and retain full reasons in the expanded editor. Do not impose fixed
heights at accessibility text sizes.

Add a direct Plan action: Today, Tomorrow, Choose day, Remove planned day.
It changes the planned day only. Completion uses a visible circle beside each
unfinished task. Remove swipe-to-complete; rightward swipes belong to selection.
Make action availability consistent between ordinary and Upcoming rows.

Acceptance: planning from a row uses the compact parameter controls and leaves
the deadline unchanged; Upcoming retains its distinct planned/deadline entries;
occurrence actions keep their correct scope; long titles, multiple blockers,
active work, errors and accessibility sizes remain understandable. Verify with
Core tests where behavior changes and canonical iPhone/iPad XCUITest plus
matched baseline/proposed captures using realistic populated fixtures.

The original audit scope excludes task ordering/filter changes, recurrence
behavior, replacement of workspace/tab navigation and a new visual theme.
The [iPad layout follow-up](#ipad-layout-follow-up-2026-10-22) reopens iPad
navigation separately.

### 2. Expand the task row into its editor

Accepted: remove task detail and show meaningful task information in the editor.
The editor expands the row inside the current list, replacing the native sheet
and separate page. Neighbouring rows move aside and the surrounding list dims.
Tapping outside collapses the row.

Morphing means that already-visible elements move to their expanded positions,
newly revealed controls fade in, and the component container changes size to fit
the layout. Reverse the transition when collapsing. See ADR-0004.

Hide raw technical information entirely from the app rather than moving it to a
disclosure: no UUID inspection or raw storage dictionary. Preserve underlying
task data. Whether configured user-defined attributes count as technical
information has been resolved: meaningful configured fields, such as Energy,
remain editable using their labels. Raw storage inspection is removed.

Accepted layout: editable title first, then dedicated custom parameter
components arranged horizontally. Each component displays a task parameter and
opens its editing control when tapped: for example, a date picker or tags
selector. Use these components for project, tags, priority and scheduling;
annotations, dependencies and meaningful custom fields remain available below.
Start/Stop is secondary. Remove duplicated values and use one actionable error
presentation. Completed tasks and recurring templates retain action restrictions.
iPad and accessibility routes follow the in-list editing direction too.

Accepted: tapping outside saves valid changes and collapses the editor; no Cancel
button. A blank new row disappears. Invalid input or save failure leaves the
editor open with its draft and error. The outside tap only closes the editor;
it does not activate the dimmed row underneath.

Keep the edited row anchored until editing finishes. Collapse first, then apply
normal filtering/grouping so changes do not move the row while it is being
edited. Existing links from Spotlight/dependencies reveal a list containing the
task and expand its row, with a route back to the previous list.

Existing tasks expand without raising the keyboard; capture immediately focuses
the title. Grow naturally up to the available screen height, then scroll inside
the expanded component. Keep the focused field above the keyboard. Provide a
small collapse control with the same save behavior as outside tap. Only one row
is expanded at a time. Motion respects system accessibility preferences without
changing the interaction's meaning.

Completion Undo is explicitly out of scope. Do not implement draft persistence
or restoration: retention supplied by the existing app/system lifecycle is
enough, and losing an unsaved draft after process termination is accepted.

Parameter editors form a separate dismissal layer: tapping outside an open
picker closes that picker only and leaves the task expanded. Choices update the
task draft. A subsequent outside tap saves and collapses the expanded row.

### 3. Reduce capture to a short task draft

Accepted: capture inserts a new row in the current task list and immediately
expands it into editing with the same morphing animation. Do not switch task
views or open a sheet merely to capture.

Lead with description, project and direct planned-day choices. Offer compact
controls for tags, priority, deadline and waiting date, expanding their editors
when used. Existing populated fields must be apparent when editing. Apply the
same parameter components to Share while preserving shared text/URLs and
review-before-save.

Accepted defaults: Today capture starts planned for Today; project capture
inherits that project; other task views leave planned day unset. Defaults are
visible and editable. Insert the draft at the top of the task area below Calendar
and pin it while editing. If the saved task does not match the view, remove it
after collapse with brief confirmation that it was saved.

Share is an accepted presentation exception: reuse compact editor content in
the system Share panel, with explicit Add task to save and close. Dismissing
without Add creates nothing. Do not add a custom Cancel button.

Acceptance: description-only capture requires no optional configuration;
Today/Tomorrow works without first enabling a switch; collapse/save remains
reachable with the keyboard visible; validation and empty-draft dismissal follow
the accepted rules. Share Add stays reachable and only closes after durable save.
App and installed Share flows need their respective runtime verification.

### 4. Keep Today focused while retaining Calendar

Accepted: Calendar stays above tasks. Present compact event rows containing
only time and title, with no Calendar section title. Omit event location,
calendar name, continuation explanations and routine footer text from this
presentation. Calendar remains display-only. Hide Calendar entirely when there
are no events. With missing access, show a compact Enable Calendar control;
with a read failure, show compact Retry feedback. No empty section, heading or
explanatory paragraphs. The earlier tasks-first, expandable-summary proposal
was rejected.

Acceptance requires populated Calendar and denied/not-yet-requested states,
many events, empty tasks, largest text and both device families.

### 5. Edit multiple tasks

Accepted action set: planned day, deadline, project, tags, priority and completing
selected tasks. Descriptions, dependencies and recurring-series changes remain
individual operations.

Accepted selection gesture, inspired by the user's description of Sorted3:

- Swipe a task right by about one quarter of the task-list column width to select
  it and enter selection mode; on iPad use the column rather than device width.
- Enter selection mode immediately on crossing the threshold, before finger-up.
- Completion circles on every task become selection circles, filled for selected
  tasks.
- Continue the gesture vertically to select tasks it touches. This selects tasks
  rather than repeatedly toggling them on re-entry.
- Disable list scrolling during the selection gesture.

Accepted: selection mode persists after release and scrolling resumes, allowing
selection through multiple gestures. Tapping a selection circle toggles that
task. Done exits selection mode. Upcoming's repeated appearances share one
selection and count as one task.

Show a bottom action bar with selected count and access to Plan, Deadline,
Project, Tags, Priority and Complete. Each action opens focused controls rather
than expanding every selected row. Provide a Select command for keyboard and
accessibility use.

Each operation changes only its chosen field, preserving others. Clearing is
explicit. Tags offers Add and Remove, preserving other tags. Save the selected
changes together or none; on failure retain selection and explain the problem.

Bulk controls use an explicit Apply action, committing once rather than changing
stored tasks while a date picker is being scrolled. After success, retain the
selection of tasks still visible so another operation can follow. Completed
tasks and tasks no longer matching the view leave the selection. Exit selection
mode when none remain, when changing task views or when Done is tapped.

Current code supports one selected task (`ContentView.swift:41` and
`TaskListView.swift:6`), and the store updates/completes one task and reloads
after each mutation (`TaskStore.swift:178`). Atomic multi-record storage exists
in `Core/Sources/TskCore/TaskOccurrences.swift:3` and
`Native/Sources/TskNative/TaskChampionReplica.swift:30`; this is infrastructure,
not an existing general multiple-task editing feature. Upcoming may show the
same task twice, so selection must count unique tasks. Occurrence completion
also updates series bookkeeping; a bulk operation must preserve that behavior.

## Three delivery steps

### Step 1: Task presentation and parameter components

Build shared collapsed-row presentation and reusable horizontal parameter
components with their focused editing controls. Show deadline rather than
planned day on collapsed rows. Add visible completion circles and remove swipe
completion. Compact Calendar above tasks to time/title only, including the
accepted empty, permission and error states.

Acceptance: review populated Today, Upcoming, project and custom lists on both
device families; long titles, waiting/blocked/active tasks, deadlines, all-day
events, empty/denied Calendar, light/dark appearance and accessibility text must
remain legible. Preserve Upcoming's planned/deadline grouping distinction.
Exercise completion through the visible control. This step supplies the shared
components; it does not claim the final editor/selection workflow is complete.

### Step 2: In-place editing and capture

Compose the parameter components into the morphing row editor and draft row.
Implement anchoring, dimming, keyboard/overflow behavior, layered picker
dismissal and save-on-collapse. Remove task-detail navigation and the main
editor sheet, including the iPad detail column. Route existing task links into
the containing list with a route back. Hide technical inspection and retain
meaningful configured fields. Adapt Share content with its explicit Add task
exception.

Acceptance: canonical iPhone/iPad runtime journeys must cover editing, capture,
outside/collapse saving, blank drafts, invalid input, save failures, tasks moving
out of the current view, deep links, keyboard use and largest text. Verify the
installed Share flow separately. Match screenshots across collapsed/expanded
states; inspect actual transitions and Reduce Motion behavior. Synthetic or CI
screenshots alone do not establish animation quality or physical interaction.

### Step 3: Gesture selection and atomic multiple-task actions

Add the threshold-triggered rightward selection gesture, continued vertical
selection with scrolling disabled, persistent selection and the bottom action
bar. Reuse the parameter controls with Apply. Implement atomic field operations
and completion in Core/Native, preserving occurrence bookkeeping and unrelated
attributes. Do not implement multiple edits by looping the existing UI's
single-task mutation/reload path.

Acceptance: Core/Native tests cover explicit clearing, mixed values, Add/Remove
tags, no partial changes on failure and multiple occurrences sharing a parent.
Runtime coverage must exercise crossing the threshold before finger-up,
continued vertical selection, no scrolling during the drag, resuming scrolling
after release, unique task selection in Upcoming, apply/failure/selection
reconciliation and keyboard/accessibility alternatives. Keep the displayed row
positions stable during a drag even if remote updates arrive. Physical touch
acceptance is required in addition to canonical iPhone/iPad CI checks.

The full UI lane is required before accepting workflows outside smoke coverage,
following `docs/verification/ci-test-tiers.md`. No delivery estimates are implied.

## Deferred secondary work

Integration settings: consistent order of current status, relevant action,
preferences/configuration, then troubleshooting. Keep source deletion and
retry consequences visible at Reminders move decisions. Recurrence: simplify
everyday wording but preserve occurrence/series distinctions and mandatory
affected-task previews.

Accepted in the original audit: tab navigation remains unchanged. The
[iPad layout follow-up](#ipad-layout-follow-up-2026-10-22) supersedes that
constraint for iPad. The original effort focuses on task presentation, capture,
editing, completion, scheduling and editing multiple tasks. Integration settings
and recurrence-help cleanup are deferred proposals, not part of the agreed focus.

## Constraints carried forward

Planned day and deadline remain distinct (ADR-0003). Waiting or blocked tasks
matching Today remain visible with a reason. Calendar remains display-only.
Recurring template and occurrence actions remain distinct, with external
generation (ADR-0002). Reminders copy/move behavior remains as recorded in
ADR-0001. Preserve iPad keyboard workflows and accessibility while changing
presentation. Raw technical inspection is deliberately removed from the app;
hidden values remain preserved in storage and interoperability. No Taskwarrior
storage migration is proposed.

## Decision status

The interview frontier is empty: the user accepted the final picker-dismissal
and selection-lifetime decisions on 2026-10-21. The three delivery steps above
are the implementation proposal; the app has not yet been changed.

The glossary classifies Planned day as organizational. [ADR-0004](adr/0004-edit-tasks-in-the-current-list.md)
records the deliberate choice of in-list morphing over native navigation/sheets
and its layout, focus and gesture trade-offs.

## iPad layout follow-up (2026-10-22)

Status: design decisions accepted and the existing test seams confirmed.
The full specification is published as
[Spec: Clear iPad workspace with native adaptive navigation (#53)](https://github.com/Julesseg/tsk/issues/53).
Implementation ticket granularity and blocking edges still await approval.
No application changes have been implemented by this follow-up.

Accepted: use native adaptive iPad navigation, with a top tab bar that can
switch into a sidebar and bottom tabs in compact windows. This supersedes the
original audit's decision to leave iPad tab navigation unchanged. The current
source forces compact horizontal size class on the tab container to keep its
bar at the bottom; that behavior must give way to the native adaptive layout.

Accepted: the selected task view, including Today, Upcoming and project task
lists, occupies the main content area. Editing expands the task within that
list, following ADR-0004. Remove the reserved task-detail column so the task
list becomes the primary workspace instead of occupying a narrow leading
column beside task detail or an empty selection prompt.

Accepted: initially show the top tab bar on iPad. Let the user switch to the
sidebar and remember that presentation preference.

Accepted: the sidebar exposes all predefined and saved custom views. The top
tab bar contains the user's chosen favorites. The current four-active-view
model must not make other views inaccessible from the sidebar.

Accepted: center task rows within a comfortable reading width, with generous
margins in large windows. Adapt that width to the available window and text
size while keeping the task list in the main content area.

Accepted: place New task (+) in the upper-right toolbar in wide iPad layouts.

Accepted: group predefined views, an expandable Projects section with direct
project links, and saved custom views in the sidebar. Put Settings at the
bottom.

Accepted: retain up to four favorite tabs. Provide a Views toolbar menu for
opening any other view and managing favorites, including in compact iPad
windows. Opening a view and managing favorites are distinct actions.

Accepted: choosing another view saves valid edits and then navigates. Invalid
input or save failure keeps the current editor open with its draft and an
actionable error. An open parameter picker closes first, following the existing
dismissal rule; switching views requires a subsequent action. Existing blank
new-draft dismissal rules continue to apply.

Accepted: resizing, rotation and switching between tab and sidebar presentation
preserve the selected view/project, scroll position and open draft without
triggering a save. Preserve editing context in memory; this does not reopen the
earlier decision against draft persistence after process termination.

Accepted: a selected view outside favorites remains open when the sidebar
closes. Show its name as the content title and a checkmark in the Views menu;
opening it does not automatically add a favorite.

Accepted: when Projects shows the project-name overview rather than a task
list, New task opens All and inserts an expanded draft with no project or
planned day assigned. This is an explicit exception to the original audit's
rule against switching views for capture because no task list is open. Within
a specific project, capture stays in that task list and inherits the project.
Existing capture defaults continue to apply to other task lists.

Accepted: New task remains an upper-right toolbar action throughout iPad
layouts, including compact windows with bottom tabs.

This navigation redesign is scoped to iPad. The earlier audit's shared task
presentation and in-list editing decisions continue to apply to both device
families. Preserve the existing iPhone navigation while integrating this work.

### Verification planned for this follow-up

Use matched baseline/proposed captures from canonical iPad runtime journeys:
populated Today with Calendar, Upcoming, project and custom task lists; top
tabs and the full sidebar; the Views menu and favorite management; inline
capture/editing; empty lists; and largest accessibility text. Include landscape,
portrait and compact window layouts. Verify reading width, reachable toolbars,
and the absence of a reserved detail column. Keep iPhone regression captures
with the matching existing navigation states. Deliver the comparisons in a
single HTML UI report following the ui-report skill.

Exercise view changes during valid edits, invalid edits and save failures;
picker-first dismissal; and preservation of draft, selection and scroll context
across presentation/window changes. Update tests that currently require bottom
iPad tabs or task-detail navigation. Keyboard commands and focus must remain
usable; physical keyboard and live window-resizing acceptance remain separate
from injected simulator events. These are future acceptance checks, not
verification already performed by this design interview.

### User review: attribute pills and Scheduled (2026-10-23)

Replace the intermediate Today/Tomorrow/Choose day menu in the in-list editor
with the date control itself. Label Taskwarrior's `scheduled` date Scheduled;
its independence from the deadline is unchanged. Use rounded Liquid Glass
attribute pills in the horizontal strip, project first, displaying only an icon
and the current value when present. Project and priority are editable in this
strip. Coordinate a selected pill and its picker through a shared glass
container and identity where supported. Preserve the existing picker-first
outside dismissal and save-on-collapse behavior. Opening and closing the row
must avoid provisional-height, scroll-anchor and stale-value jumps.
