# Task title and date editing in the current list — issue 41

Editable ordinary tasks and valid unfinished occurrences expand in Today,
Upcoming, project and custom lists. The completion circle stays in place;
title, project and deadline use matched geometry, the row changes height and
new controls fade in. Other rows dim and cannot receive the closing tap.
Reduce Motion removes the explicit morph, collapse and focus-scroll animations.

The expanded row has a title field, horizontal planned-day/deadline/waiting-date
parameters, full availability reasons, a collapse control and a route to
supporting task information. Existing tasks do not focus a field on expansion.
The editor measures its content, grows to the available list height, and then
scrolls internally. Its available height follows keyboard/layout changes.
The parameter picker also scrolls when its content exceeds available height.

Today, Tomorrow, Choose day and Remove planned day need no enable switch.
Opening a parameter alone does not change a stored date. Choosing a value
changes the draft; an outside tap dismisses the picker only. The next outside
tap, collapse control, Command-Return or Escape validates, saves and collapses.
Blank descriptions and persistence failures keep the draft and actionable error.
No Cancel, completion Undo or draft restoration is added.

`TaskRowDraft` in Core owns title validation, planned-day calendar boundaries
and the patch restricted to description, scheduled, due and wait. Hidden fields
and unrecognized dates remain unchanged unless the user edits that parameter.
The existing manager preserves ordinary/occurrence restrictions and atomic
occurrence mutations. Supporting information and its existing editors remain
reachable through More task information; their migration is separate work.

An editing session freezes the visible records and Upcoming day groups.
Mutation/reload can update the underlying task collection, but the frozen
presentation stays until the collapse animation completes. Only the selected
Upcoming appearance expands; its other appearance dims. Keyboard expansion
resolves the same appearance identity as rendering and refuses missing rows.
No draft is written outside the normal task-save operation.

## Verification

Core tests cover independent planned/deadline/waiting values, hidden fields,
blank-title rejection, real boundary-level write failure, occurrence/sibling
scope, recurring-template rejection and chosen-day normalization over Paris DST.

`TaskRowEditingUITests` exercises save/relaunch, invalid draft retention,
parameter-first outside dismissal, direct planned-day choices, focused date
controls, title/keyboard geometry, occurrence save failure at accessibility
XXXL, Upcoming anchoring and post-collapse membership. Appearance captures run
on both device families. The existing iPad native-keyboard journey now edits
an Upcoming row; supporting-information tests follow the new information link.
These five new methods run in both smoke and full selections.

The report records actual source revisions, captures, animation recordings and
results. Simulator checks do not establish physical touch, spoken VoiceOver,
personal account behavior or distribution provisioning. A source check of
Reduce Motion is separate from runtime verification of the system setting.

The lower-list XCUITest first failed because expansion left its supporting
information control below the visible list. Opening now brings the expanded
row fully into view using a top scroll anchor, clamped by the list's content
extent, while preserving its frozen group and identity. The keyboard viewport
change reveals that same row again; the iPad regression asserts that its title
is above the software keyboard. Core also checks that merely opening/closing
an imported title with stored whitespace does not normalize it.

Fullscreen docked-keyboard geometry is exercised. Moved Stage Manager windows
and floating keyboards are unverified; keyboard notifications use screen
coordinates while the row geometry uses window coordinates. Native keyboard
command delivery is a separate canonical HID CI gate. Local controller/Native
host suites were not run because this checkout has no host bridge library;
Core and simulator verification do not substitute for those CI checks.
The local `XCUIElement.typeKey` fallback failed at
`iPadWorkspaceUITests.swift:28`: Command-Return did not dismiss the existing
new-task capture, before the inline edit journey began. Its canonical HID
CI result remains pending; the overall iPad result bundle therefore contains
five passing row-editing methods and this one failing keyboard method.

## Recorded local results

After fetching and merging `origin/main` (already current at `d3c14fe`),
`cd Core && swift test` passed all 167 tests. UI-selection tests passed 14/14;
CI routing tests passed 12/12. A signed Xcode 27.1 simulator build succeeded.
All five new methods passed on each device family in
`/tmp/tsk-41-phone-verified.xcresult` and
`/tmp/tsk-41-pad-verified.xcresult`.
The existing iPhone durable edit/completion journey also passed in
`/tmp/tsk-41-phone-final.xcresult` before the final keyboard viewport fix.

Both standards and issue-spec reviews have no remaining findings in the
canonical fullscreen paths. The window-coordinate limitation above remains
an explicit acceptance gap.

## UI report

App source: `e91c88ab05aae391976fef2c687e3286c0bc5507`.
Signed base source: `d3c14fe3be2d8cef07ce63d75c835a7e9a128ebf`.

Local report: `/Users/julesseguin/.local/share/ui-reports/tsk/label-and-implement-with-pr-issue-41/20261022/report.html`

Measured size: 3,040,316 bytes. It contains 78 screenshots
(including labelled iPad readability crops) and four actual animation excerpts.
Chrome verification at a 390-pixel inner viewport decoded all 78 images,
opened all 30 sections, reported a 390-pixel document width, and verified
image enlargement. Full native captures and recordings remain source evidence
under `/tmp/tsk-41-evidence`; the report is the single deliverable HTML file.
Both simulators booted for verification were shut down.
