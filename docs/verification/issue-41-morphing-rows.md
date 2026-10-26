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
policy; removing that asset requires administrator authentication. The user could not
access the Mac, so that authentication prompt was cancelled and the cache remains.
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

## Fixed-header follow-up (2026-10-23)

The user's second review replaces the moving title/checkbox and collapse arrow
with one shared header. Only the lower section reveals attributes; compact
project/deadline metadata fade as the controls appear. The multiline title uses
a bounded native text field, including internally scrolling long text. Project
and priority now use system menus containing selection pickers. Creating a new
project retains the glass text-entry container. Calendars are measured before
the selected pill morphs into their glass container.

The new fixed-header regression fails on the preceding `bcc56d6` app: expanding
moves the title 12 pt horizontally. Endpoint assertions alone missed a separate
53 pt transient vertical excursion in early follow-up drafts. Actual native
frames traced that excursion to native List hosting-height animation. A draft
that reserved all editor space immediately kept the header fixed but made
neighbouring rows snap, so it was discarded. The final lower reveal samples
elapsed monotonic time and updates layout height with implicit List animation
disabled. Its height and the neighbouring rows can then progress together;
Reduce Motion applies the target directly. The original completion mask is
preserved.

All seven iPhone row-editing methods pass in
`/tmp/tsk-61-refinement/phone-bottom-continuous.xcresult`. The native film keeps
the first checkbox centre at 437.5 px through all 234 frames sampled from the
opening/closing interval; neighbouring-row detection found 18 intermediate
positions between its compact and expanded endpoints. These are visible-pixel
checks in a simulator, not physical-device frame-pacing acceptance. The native
clips also show the system priority menu and the Scheduled glass transition.

The same final app source covers all seven iPad row-editing methods with passing
results across `pad-bottom-continuous.xcresult` and `pad-bottom-menu.xcresult`.
The first run passed five row methods and the existing Upcoming completion
journey, but its appearance method timed out before app bootstrap as disk space
reached zero. Its native New Project selection also missed activation: the
failure hierarchy and per-test film still show the native menu, with no custom
picker. The test now uses the existing settled-geometry centre-tap helper for
native options. The appearance, header and complete durable-edit methods pass
on rerun; its valid native recording shows opening/closing, the system priority
menu and the Scheduled morph on iPad. The original full iPad recording was
corrupted at disk exhaustion and is not evidence.

The verified App-source patch relative to `bcc56d6` has SHA-256
`b3281ce30047585c44f4380c6a1fbbe473660a34245ec3603130a6b01dfa75ef`.
Signed simulator test builds and all 14 UI-selection tests pass. Core behavior
is unchanged since the preceding 168-test pass. Two independent review axes
found zero remaining definite standards violations and zero remaining definite
spec findings after the neighbouring-row snap was corrected. Physical-device
frame pacing, physical input, spoken VoiceOver, system Reduce Motion and moved
Stage Manager/floating-keyboard geometry remain unverified. Canonical CI on
the pushed follow-up is still required.

The existing iPhone description-edit/completion/relaunch and Upcoming
completion/removal/label journeys both pass in
`/tmp/tsk-61-refinement/phone-bottom-regressions.xcresult`.

Final report, local to this Mac:
`/Users/julesseguin/.local/share/ui-reports/tsk/label-and-implement-with-pr-issue-41/20261023-bottom-reveal/report.html`

Measured size: 4,733,189 bytes, with 172 screenshots and ten actual native clips.
Chrome at a 390 px viewport decoded all 172 images, expanded all 70 sections,
measured a 390 px document width and verified image enlargement and native
video playback. Full captures and labelled iPad crops remain paired; differences
in initial picker values and missing exact baselines are disclosed. Owned
simulators were shut down and the report's Chrome tab was closed.

### Canonical CI: outside-tap admission

Run `40021090247` on `78abe51` passed all seven iPad row-editor methods and six
of seven on iPhone. The iPhone durable-edit method failed its blank-title
validation assertion. Its native failure recording and hierarchy show a test
input error: the outside-tap helper sampled keyboard top 722 pt, then tapped
`(193.0, 454.2)` after the keyboard moved to top 418 pt. That tap typed `T` into
the previously blank title, so it never requested a save. The helper now uses
the existing control admission policy and an element-relative centre tap. With
a visible keyboard it requires matching keyboard/control geometry in successive
samples and rejects overlap before delivering input. Validation assertions are
retained.

The same CI run also failed unrelated iPhone Share, Spotlight, independent
keyboard and widget journeys. iPad's annotation journey exceeded the 20-second
admission deadline while accessibility reads took 30.9 seconds despite returning
valid visible geometry. Those tests and their timeouts were left intact. Core,
persistent replica and signed IPA checks passed. New-head canonical CI remains
required; the visual report retains the unchanged App source at `78abe51`.

The focused local follow-up also reproduced a missed native New Project menu
selection with the menu still present. Native options now use the existing
picker helper, which verifies the expected menu choices and stable ancestor
geometry before a real centre tap. A disk-exhausted iPad attempt crashed Xcode
while writing its result bundle and is not counted as passing evidence.

The signed test build passes. The complete focused iPhone journey passes in
`phone-outside-admission.xcresult`, including two matching keyboard/backdrop
samples before blank-title validation, save, relaunch and independent dates.
After adopting native-picker admission, iPad reached the project editor and
blank-title validation, but repeated local runs exhausted disk space and Xcode
could not finish their result bundles, even without duplicate video recording.
No full passing result is claimed for those iPad follow-ups. Local retries
stopped; canonical CI must verify the final harness. App UI code is unchanged.

### Compact alignment and continuous date surface

The compact checkbox had been aligned with a 44-point title field, leaving it
above the center of rows with project/deadline metadata. The compact title and
metadata now form one measured header; the checkbox centers beside that header,
and the metadata keeps its layout space while fading during bottom expansion.
The title's extra minimum height applies only to rows without metadata.

The previous date transition exchanged two separate glass effects while fading
the calendar in its final layout. The replacement keeps one glass surface and
animates its frame, position and corner radius between the visible pill and the
measured picker. The expanded placement is anchored at opening so typing a new
project cannot move the container; the return follows the current pill bounds.
Reduce Motion applies the final geometry directly. Scheduled, Deadline and
Waiting keep their existing native graphical pickers and independent values.

Attribute pills now use caption text, 10-point horizontal padding and a
32-point minimum visible height. Their labels retain a minimum 44-by-44-point
touch area, including icon-only values. Native project and priority menus remain
system menus.

The signed simulator test build passes. The focused iPhone run in
`/tmp/tsk-61-small-controls/phone-final.xcresult` passes
`testExpansionKeepsHeaderInPlace` (including compact header centering) and
`testCompactControlsAndDateSurface` (all three date controls, opening and
closing). The initial icon-only touch-area failure was reproduced before the
44-point minimum hit area and passes with that fix. A native per-test recording
of the date transition shows intermediate surface sizes rather than an opacity
handoff; the compact header screenshots also show the corrected visual center.

The broader iPhone edit/save journey reaches native project/priority selection,
new-project entry, direct date selection, and blank-title validation. Its final
save/relaunch assertion fails with the visible error `Local task storage failed:
Setting journal_mode=WAL`. During that run the Mac also rejected temporary-file
creation with `no space left on device`; the native recording is zero bytes.
This is not claimed as a passing persistence journey or usable motion evidence.
Storage code and assertions are unchanged. The valid earlier date-transition
recording is in `phone-evidence/AE039B4D-9CEB-49C8-9B5B-E008D5F71F27.mp4` under
the same temporary directory. Canonical CI remains required for the full suite.

Both focused methods also pass on iPad in
`/tmp/tsk-61-small-controls/pad-final.xcresult`. The valid final-source native
recording `pad-final-motion.mp4` shows opening/closing the three date controls;
the recorded display is rotated relative to the app after orientation setup,
so inspection uses a counterclockwise rotation without synthesizing frames.
The initial iPhone transition recording predates the final compact spacing,
minimum hit width and fixed expanded project anchor; final-source date and
header functional checks pass on both families. Full-suite, dark/large-text,
physical-device frame pacing and spoken accessibility checks were not repeated
for this refinement. All simulators booted for it were shut down and Simulator
was quit. No new HTML report was generated, as requested.

### Native attribute presentations and stable checkbox tint

The completion button used the disabled state while any row was being edited.
That changed its native tint. Completion now keeps its existing appearance and
blocks input through hit testing, accessibility interaction eligibility and an
action guard while editing. Its actual completion-feedback disabled state is
unchanged. A pixel comparison of the same iPhone checkbox region fails on
`0fe5f65` (1,147 blue pixels compact, zero expanded) and passes with the fix
(1,147 in each state).

Project and priority menus had native menu chrome around a separately styled
glass label, while dates used only that custom label. All attribute controls
now use the same small native glass button style, capsule shape and caption
label. The captured iPhone Project, Scheduled and Deadline borders have equal
76-pixel sampled vertical extents at matching positions. Their widths follow
their values; their outer layouts keep a 44-point minimum size.

The manual date-picker surface and its position/height/corner animation have
been removed. A native SwiftUI popover hosts the graphical DatePicker (or the
new-project TextField). An explicit matched transition source and native zoom
transition connect the control to the presentation. The initial native popover
without that explicit connection still left a separate source pill; that
intermediate version is not the final fix. The final iPhone native recording
shows the source-to-popover transition and its return. Outside dismissal keeps
the task draft open; Done and date removal dismiss the picker independently.
Content fits its intrinsic size or scrolls when constrained.

Apple describes native presentation continuity in
[Build a SwiftUI app with the new design](https://developer.apple.com/videos/play/wwdc2025/323/)
and the source/destination API in
[zoom(sourceID:in:)](https://developer.apple.com/documentation/swiftui/navigationtransition/zoom(sourceid:in:)).

The signed simulator test build passes. Both focused iPhone methods pass in
`/tmp/tsk-61-native-popovers/phone-zoom.xcresult`. The attribute journey now also
checks outside dismissal, native priority selection, the native project menu,
New Project presentation and returning to the same expanded draft. The color
comparison passes on its exported captures. The valid native recording is
`phone-zoom-motion.mp4` in that directory. The final iPad build adds a guarded
dismissal binding so a closing popover cannot clear another parameter's state.

CI run `40037615974` on `0fe5f65` stopped before XCUITest: the added regression
method had not been reflected in the selection tests' fixed method counts.
Those expectations and their coverage table now include it (21/18 smoke,
72/62 full). All 14 selection checks pass. This changes the expected counts,
not the tier selectors or existing coverage. Full canonical CI is required on
the new head. Persistence, physical-device input/frame pacing, spoken
accessibility, dark/large-text and system Reduce Motion were not reverified in
this focused refinement. No HTML report is generated, per user instruction.

The final iPad attribute journey passes in `pad-zoom.xcresult`. Its subsequent
header method could not reach app bootstrap while disk space fell to 109 MiB.
After removing superseded task-owned temporary exports, the same final source
passes the standalone header method in `pad-header.xcresult`. The iPad film is
zero bytes and is not motion evidence; the iPhone native film remains valid.
Both device families therefore have passing focused header and native-attribute
coverage, with the iPad results spanning two runs. All owned simulators were
shut down after verification and Simulator was quit.

### Chosen motion A (2026-10-25)

Jules chose A from the throwaway motion study. The original question, runnable
A/B/C comparison and verdict are archived on
[prototype/issue-41-row-motion](https://github.com/Julesseg/tsk/tree/prototype/issue-41-row-motion/App/Prototypes/task-row-motion),
with a [decision pointer on issue #41](https://github.com/Julesseg/tsk/issues/41#issuecomment-6394662730).
The implementation branch contains only A.

Compact rows now have four points of vertical padding per edge. Expansion opens
12 more points above and below the selected row while shifting the list up by
12 points, keeping the title and checkbox at the tap position. Near the top
viewport edge, the upward shift and matching top padding clamp together. The
bottom still opens space for the editor. Existing scrolling keeps lower rows
and keyboard-focused controls visible.

One presentation progress value drives editor height, control/metadata fades,
card appearance, surrounding padding, list translation and neighbor dimming.
Opening uses a 180 ms quartic ease-out; closing uses 140 ms, scaled for a partial
reversal. The separate metadata/background animations and fixed 350 ms cleanup
wait are removed. Layout updates retain disabled implicit List animations to
avoid the native hosting-cell recentering found in the earlier refinement.
Reduce Motion applies the final presentation state directly.

The signed simulator test build and all 14 selection-routing checks pass. The
new middle-row regression is included in both smoke lanes (22 iPhone/19 iPad
methods; full coverage is 73/63). It checks compact height, the fixed selected
header, the earlier row's 12-point upward shift, movement below the editor and
restoration after collapse. Both geometry regressions pass on iPhone and iPad.
The iPad native attribute/menu/popover journey also passes. The iPhone recording contains 97 encoded source frames with all three
checkboxes detected during the middle-row opening/closing study: the selected
center stays at 582 px, the earlier center moves 426 to 390 px, and the following
center moves 738 to 1140 px. The same changing frames show dimming and movement;
there is no separate dim-only phase. These variable-rate simulator source frames
were not interpolated and do not establish physical-device frame pacing.

Local evidence lives under `/tmp/tsk-61-motion-a/`: `build.log`,
`phone-geometry.xcresult`, `phone-geometry-motion.mp4`, exported native captures,
`phone-native-frames.json` and `phone-motion-summary.json`. No HTML UI report is
generated, per user instruction.

The valid iPad recording is `pad-geometry-motion.mp4` (portrait recording canvas
with the landscape app rotated inside it). After rotating decoded source frames
for measurement, all 74 frames with the three study checkboxes keep the selected
center at 327.5 px. The geometry tests independently verify the 12-point nudge.
The corresponding result bundle and native captures are `pad-geometry.xcresult`
and `pad-captures/`.

The broader iPhone run passed appearance/accessibility overflow, native controls,
long-title keyboard bounds, failed-draft retention, lower-row visibility and
Upcoming regrouping. The outside-save journey reproduced the prior CI failure:
after Select All and Delete in New Project, typing failed because the TextField
lost keyboard focus. A minimized native sequence reproduced it again in
`phone-project-red.xcresult`.

The picker duplicated its content inside `ViewThatFits`. Removing a project's
value also removes the Remove Project button and changes the content's height.
A single measured, height-bounded ScrollView now preserves the content identity
as that height changes. The same minimized sequence passes without refocusing
or changing the text helper in `phone-project-green.xcresult`. The full journey
also now explicitly waits for keyboard disappearance after its Hide Keyboard
button, before selecting an outside-save target; this covers the keyboard
snapshot race seen in the prior iPad CI log.

The restored iPhone picker/appearance checks pass with the stable container.
The full save journey proceeds through validation, durable relaunch and
independent dates/project/priority readback, then exposed a test-only hit-area
failure. The enabled Waiting control was fully visible but its CGRect width
was `43.99999999999994` instead of 44, so the helper repeatedly scrolled instead
of tapping. A shortened fixture reproduced the exact value in
`phone-pill-probe.xcresult`. Hit-area admission now allows 0.001 pt of numeric
rounding; app control dimensions and hit targets are unchanged. Temporary
fixture changes and debug instrumentation were removed before the final build.

The original complete iPhone outside-save/validation/relaunch journey passes in
`phone-durable.xcresult` after the rounding correction, including the previously
blocked Waiting picker and plain-row anchored collapse. The stable-container
appearance/accessibility and complete native-control checks pass in
`phone-final.xcresult`; that earlier bundle also retains the diagnosed rounding
failure, so it is not described as an entirely passing run. The final source
build is `build-verified.log`. Geometry, keyboard, failed-draft and Upcoming
checks are retained in the focused bundles above; the entire canonical suite
still belongs to CI on the pushed head.

The original complete iPad outside-save/validation/relaunch journey also passes
in `pad-durable.xcresult` on the final source, including New Project replacement,
invalid-draft retention, keyboard dismissal, saved attribute readback, all date
pickers and anchored plain-row collapse. Its native recording is
`pad-durable-motion.mp4`. All owned simulators were shut down after their runs;
the prototype browser tab was closed while leaving the pre-existing browser open.
System Reduce Motion, physical-device input/frame pacing and spoken VoiceOver
were not verified. Canonical CI is required on the new pushed head.

## Display-linked expansion and observation isolation (2026-10-25)

The follow-up complaint concerns pacing, which the earlier endpoint geometry
assertions did not establish. A quiet native fixture, with the XCTest driver
idle and the real clock enabled, reproduced a first timer-driven progress jump
from 0 to 0.837. The fixed 16 ms sleep also added its delay after each update's
layout work.

TaskRowMotion now uses CADisplayLink's presentation timestamps. Its lifetime is
bounded by completion/cancellation, and replacement motion retains ownership of
the shared progress. The chosen A curve, 180/140 ms durations and spacing remain.
The iPhone plist opts in to the display-link frame-rate range. Preferred rates
are requests, not measured rendering guarantees.

Progress reads now live in small modifiers for offset, spacing and fades.
The task header and List construction do not observe each progress update.
Editor controls have a separate content view and a stable session reference
date. Row geometry is cached without writing SwiftUI State on each measurement.
Live bounds update only a dedicated dismissal overlay; separate visibility
bounds and an animation guard defer scrolling until expansion finishes. This
preserves immediate control/outside taps without letting intermediate geometry
retarget the scrolling animation.

A controlled native comparison kept the same CADisplayLink clock, curve,
durations, real date and five actual open/close cycles, with the XCTest driver
idle during motion. The before variant used the previous row/content/geometry
implementation with that same display clock; the after variant used this
observation refactor. Temporary body counters recorded:

| Evaluation or measurement | Before | After |
| --- | ---: | ---: |
| Editor control content | 98 | 19 |
| Selected row body | 90 | 35 |
| Neighbour row bodies | 160 | 50 |
| Outer screen body | 10 | 10 |
| Outer task-list body | 16 | 15 |
| Reveal wrapper body | 98 | 116 |
| Display-linked updates | 55 | 93 |
| Median callback interval within motion | 33.333 ms | 16.672 ms |

The work reduction is concentrated in row/control construction. The small
reveal wrapper updates more often as more display callbacks arrive. These are
body counts and callback intervals, not presented-frame FPS or a device hitch
ratio; the largest observed callback gap remains 49.983 ms. Raw counters,
timestamps, controlled-variant harness and result bundles are under
`/tmp/tsk-61-frame-pacing/`: `body-count-comparison.json`, `body-count.py`,
`body-before.xcresult` and `body-after.xcresult`.

The clean candidate passes six iPhone methods in `phone-isolated.xcresult`:
fixed first/middle headers, compact native controls/calendars, complete outside
save/validation/relaunch, lower-row keyboard visibility and Upcoming regrouping.
Four iPad methods pass in `pad-isolated.xcresult`: both header/spacing studies,
native controls/calendars and lower-row keyboard visibility. The test-selection
suite passes all 14 checks. The restored production test build passes after
removing the temporary body counters and autoplay.

Frame studies use the encoded native `phone-isolated-motion.mp4` and
`pad-isolated-motion.mp4`. During the visible All-list middle-row study, all 91
iPhone source frames retain the selected checkbox centre at 582 px; all 89 iPad
source frames retain it at 327.5 px after rotation for inspection. The earlier
and following rows traverse intermediate positions and return on collapse.
These measured windows exclude app/tab entry and are recorded in
`phone-final-study.json` and `pad-final-study.json`. No frames were interpolated.
All task-owned simulators were shut down after their runs.

The Hitches Instruments template is unsupported on this simulator, and the
XCTHitchMetric attempt returned no measurements. Neither is reported as a
passing performance gate. Display-link probes still contain approximately
33 ms intervals; their cause is not attributed solely to the simulator.
Physical-device hitch/frame-pacing acceptance, system Reduce Motion and spoken
VoiceOver remain unverified. Canonical CI is required on the pushed head.
Temporary probes/autoplay and altered fixtures were removed; no HTML UI report
was generated.

## Scrollable focus and prototype controls (2026-10-25)

Expanded drafts now allow native list panning. The outside-tap recognizer lives
on the workspace, while the existing accessible save/close regions no longer
intercept touches. A drag leaves the draft open; a tap outside the row
still validates and saves. Initial expansion and viewport/keyboard
changes retain visibility correction, but changing scroll coordinates no longer
retarget it. All/Today and Upcoming share this behavior.

An 8% black scrim follows the shared reveal progress across the app and its safe
areas. Its rounded cutout follows the expanded row, clipped to the list viewport,
so the card stays undimmed without exposing navigation chrome when scrolled.
The chosen A clock, curve and durations are unchanged.

The archived `prototype/issue-41-row-motion` capsule design is translated to a
26-point minimum visible height, thin outline, nine-point horizontal padding,
small icon/value labels and adaptive system colors. The 44-point interaction
areas, native Project/Priority menus, and matched-source date popovers remain.

The lower-row native regression now edits a title, hides the keyboard, drags
from a surrounding row, verifies the list moved without collapsing the draft,
then scrolls back and checks the unsaved text before outside saving.

The signed simulator build and all 14 test-routing checks pass. Native iPhone
fixed-header, picker/menu and complete outside-save/validation/relaunch checks
pass in `phone-interaction.xcresult`, `phone-final-visual.xcresult` and
`phone-pickers-save.xcresult`. The final dark-mode overflow/keyboard/scrolling
sequence passes in `phone-keyboard-hit-test.xcresult`.

The equivalent iPad overflow sequence passes in `pad-scroll-overflow.xcresult`.
The iPad light/dark and accessibility XXXL journey passes in `pad-final.xcresult`;
that bundle also retains an initial scrolling-fixture failure because twelve
neighbours fit on the taller iPad after keyboard dismissal. The regression now
uses twenty-four neighbours so both device families have a real scroll range.

A clipped-viewport tap-test candidate incorrectly closed the iPhone draft when
Hide Keyboard changed the viewport. The same dark-mode sequence is red in
`phone-scroll-overflow.xcresult` and green with live row-bound tap detection in
`phone-keyboard-hit-test.xcresult`. Viewport clipping applies only to the visual
scrim cutout.

Actual native captures under `/tmp/tsk-61-refinements/` show the flat capsules,
retained draft after scrolling and continuous dimming. In the final light iPhone
capture, sampled background/top/bottom safe-area pixels change from RGB 255 to
235 while a blank expanded-card pixel remains RGB 255; raw values are retained
in `dimming-pixels.json`. Every task-owned simulator was shut down after its run.

Canonical CI is required on the pushed head. Physical-device gestures/frame
pacing and spoken VoiceOver are not established by these simulator checks.
No HTML UI report was generated.

## Tighter expanded-row spacing (2026-10-26)

Reduced the editor's vertical stack spacing from 16 to 4 points, removed its
8-point top inset and the attribute strip's vertical padding, and reduced the
bottom inset to 8 points. Header geometry and 44-point control hit areas remain
unchanged.

The signed simulator build and the native iPhone fixed-header and picker/menu
checks pass in `/tmp/tsk-61-spacing/spacing.xcresult`. Exported captures confirm
the tighter gaps above and below the pills. The owned simulator was shut down.
The iPad suite and physical-device interaction were not rerun for this spacing
change; canonical CI remains required on the pushed head.
