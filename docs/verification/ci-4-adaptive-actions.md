# Canonical UI failure correction, run 38655124794

The canonical run on `6fd5747` failed four of six iPad scenarios and five of nineteen iPhone scenarios (three iPad-only tests skipped on iPhone). This change preserves the original persistence, date-role, annotation, dependency, server and injected-keyboard expectations. Corrected runtime behavior remains pending canonical CI; generic compilation does not establish it.

## Actual evidence and changes

- iPad annotation and both automation failures looked for a child StaticText. Actual accessibility trees expose a native task Button with `task-<UUID>` and the task description as its label, with no matching StaticText. The shared task-row finder constrains both native identity and description, and works across compact and regular navigation. Native accessibility behavior is unchanged. Typed-attribute and synchronization scenarios use the same row seam.
- iPhone automation had already created the planned entry. Its actual Button identifier was `upcoming-planned-1792224000-7369B2A4-2886-480E-B2BA-DE6CA5A846BD`; the test omitted the timestamp. Assertions now match role and UUID while preserving distinct planned/deadline appearances.
- iPhone Waiting detail visibly contained Pending, exposed as combined `Status, Pending` rather than an exact Pending StaticText. The status row now has a stable identifier; waiting and dependency tests still assert the required status value.
- iPhone Add annotation and Add dependency synthesized valid taps at their visible button frames, but the resulting hierarchy remained task detail with no editor/selection sheet. Both presenters were attached to lazy Form Sections. TaskDetail now owns their routes and presents the corresponding sheets from the Form host. The advanced editor uses the same stable host. This is the leading presentation hypothesis; the next canonical run must confirm both original flows, including cycle rejection and durable annotation reopen.
- iPad Command-N opened capture, typing produced Keyboard task, and a real Command-Return event (Unicode13, command modifier16) left the editor open. Save was only a toolbar shortcut, whereas working workspace commands use scene Commands. Task and annotation editors now publish focused save actions to Commands; toolbar taps call the same action. Tests continue injecting Command-Return and asserting editor dismissal and persistence; no tap replaces the command.
- iPhone automatic-sync failure left a focused but empty description after synthetic typing, followed by an invalid Save hit point `{-1,-1}`. Connection Save/Sync/Disconnect/Done now clear secure-field focus before acting. The original save-after-error scenario remains, with additional keyboard readiness, exact entered-value, keyboard-dismissal and Save-hittability checks. The focus explanation is provisional until canonical execution; local persistence failure was not demonstrated by the capture.

The competing sheet hypotheses were wrong selector type, invalid/offscreen tap, and lazy presentation host. Actual full trees ruled out a visible alternative sheet/editor, and touch traces place the taps within the visible controls. Moving presentation to the Form host changes that boundary without altering task mutations. Keyboard alternatives were malformed Return event, missing input, and toolbar dispatch; the event and focused field contain the intended input, leaving scene routing as the tested correction. No blind rerun was requested.

## Gate integration

The iPad selection retains workspace, annotations, automation, recurrence, typed attributes and Reminders, and adds SynchronizationUITests. Both families now run the actual successful-server flow and request independent peer verification. The prior workflow requested peer verification only on iPhone; its peer check ran only when the entire suite succeeded, so the earlier passing manual-sync scenario alone is not peer proof. This change preserves that success gate, the owned real server, disposable device cleanup, EventKit evidence collection, simulator ad-hoc signing and intent/App Group metadata checks.

The largest-accessibility-type workspace scenario now attaches the actual accessibility tree and column frames and captures XCUIScreen. Earlier iPad app PNGs have EXIF orientation8 and misleading render rotation/clipping. They do not establish a production clipping defect. No speculative layout change was made. Inspect new geometry and screen captures before accepting large-text layout.

## Verification and evidence

- Core: 74 tests passed after integrating Reminders.
- Signed generic arm64 simulator App + XCUITest build-for-testing passed for the correction and again after integrating Reminders/root8963a73. Embedded App Group and create/find/complete/reschedule metadata verification passed.
- Workflow YAML parsed; embedded run blocks passed bash syntax validation; diff check clean.
- No local simulator boot, personal task/account access, push, CI retry or issue closure.
- Actual corrected iPhone/iPad execution, physical keyboard behavior, huge-text geometry and independent peer result remain pending canonical CI. Native business logic/ABI did not change here.

Original logs: `/tmp/tsk-issue-3/ci-ipad-116162950790.log` and `ci-iphone-116162950731.log`. Original bundles: `/tmp/tsk-issue-3/ui-38655124794-{ipad,iphone}/App/TestResults.xcresult`. Focused manifests, accessibility trees, original videos and extracted unmodified frames: `/tmp/tsk-issue-3/ui-ipad-4-{capture,automation-dates,automation-missing,keyboard,accessibility-full}` and `/tmp/tsk-issue-3/ui-phone-4-{autosync,annotations,automation,dependencies,waiting}`. Local report: `/tmp/tsk-issue-3/ui-ci-4-report.html`.
