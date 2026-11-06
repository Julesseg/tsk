# Capture tasks in the current list

Issue #44 replaces the main app's creation sheet with the shared expanding row.
Today inserts it below Calendar, other lists insert it before their tasks, and
Upcoming retains its day groups below the draft. The current list snapshot stays
frozen until collapse. Today supplies an editable Scheduled date for today; an
exact project list supplies that project; custom and other task views supply no
Scheduled date. The Projects overview opens its No project task list, including
when All is not an active tab.

The title focuses on expansion. Capture reuses the row's Notes and horizontal
project, tags, priority, Scheduled, Deadline and Waiting controls. Actions that
need an existing task (activity, dependencies and information) appear after save.
A blank title discards the new row. Valid input saves once before collapse;
validation or storage failure retains the editor, input and error. Repeated
capture retains the current new draft. Starting capture from an existing editor
first finishes its valid edits; invalid edits stay open. A nonmatching task leaves
the list after collapse with a three-second Saved confirmation.

Capture-tab actions arbitrate against outside-tap saves in the same input event.
There is no capture Cancel control or draft restoration store. Existing task
information retains its separate edit form. Share retains its current automatic
plain-text/URL capture behavior; its older explicit Add requirement was superseded
by the existing Share simplification.

## Verification boundaries

- Core tests exercise editable Today/project defaults, absence of Scheduled in
  other views, notes/tags conversion, validation and ordinary task persistence.
- The capture controller target compiles production TaskStore and TaskRowEditing
  through relative symlinks. Its in-memory storage boundary covers failed-save
  retention/retry, duplicate prevention, blank dismissal and existing-editor
  protection. Its display-link stand-in does not establish animation behavior.
- iPhone XCUITest covers immediate focus, blank dismissal, repeated capture,
  durable reopen, project defaults, Upcoming and custom-view nonmatching capture.
  Existing fixture creation now uses shared row controls; information edits still
  use their existing form.
- Full iPhone CI remains required for workflow acceptance, including actual
  hardware-keyboard transport and installed system integration journeys.
- ADR 0007 supersedes the issue's historical iPad requirement. Physical-device
  input, distribution provisioning and iPad behavior are not established here.

Local runtime results and the visual-report path are recorded in the PR, with
unsuccessful attempts kept distinct from the final source's verification.

## Local evidence on 2026-11-05

Core: 178 tests passed. Native: 176 tests passed, with the existing optional
Taskwarrior oracle case skipped. All controller targets passed, including four
capture lifecycle cases. The 24 UI-selection checks passed. The signed iPhone
build-for-testing passed.

The custom-view and Upcoming journeys passed. The project journey verified
capture defaults and durable reopen, then twice missed its unchanged two-second
completion-removal deadline, with Completed feedback present. The focused capture
journey verified focus, blank dismissal and retained input, then missed the saved
row deadline while its durable-save collapse was still in progress. These are not
clean runtime acceptance. Measured host load reached 428 with 31.8 GB swap in use;
further local device work stopped, and the task-owned simulator was shut down.
Existing booted devices were preserved. No deadlines or required assertions were
relaxed. The final test also requires a dismissed keyboard and admitted hit target
before repeated New task input; canonical CI must verify that final source.

The local report is
`/Users/julesseguin/.local/share/ui-reports/tsk/agent-issue-44/20261105/report.html`.
It explicitly lists missing matched baseline, populated Calendar/neighbors,
accessibility-size, storage-error and clean animation captures. These gaps and
actual hardware-keyboard transport remain pending full iPhone evidence.

## PR smoke diagnosis

At `d0c7710`, PR smoke passed three methods and failed repeated capture at
`TskUITests.swift:27`. New task was enabled at `(357, 873, 62, 62)` but failed
native hit admission for all 17 samples within the unchanged twenty-second
budget. The captured hierarchy exposed an invisible `task-row-outside` Button
at `(0, 320, 440, 636)`, spanning the tab bar beneath the editor. The rollup
correctly failed because this shard failed; it had no separate gate error.

The viewport correction limits the outside-region accessibility metadata to
the task list's lower edge, matching the existing outside-save gesture guard.
It preserves the visual dimming path, shared animation, native tab control,
readiness policy, assertions and deadlines. The existing capture journey is the
regression seam: it must actually admit and activate New task, retain one title,
save, and reopen the durable task.

A reused local simulator stopped earlier because its keyboard frame was outside
the app window, so that run did not reproduce the CI symptom. A disposable phone
was created for a matched control, but the Device tool could not discover/open
it even after its prescribed inventory refresh and retry. Local device work
stopped; the unused phone was deleted and the booted probe device shut down.
Compilation/controller checks supplement the required new-head canonical CI;
no local native hit-testing pass is claimed.
