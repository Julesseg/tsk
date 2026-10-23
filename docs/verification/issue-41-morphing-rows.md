# Task title and date editing in the current list — issue 41

Editable ordinary tasks and valid unfinished occurrences expand in Today,
Upcoming, project and custom lists. The completion circle stays in place;
title, project and deadline use matched geometry, the row changes height and
new controls fade in. Other rows dim and cannot receive the closing tap.
Reduce Motion removes the explicit morph, collapse and focus-scroll animations.

The expanded row has a title field, a horizontal strip of rounded Liquid Glass
attribute pills, full availability reasons, a collapse control and a route to
supporting task information. Existing tasks do not focus a field on expansion.
The editor measures its content, grows to the available list height, and then
scrolls internally. Its available height follows keyboard/layout changes.
The parameter picker also scrolls when its content exceeds available height.

Project is first, followed by Scheduled, deadline, waiting date and priority.
Pills show an icon and the current value, or only the icon when unset. Their
accessible labels retain the attribute name. Project accepts existing or new
names; priority offers None, Low, Medium and High. A selected pill shares a
native glass identity with its anchored picker. Other pill surfaces disappear
while it is open to prevent their glass from merging into the panel.

The user review on 2026-10-23 supersedes the issue's intermediate
Today/Tomorrow/Choose day menu: Scheduled opens the calendar directly, without
an enable switch. Deadline and waiting date retain independent date/time controls.
Opening a parameter alone does not change a stored date. Choosing a value
changes the draft; Done can confirm the displayed date for an unset attribute.
An outside tap dismisses the picker only. The next outside
tap, collapse control, Command-Return or Escape validates, saves and collapses.
Blank descriptions and persistence failures keep the draft and actionable error.
No Cancel, completion Undo or draft restoration is added.

`TaskRowDraft` in Core owns title validation, Scheduled calendar boundaries
and the patch restricted to description, project, priority, scheduled, due and wait. Hidden fields
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

The editor keeps one persistent scroll subtree across keyboard and size changes.
Its initial height accommodates the 44-point collapse control and its padding;
subsequent height comes from measured content, capped by the available viewport.
The first measurement does not start a second animation alongside row expansion;
later content-height changes retain their resize animation.
Position matching avoids stretching title and metadata. Intrinsic row content is
pinned to the top of the List cell while its height animates; the completion
circle also uses top alignment when an unadorned task expands. Only clipped editors
request a scroll, including after a height change. The saved record remains
visible during the frozen-list handoff, preventing an old-title flash.
Picker scrim/layout transitions use identity so their outgoing hit area cannot
intercept the first tap after dismissal; the glass effect owns its morph.

Scheduled is also the label in supporting forms, detail, series transitions,
Reminders review and App Intents. Storage keys and existing shortcut identities
remain unchanged. Supporting forms retain their existing organization.

## Verification

Core tests cover independent planned/deadline/waiting values, hidden fields,
blank-title rejection, real boundary-level write failure, occurrence/sibling
scope, recurring-template rejection and chosen-day normalization over Paris DST.

`TaskRowEditingUITests` exercises save/relaunch, invalid draft retention,
parameter-first outside dismissal, the direct Scheduled calendar, focused date
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

## Initial implementation results (before the 2026-10-23 refinement)

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

## Initial UI report (historical)

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

## Refinement verification in progress (2026-10-23)

The Core suite passed all 168 tests, including project/priority persistence and
removal while preserving independent dates and opaque attributes. The signed
simulator build succeeds with the explicit horizontal clipping boundary.

Before that final clipping modifier, all five row-editing methods passed on
iPhone (`/tmp/tsk-61-refinement/phone-final.log`). The preceding build also
passed the existing durable edit/completion journey. Actual frame inspection
confirmed that making the first height measurement nonanimated removes the
large initial whole-row excursion; edited titles stay visible through collapse.

iPad normal light/dark picker and collapse flows passed before clipping, but
native recordings exposed glass pill foreground escaping the narrow sidebar.
An explicit clip was added to the horizontal scroll view. Its native visual
verification and the remaining iPad matrix are pending: Xcode and simulator
launches repeatedly exhausted this Mac's disk space even after task-owned
temporary builds and obsolete captures were removed. The final clipping build
succeeded, but the following simulator launch stalled before the first row
could open. No passing result is claimed for that attempt.

Both owned simulators are shut down. The refreshed report is pending final
captures; the report above is historical and does not show the new pills.

### Canonical refinement CI follow-up

Run `39953658735` on `602a5cf` built both app targets, but both UI lanes
failed. CI iPad screenshots confirm that `.clipped()` alone still allows
pill foreground and glass to escape the sidebar. The follow-up composites
that scroll view before clipping; its native result is pending the next run.
The lower-row iPad journey also exposed an information control under the tab
bar. Row bounds are now measured after final sizing, and reveal reacts to
position changes as well as height changes. The existing visibility assertion
now waits for the bounded reveal to finish without weakening its geometry gate.

CI also exposed locale-dependent calendar queries, full-width attribute swipes
that overshot at large text sizes, and a project Done tap during keyboard
relayout. The affected tests pin English US calendar labels, use bounded drags,
and use existing stable-keyboard control admission before Done. Other failing
Share, Spotlight, widget and annotation journeys were left unchanged. The next
canonical run must establish both the fixes and their visual outcome.

Swift parsing, all 14 UI-selection tests and diff whitespace checks pass for this follow-up. No new local
simulator run was attempted while disk space remained exhausted. The extracted
CI screenshots and native recordings remain under
`/tmp/tsk-61-refinement/ci-ipad-all` and `ci-iphone-all`.

### Rendering-boundary correction and disk recovery

Native capture on `42f5523` confirmed that compositing before the scroll clip
still did not contain the root glass renderer. The final implementation gives
the horizontal pill stack its own nearest `GlassEffectContainer`, inside the
clipped scroll view. A temporary selected-pill proxy and the floating picker
share the root container and identity, preserving the native morph without
extracting the complete scrolling strip into the root renderer. The proxy
preserves the full pill geometry within its visible clip, follows active row
movement, and freezes the return target during dismissal. The picker anchor
stays stable while editing changes the pill's value or width.

Row reveal now observes whether the editor crosses the viewport boundary,
rather than retargeting an animation for every changing scroll coordinate.
The outside-picker test chooses a visible backdrop region that excludes the
picker, native bars and keyboard. The scrolling helper taps the actual visible
pill fragment rather than asking XCTest for an offscreen activation point.
Keyboard admission accepts both a visible software keyboard and native text
input without a positive-height software keyboard.

The final signed simulator test build and 14 UI-selection tests pass. Native
captures establish containment on iPad in normal light/dark and accessibility
XXXL states. All five iPhone row-editing methods pass in
`/tmp/tsk-61-refinement/phone-verified.xcresult`. On the same final app source,
four iPad methods pass in `pad-verified.xcresult`; its durable-edit method
exposed the offscreen-hittability issue above and passes after the helper fix
in `pad-durable.xcresult`. The final app-source patch is unchanged between
those runs (SHA-256 `9668d2e19a95142ce0d9a1445141db546127ac3e772f007d67cd480b9c4dc0b2`).
The iPad software-keyboard element reported zero height during native text
input; visible docked keyboard geometry is verified on iPhone. Both devices
are now Shutdown, the temporary iPad is deleted, and Simulator is quit.

The authorized iOS 18.1 runtime was removed from the installed runtime list;
iOS 27.0 and 27.1 remain Ready. Free space reached 3.7 GiB after removal.
macOS retained the associated 8.2 GiB MobileAsset download with a never-collect
policy; removing that asset requires the pending administrator authentication.
A temporary iPad used during recovery was stopped and deleted. Restarting the
simulator service with no booted devices cleared the original iPad's stale
Shutting Down state, allowing its existing data to be reused.

### Refreshed visual report

`/Users/julesseguin/.local/share/ui-reports/tsk/label-and-implement-with-pr-issue-41/20261023-refinement/report.html`

Measured size: 4,537,245 bytes. The single HTML contains 129 screenshots,
including before/after interaction comparisons and labelled iPad crops,
and ten actual native animation clips. At 390 px, Chrome decoded all 129
images, opened all 54 sections, measured document width 390 px and verified
image enlargement and embedded native clip playback. Native frames show contained iPad pills, picker morphs
and the retained revised title through collapse. Physical frame pacing,
spoken VoiceOver and the other explicitly listed capture gaps remain open.
Canonical CI on the pushed head is still required; the latest completed CI
run on `42f5523` had UI failures and is not evidence for this follow-up.
